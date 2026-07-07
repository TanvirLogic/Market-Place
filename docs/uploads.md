# Upload System — How It Works

This app uploads **everything** (course videos, lesson videos, resources,
course thumbnails, intro videos, avatars, cover photos) through **one** system,
built on the industry-standard [`background_downloader`](https://pub.dev/packages/background_downloader)
package. Uploads run in the OS background (iOS `URLSession`, Android
`WorkManager`) and survive the app being backgrounded or killed.

All code lives under `lib/features/uploads/`.

---

## 1. The mental model — every upload is 4 steps

Whether it is a 2 GB course video or a 40 KB avatar, the flow is identical:

```
 ┌──────────┐   ┌──────────────┐   ┌────────────┐   ┌────────────┐
 │ 1. INIT  │──▶│ 2. TRANSFER  │──▶│ 3. COMPLETE│──▶│ 4. CALLBACK│
 │ ask our  │   │ send bytes   │   │ tell S3    │   │ tell our   │
 │ backend  │   │ to S3 via    │   │ "done",    │   │ backend the│
 │ for URLs │   │ presigned    │   │ get final  │   │ file URL   │
 │          │   │ PUT(s)       │   │ URL        │   │            │
 └──────────┘   └──────────────┘   └────────────┘   └────────────┘
```

### The S3 rule (size decides direct vs multipart)

```
fileSize < 15 MB   → DIRECT  : one PUT to a single presigned URL.
                               Step 3 (complete) is skipped — the object is
                               already stored. Go straight to callback.
fileSize >= 15 MB  → MULTIPART: N PUTs, one per part, each with a byte Range.
                               Collect an ETag per part, then step 3 sends all
                               the ETags to finalize the object.
```

The **backend decides** by returning `isMultipart` in the init response — the
client just follows whichever shape it gets. (`15 MB = kMultipartThresholdBytes`.)

---

## 2. The key trick — parts upload by byte Range, no file slicing

For multipart, we do **not** cut the video into temp files. `background_downloader`
supports a `Range` header on a binary upload:

```
part 1 → Range: bytes=0-104857599        (first 100 MB)
part 2 → Range: bytes=104857600-...
part N → Range: bytes=419430400-         (no end = to end of file)
```

The package reads exactly that slice from the original file and PUTs it. This is
what makes multipart correct on **every** platform (it also fixed a historical
iOS bug where the whole file was sent per part).

---

## 3. The layers (who does what)

```
 UI (screens, sheets)
        │  calls e.g. addModuleLessonToQueue(...)
        ▼
 UploadQueueProvider           presentation/upload_queue_provider.dart
   • ChangeNotifier the UI listens to
   • same public API the old system had (drop-in)
   • maps int queue ids ↔ string job ids
   • notification-permission gate
        │
        ▼
 UploadService                 service/upload_service.dart
   • THE state machine: init → transfer → complete → callback
   • builds parts with byte ranges, aborts on failure
   • emits an UploadJob on every state/progress change
        │              │
        │              ▼
        │      UploadRoutes          service/upload_routes.dart
        │        • per-type endpoints + request bodies (all 8 asset types)
        │
        ├────▶ S3UploadApi           data/api/s3_upload_api.dart
        │        • init / complete / abort / callback HTTP
        │        • uses getNetworkCaller() → bearer auth + 401 refresh for free
        │        • callback sends a real Idempotency-Key header, 409 = success
        │
        └────▶ BackgroundUploadEngine engine/background_upload_engine.dart
                 • wraps background_downloader
                 • MemoryTaskQueue (limits concurrent parts)
                 • reads S3 ETag from responseHeaders['etag']
                 • reports aggregated progress per job
                     │
                     ▼
                 UploadTaskFactory   engine/upload_task_factory.dart
                   • builds each UploadTask (binary PUT, Range header,
                     per-job group, taskId encodes job+part)
```

### Data models (`data/models/`)
- `upload_enums.dart` — `UploadAssetType` (which asset), `UploadJobState` (lifecycle).
- `upload_job.dart` — `UploadJob` (one upload) + `UploadPart` (one ranged part) +
  the 15 MB constant. `etagPayload` produces the `[{partNumber, eTag}]` list for
  the complete call.
- `s3_init_response.dart` — parses the init response (direct or multipart, plus
  the nested `data.thumbnail` / `data.video` course shape).

---

## 4. A concrete example — uploading a 500 MB lesson video

1. UI calls `provider.addModuleLessonToQueue(videoPath, title, moduleId, ...)`.
2. Provider checks notification permission, creates a job, hands it to `UploadService`.
3. `UploadService`:
   - **INIT** → `POST /course/module/lesson/upload {videoFilename, videoContentType, videoFileSize, moduleID}`
     → backend returns `isMultipart: true`, `uploadId`, `key`, `parts:[{partNumber, uploadUrl} × 5]`, `fileUrl`.
   - Builds 5 `UploadPart`s with byte ranges.
   - **TRANSFER** → engine enqueues 5 binary PUT tasks (max 3 at a time) with
     `Range` headers. Each finished part yields an ETag from its response header.
   - **COMPLETE** → `POST /video-post/upload/complete {key, uploadId, parts:[{partNumber, eTag} × 5]}`
     → returns the final `fileUrl`.
   - **CALLBACK** → `POST /course/module/lesson {title, moduleId, videoUrl, duration, fileSize}`
     with header `Idempotency-Key: <jobId>_callback` (409 counts as success).
   - Job state → `completed`. UI updates via the stream.
4. If any part fails, the S3 session is **aborted** (`POST /video-post/upload/abort {key, uploadId}`)
   and the job is marked `failed` (user can retry).

An avatar (< 15 MB) skips step 3: init → one PUT → confirm callback
(`PUT /profile/avatar/confirm {fileUrl}`).

---

## 5. Background & app-kill survival

- The byte transfer runs natively (URLSession / WorkManager), so it continues
  when the app is backgrounded and can survive being killed.
- `FileDownloader().start()` (called on first use via `ensureStarted()`) turns on
  the package's persistent task database, resumes background events, and
  reschedules tasks that were killed.
- The package's own database is the source of truth for task status/progress and
  the response headers (where ETags live) — we intentionally do **not** keep a
  second database.

---

## 6. Per-type endpoints (all in `upload_routes.dart`)

| Type | init | complete | callback |
|------|------|----------|----------|
| video_post | `/video-post/assets/upload` | `/video-post/upload/complete` | `POST /video-post` |
| module_lesson | `/course/module/lesson/upload` | same | `POST /course/module/lesson` |
| resource | `/course/module/resource/assets/upload` | same | `POST /course/module/resource` |
| course / thumb | `/course/assets/upload` | same | `POST /course` |
| course_intro | `/course/assets/upload` | same | `POST /course/assets/upload` |
| avatar | `/profile/avatar/upload-url` | same | `PUT /profile/avatar/confirm` |
| cover | `/profile/cover/upload-url` | same | `PUT /profile/cover/confirm` |

To add a new asset type: add a case in `UploadRoutes.forJob` and a value in
`UploadAssetType`. Nothing else changes.

---

## 7. What was removed in the migration

The previous system had **three** overlapping uploaders. All are gone:
- `packages/upload_queue/` (custom package + hand-written Kotlin/Swift workers)
- `S3UploadService` (image path), `UnifiedUploadQueueProvider`,
  `VideoQueueUploadProvider`, `NativeBackgroundEngine`, `NativeUploadBridge`,
  `UploadQueueRepository`, `UploadPathStorage`.

`CourseUploadProvider` was slimmed to only hold picker/form state.
