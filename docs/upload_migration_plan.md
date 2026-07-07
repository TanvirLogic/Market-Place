# S3 Upload Migration — background_downloader + Hive

Replaces the custom `upload_queue` package + hand-written Kotlin/Swift workers
with the industry-standard **`background_downloader`** package for native
background transfer, and **Hive** for our own job/part metadata.

Verified facts (from official docs, background_downloader 9.5.5):
- **Binary PUT to presigned S3 URL**: `UploadTask(post: 'binary', httpRequestMethod: 'PUT', ...)`.
- **Byte-range part upload WITHOUT slicing the file**: add header `Range: bytes=START-END`
  to a binary UploadTask. "The Range header will not be passed on to the server."
  → each S3 part = one UploadTask pointing into the ORIGINAL file. No temp part files.
  (This is what fixes the old iOS whole-file-per-part bug for free.)
- **ETag capture**: `TaskStatusUpdate.responseHeaders` is `Map<String,String>?`,
  keys **lowercased** → read `responseHeaders['etag']`. Also `responseStatusCode` (int?),
  `responseBody` (String?), only populated on the FINAL status update.
- **Background + survive-kill**: iOS URLSession / Android WorkManager handled by the
  package. `FileDownloader().start()` resumes background events and
  `rescheduleKilledTasks()` retries tasks lost to app kill.
- **Concurrency**: `MemoryTaskQueue` (implements `TaskQueue`) with
  `maxConcurrent` / `minInterval`, registered via `FileDownloader().addTaskQueue(q)`.
- **Native setup**: Android needs Kotlin 2.1.0+. iOS default requires HTTPS URLs.

---

## The S3 rule (same for ALL asset types: video, resource, avatar, cover)

```
fileSize < 15 MB   → DIRECT   : 1 binary PUT to uploadUrl,       then complete? no → callback
fileSize >= 15 MB  → MULTIPART: N binary PUTs (Range per part),  then complete,   then callback
```

The **server decides** and returns `isMultipart` + either `uploadUrl` or `parts[]`.
We also compute the boundary client-side only to send the right `fileSize` and to
sanity-check. 15 MB = `15 * 1024 * 1024`.

---

## 4-step flow (unchanged API contract — matches current backend)

```
1. INIT      POST {initEndpoint}      → {isMultipart, uploadUrl?|parts[], key, uploadId?, fileUrl, totalParts}
2. TRANSFER  PUT presigned S3 URL(s)  → capture ETag header(s)         [background_downloader]
3. COMPLETE  POST /video-post/upload/complete  {key, uploadId, parts:[{partNumber,eTag}]} → {fileUrl}
             (multipart only; direct skips this)
4. CALLBACK  POST {callbackEndpoint}  {..., videoUrl/fileUrl, Idempotency-Key}
```
On failure after INIT (multipart): `POST /video-post/upload/abort {key, uploadId}`.

---

## New file layout  (`lib/features/uploads/`)

```
lib/features/uploads/
  data/
    models/
      upload_job.dart          // Hive: id, filePath, type, state, fileUrl, key,
                               //       s3UploadId, isMultipart, totalParts, partSize,
                               //       fileSize, progress, metadata(Map), createdAt
      upload_part.dart         // Hive: jobId, partNumber, rangeStart, rangeEnd,
                               //       eTag, done   (embedded list on job)
      upload_enums.dart        // UploadJobState, UploadAssetType
      s3_init_response.dart    // parse init (direct | multipart)
    hive/
      upload_hive.dart         // box open/register adapters, CRUD
    api/
      s3_upload_api.dart       // init / complete / abort / callback HTTP (uses existing NetworkCaller + auth)
  engine/
    bd_upload_engine.dart      // background_downloader wrapper:
                               //   directPut(job) , uploadPart(job, part) , listener→ETag
    upload_task_factory.dart   // builds UploadTask (binary PUT, Range header, group, taskId=jobId:part)
  service/
    upload_service.dart        // orchestrator: enqueue → transfer → complete → callback,
                               //   resume-after-kill, retry, abort, progress aggregation
  presentation/
    upload_queue_provider.dart // ChangeNotifier — DROP-IN replacement for UnifiedUploadQueueProvider
                               //   (same public method names: addToQueue, addModuleLessonToQueue,
                               //    addResourceToQueue, addCourseToQueue, cancelTask, retryFailed, tasks…)
```

Legacy (kept as backup, unwired):
```
lib/_legacy/upload/            // old S3UploadService, native_upload_bridge, upload_queue_repository
packages/upload_queue/         // left on disk but removed from pubspec dependency
```

---

## How multipart maps onto background_downloader (the key idea)

For a 500 MB video with `totalParts = 5`, `partSize = 100 MB`:

```
job.id = 42
 part 1 → UploadTask(taskId:'42:1', url:parts[0].uploadUrl, post:'binary',
                     httpRequestMethod:'PUT', headers:{'Range':'bytes=0-104857599'},
                     group:'uploads', filename/baseDir from Task.split(originalFile))
 part 2 → Range: bytes=104857600-209715199
 ...
 part 5 → Range: bytes=419430400-        (omit end = to EOF)
```
- All 5 enqueued into a `MemoryTaskQueue(maxConcurrent: 3)`.
- Listener collects `responseHeaders['etag']` per finished part → store in Hive `UploadPart.eTag`.
- When all parts `done` → step 3 complete with the collected ETags → step 4 callback.
- **Resume after kill**: on app start, `FileDownloader().start()` +
  `rescheduleKilledTasks()`; our service reads Hive, re-enqueues only parts with `done=false`.

Direct (<15 MB) is just one `UploadTask` (no Range) → on complete, no S3-complete
call needed (S3 already has the object at `key`), go straight to callback with `fileUrl`.

---

## Provider compatibility (so screens don't break)

`UploadQueueProvider` will expose the SAME surface the app already calls:
`tasks`, `activeUploadId`, `activeUploadProgress`, `pendingCount`, `completedCount`,
`failedCount`, `addToQueue`, `addModuleLessonToQueue`, `addResourceToQueue`,
`addCourseToQueue`, `addCourseIntroVideo`, `queueCourseEditAssets`, `cancelTask`,
`retryFailed`, `removeTask`. A thin `UploadTaskView` mirrors the fields the UI reads
(`id`, `state`, `progress`, `title`, `filePath`, `fileUrl`, `metadata`) so
`manage_module_provider.dart` / `module_card.dart` keep compiling with minimal edits.

Avatar/cover: `avatar_upload_provider` & `cover_upload_provider` call
`uploadService.uploadSync(...)` (await-to-completion, tiny direct PUT) instead of
`S3UploadService.uploadImage`, reusing the exact same engine.

---

## Stages (each ends: `flutter analyze` clean)

0. Deps + legacy backup (no behavior change yet).
1. Hive models + S3 API client + size rule.
2. background_downloader engine (direct + Range parts + ETag capture).
3. UploadService orchestrator (resume/retry/abort/progress).
4. UploadQueueProvider drop-in.
5. Rewire consumers (video/lesson/resource/course + avatar/cover).
6. Native config + analyze + tests.

## Open items / assumptions
- HTTPS: iOS requires https for presigned URLs. Backend base is currently http IP.
  Presigned S3 URLs are usually https already. If the INIT/complete/callback calls
  stay http, iOS ATS may need a temporary exception — flagged, not silently added.
- Direct upload needs no S3 "complete" call (object already stored). Confirmed by the
  old S3UploadService which only did get-url → PUT → confirm(callback).
