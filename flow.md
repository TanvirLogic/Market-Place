# Eduverse Upload System — Complete Flow (Beginner-Friendly)

This document teaches you **everything** that happens from the moment a user taps
"Upload Video" until the video is fully uploaded, assembled on S3, and the lesson
row is created on your server — including **every function, every API call, every
trigger, and every edge case**, even when the app is completely killed.

Read it top to bottom once. Then use the "Quick Reference" tables at the bottom
as a cheat sheet.

---

## 0. The Big Picture (read this first)

Think of the upload system as **4 layers**, each with one job:

```
┌───────────────────────────────────────────────────────────────┐
│ LAYER 1 — UI (Flutter widgets)                                 │
│   Buttons, progress bars. Lives only while a screen is open.   │
│   Example: UploadVideoScreen, UploadZone                       │
├───────────────────────────────────────────────────────────────┤
│ LAYER 2 — Provider (in-memory state, ChangeNotifier)           │
│   UnifiedUploadQueueProvider. Bridges UI ↔ the queue.          │
│   DIES when the app is killed. Rebuilt on next launch.         │
├───────────────────────────────────────────────────────────────┤
│ LAYER 3 — UploadQueue + Persistence (the brain)                │
│   The FIFO scheduler + SQLite database (upload_queue_v2.db).   │
│   The database is the SOURCE OF TRUTH. Survives app kill.      │
├───────────────────────────────────────────────────────────────┤
│ LAYER 4 — Native Engine (survives app kill)                    │
│   Android: WorkManager workers (UploadWorker, CompleteWorker,  │
│            CallbackWorker) + a Foreground Service.             │
│   iOS: background URLSession tasks.                            │
│   THIS is what keeps uploading after the app is dead.          │
└───────────────────────────────────────────────────────────────┘
```

**The golden rule:** The UI and Provider are *disposable views*. The **SQLite
database** and the **native OS workers** are the *permanent truth*. When the app
restarts, the Provider is rebuilt and simply *re-reads* the truth from the
database and the native layer. Nothing is lost.

**Key files:**

| Layer | File |
|---|---|
| UI | `lib/features/courses/presentation/screens/upload_video_screen.dart` |
| UI | `lib/features/manage_module/presentation/widgets/manage_module_add_lesson_sheet.dart` |
| Provider | `lib/features/courses/providers/unified_upload_queue_provider.dart` |
| Queue (brain) | `packages/upload_queue/lib/src/queue.dart` |
| Database | `packages/upload_queue/lib/src/persistence.dart` |
| Engine interface | `packages/upload_queue/lib/src/engine.dart` |
| Dart engine | `packages/upload_queue/lib/src/dart_http_engine.dart` |
| Native engine (Dart side) | `lib/features/courses/services/native_background_engine.dart` |
| Android worker | `android/.../upload/UploadWorker.kt` |
| Android bridge | `android/.../upload/UploadBridgeHandler.kt` |
| Android complete | `android/.../upload/CompleteWorker.kt` |
| Android callback | `android/.../upload/CallbackWorker.kt` |
| Android FGS | `android/.../upload/UploadForegroundService.kt` |
| iOS background | `ios/Runner/AppDelegate.swift`, `ios/Runner/BackgroundUploadManager.swift` |

---

## 1. The S3 Multipart Concept (the "why" behind everything)

Your videos are **300 MB – 3 GB**. You cannot upload that as one HTTP request —
if it fails at 2.9 GB you'd restart from zero. So we use **S3 Multipart Upload**,
which splits the file into **parts** (chunks) and uploads them independently.

The multipart "dance" has **4 server steps**:

1. **Init** — Ask the backend to start a multipart session. Backend calls S3's
   `CreateMultipartUpload` and returns:
   - `uploadId` — the S3 session ID
   - `key` — the S3 object path (e.g. `videos/uuid.mp4`)
   - `parts[]` — a **presigned URL** for each part (a temporary URL that lets you
     PUT one chunk directly to S3 without AWS credentials)
2. **Upload each part** — PUT each byte-range of the file to its presigned URL.
   S3 returns an **ETag** (a fingerprint) per part in the response header.
3. **Complete** — Send the backend the list of `{partNumber, eTag}`. Backend
   calls S3's `CompleteMultipartUpload`, and **S3 stitches the parts into one
   file**. (S3 does the joining, not your app.)
4. **Callback** — Tell your backend "the video is ready at this URL, create the
   lesson row."

> **The hard problem (the "S3 Catch-22"):** If the app is killed after the parts
> upload, the Dart code that would call step 3 and step 4 is **dead**. Our
> solution: steps 3 and 4 run **natively** (Android `CompleteWorker` +
> `CallbackWorker`, iOS background session), so they finish even with no app.

**Small files (< 15 MB, e.g. thumbnails)** skip multipart and use a single
presigned PUT (the "direct upload" path). Same lifecycle, simpler.

---

## 2. App Startup — Before Any Button Is Pressed

When the app launches, the upload system wakes up and reconnects to any work that
was happening before.

### 2.1 `initPlatformServices()` — `lib/app/native_init.dart`
Called during app boot. It:
- `MediaKit.ensureInitialized()` — video player setup (unrelated to upload)
- `UploadNotificationService.init()` — prepares the notification channel
- `_requestNotificationPermissionEarly()` — asks for notification permission
  (needed to show upload progress + keep the foreground service alive)
- `UploadQueueRepository.runStartupCleanup()` — deletes old finished rows,
  orphaned cache files, and trims the database.

### 2.2 `UnifiedUploadQueueProvider()` constructor → `_init()`
Registered in `lib/app/app.dart` as a `ChangeNotifierProvider`. On creation it:
1. `_resolveDeletableRoots()` — records the temp/cache directory paths so we can
   safely delete source files after upload (never deletes user's original files
   elsewhere).
2. Builds an `UploadConfig` — this is the **configuration object** wiring every
   backend detail:
   - `tokenProvider` — how to get the current auth token
   - `refreshTokenProvider` + `refreshEndpoint` — how to refresh a 401 token
   - `buildInitBody` / `parseInitResponse` — request/response shape for init
   - `buildCompleteEndpoint` → `Urls.uploadCompleteUrl` (`/video-post/upload/complete`)
   - `buildAbortEndpoint` → `Urls.uploadAbortUrl` (`/video-post/upload/abort`)
   - `buildCallback` — how to build the "create lesson" call per upload type
   - `shouldDeleteSourceOnComplete` — the cache-cleanup predicate
3. Picks the engine:
   - Android/iOS → `NativeBackgroundEngine` (survives app kill)
   - Desktop → `DartHttpEngine` (foreground only)
4. Creates the `UploadQueue`, which triggers **`UploadQueue._init()`**.

### 2.3 `UploadQueue._init()` — `queue.dart:58` (THE RESTORATION STEP)
This is how the app "reconnects" to uploads after a kill:
1. `migrateFromLegacy()` — one-time import from the old DB (if any).
2. `deleteOldItems()` — remove finished rows older than 7 days.
3. `_tasks = getAll()` — load every task from SQLite into memory so the UI can
   show them instantly.
4. `getUploading()` — find tasks that were mid-upload when the app died.
5. `_startPump()` — start a **15-second timer** (the safety net — see §8).
6. `_emit()` — push the loaded tasks to the UI stream immediately.
7. `unawaited(_processNext())` — kick the **single serial FIFO processor**.

> **This is why progress "instantly syncs" when you re-open the app:** the DB
> already holds each task's last-known progress, and `_processNext` immediately
> queries the native layer (`getChainStatus`, `getUploadStatus`) for the *live*
> current state.

---

## 3. THE BUTTON — User Taps "Upload"

There are several entry screens; the clearest is
`upload_video_screen.dart`. The module-lesson flow
(`manage_module_add_lesson_sheet.dart`) is identical in shape.

### 3.1 `_pickVideo()` — `upload_video_screen.dart:46`
- Guarded by `_isPicking` so double-taps can't open two pickers.
- `_picker.pickVideo(source: ImageSource.gallery)` — opens the OS gallery.
- On success stores `_pickedFile`. Wrapped in try/catch/finally so a picker
  crash never freezes the button.

### 3.2 `_handleUpload()` — `upload_video_screen.dart:59` (the button's onPressed)
Step by step:
1. `_formKey.currentState!.validate()` — title field must be valid. **Edge case:**
   invalid form → return, nothing happens.
2. `_pickedFile == null` → toast "Please select a video file", return.
   **Edge case:** no file chosen.
3. `file.exists()` → **Edge case:** the picked file was deleted/moved between pick
   and upload → toast "Selected file no longer available", return.
4. `setState(_isUploading = true)` — disables the button, shows a spinner.
5. `context.read<UnifiedUploadQueueProvider>().addToQueue(file, title)` — hands
   off to Layer 2.
6. On success → `Navigator.pop()` (leave the screen; upload continues in
   background).
7. `finally { _isUploading = false }` — **Edge case:** even if `addToQueue`
   throws, the button re-enables. No stuck spinner.

---

## 4. Provider — `addToQueue()` (Layer 2)

`unified_upload_queue_provider.dart`. Different asset types have their own
method (`addModuleLessonToQueue`, `addResourceToQueue`, `addCourseToQueue`,
`addCourseIntroVideo`) but they all follow the same recipe:

1. **Duplicate guard** — `_hasInFlightFile(path)` checks if the same file is
   already uploading. **Edge case:** user taps upload twice → toast "already
   being uploaded", return `false`.
2. **Metadata extraction** — `VideoMetadataHelper.getDurationSeconds()` and
   `getFileSizeBytes()`. **Edge case:** corrupt video → helper returns 0/null,
   upload still proceeds (duration is informational).
3. **Notification permission** — `_ensureNotificationPermission()`. **Edge case:**
   denied → dialog explains why → if still denied, offer "Open Settings" →
   return `false` (can't upload without the foreground-service notification on
   Android).
4. `_adding` flag (for module/resource/course) — prevents a re-entrancy race
   where two rapid taps enqueue twice.
5. `_queue.add(file, title, metadata)` — hands off to Layer 3. The `metadata`
   map carries everything the later steps need: `uploadType`, `moduleId`,
   `courseId`, `videoDuration`, `fileSize`, `initEndpoint`, etc.
6. Toast "Video queued for upload", return `true`.

> **`metadata` is important:** it travels with the task through the whole
> lifecycle and is how `buildInitBody` / `buildCallback` know which endpoint and
> body shape to use for *this specific* upload type.

---

## 5. Queue — `add()` then `_processNext()` (Layer 3, the brain)

### 5.1 `UploadQueue.add()` — `queue.dart:133`
1. **Queue depth limit** — if `countActive() >= maxQueueSize` (default 200),
   `_evictOldestFailed()` removes the oldest 25% of *terminal* (failed/completed/
   cancelled) tasks. **Edge case:** still full after eviction → throws
   `StateError('Upload queue is full')`.
2. `_persistence.insert()` — writes a new row to SQLite in `pending` state,
   returns its auto-increment `id`. **This id is the task's permanent identity**
   used everywhere (WorkManager tags, native chain status keys, etc.).
3. `_emit()` — UI updates to show the new pending item.
4. `unawaited(_processNext())` — try to start processing.
5. Returns the `UploadTask`.

### 5.2 `_processNext()` — `queue.dart:217` (STRICT FIFO — one video at a time)
This is the heart of the scheduler. Only **one** copy runs at a time thanks to
`_processingLock` (a simple async boolean lock).

```
_processNext():
  acquire _processingLock   ← if already locked, return (someone else is working)
  if disposed → release + return

  ── Priority 1: RESUME the oldest in-flight task ──
  resumable = getUploading()               ← tasks stuck in 'uploading'
  sort by id ASC                            ← oldest first = FIFO
  toResume = first not already processing
  if toResume != null:
      waitingOnNative = await _resume(toResume)   ← see §7
      release lock
      if not waitingOnNative → _processNext()     ← chain to next
      return

  ── Priority 2: claim the oldest PENDING task ──
  task = claimNextPending()   ← atomically flips oldest 'pending' → 'uploading'
  if task == null → release + return   ← nothing to do

  try:
    if file missing → markFailed('File not found'); return   ← EDGE CASE
    initResult = engine.initUpload(...)      ← PHASE 1 (§6)
    if initResult == null → markFailed('Init upload failed'); return  ← EDGE CASE
    save fileUrl if present
    if initResult.isMultipart → _processMultipart(...)   ← §6.2
    else                      → _processDirect(...)      ← §6.3
  catch → markFailed('Error: ...')
  finally:
    release lock
    _emit()
    _processNext()   ← immediately try the next queued video
```

**Why FIFO matters for you:** you asked for *first-in-first-out*, one video at a
time. The `_processingLock` + "oldest id first" claim guarantees video #1 fully
finishes (including complete + callback) before video #2 starts. Parts *within*
one video still upload in parallel for speed — FIFO is about video **ordering**,
not crippling a single upload.

---

## 6. Phase 1–2 — Init and Upload Parts (fresh upload)

### 6.1 `initUpload()` — `native_background_engine.dart` / `dart_http_engine.dart`
- Builds the init body via `buildInitBody(fileName, metadata)`.
- POSTs to the init endpoint (e.g. `/course/module/lesson/upload`).
- Retries up to 3× with backoff on network errors / non-200.
- Parses the response via `parseInitResponse` → `InitUploadResponse`:
  - `isMultipart` (true for big files)
  - `uploadId`, `key`, `parts[]` (multipart) **or** `uploadUrl` (direct)
  - `fileUrl` (the eventual public URL)
- **Edge case:** returns `null` after retries → task marked failed.

### 6.2 `_processMultipart()` — `queue.dart:329` (the big-file path)
1. `computePartSize(fileSize, totalParts)` — how many bytes per part.
2. `updateMultipartState(id, s3UploadId, totalParts, partSize, s3Key)` —
   **persists the S3 `uploadId` and `key` to SQLite**. Critical: these must
   survive an app kill so the complete/abort/resume can run later.
3. `engine.uploadParts(filePath, parts, partSize, dbTaskId, onProgress)` —
   uploads all parts (see §6.4 for native details). `onProgress` updates the DB
   and UI with byte-level progress.
4. **Persist ETags** — for every successful part,
   `recordPartCompletion(id, partNumber, eTag)` writes the ETag to SQLite.
   These are needed for the complete call and survive app kill.
5. **Failure handling:**
   - Some parts failed **because URLs expired** (`isUrlExpired`, HTTP 403):
     re-`initUpload()` → get fresh presigned URLs → re-upload only the expired
     parts. **Edge case solved:** 3 GB upload slower than the 24h URL expiry.
   - Still failing after refresh → `abortMultipart()` (frees the S3 session),
     `clearMultipartState()`, `markFailed()`.
   - Parts failed for other reasons → `abortMultipart()` + `markFailed()`.
6. **Success** → go to Phase 3+4 (§9).

### 6.3 `_processDirect()` — small files (< 15 MB)
1. `updateFileUrl()` immediately (so resume can use it if killed).
2. `engine.directUpload(filePath, uploadUrl, dbTaskId, onProgress)` — one PUT.
3. On success → `_sendCallback()` (§10). On failure → `markFailed()`.

### 6.4 Inside `uploadParts()` — Native (survives app kill)
`native_background_engine.dart` calls the platform channel:

**Android** (`UploadBridgeHandler.onUploadParts`):
- For each part, creates a `OneTimeWorkRequest<UploadWorker>` with:
  - the presigned URL, file path, `startByte`, `partLength`, `partNumber`
  - a **network constraint** (`CONNECTED`, or `UNMETERED` if `wifiOnly`)
  - tags `eduverse_upload_<taskId>_<partNumber>` and `eduverse_upload_<taskId>`
    (the real DB id — **not** 0; this was a bug we fixed).
- `startForegroundService()` — shows the persistent "Uploading…" notification so
  Android won't kill the process.
- `observeWork(...)` — a LiveData observer that reports progress and the final
  result back to Dart.

**`UploadWorker.doWork()`** (per part):
- Streams the byte-range from the **single original file** via `PartRequestBody`
  (O(1) memory — it does NOT copy the file). This is why 3 GB works.
- Reports **absolute bytes uploaded** every 500 ms via `setProgress`.
- On HTTP 200 → returns `success`, the **quoted `ETag` from the header**, and the
  part's byte size.
- On 403 → `Result.retry()` (URL likely expired).
- Other errors → retry up to 2×, then `Result.failure`.

**iOS** (`AppDelegate.swift` `uploadParts`): creates one background
`URLSession.uploadTask(fromFile:)` per part. Background sessions **continue after
the app is killed** and re-launch the app in the background to report results.

### 6.5 Byte-level aggregate progress (smooth % for big files)
`UploadBridgeHandler.pushProgress` sums bytes across all part-workers
(`SUCCEEDED` parts count full size, `RUNNING` parts count live in-flight bytes) ÷
total file bytes. This produces a smooth 0–100% instead of coarse jumps like
0% → 11% → 22% on a 9-part file. The value flows through the EventChannel back to
`onProgress` → DB → UI.

---

## 7. THE KILL / RESUME PATH — `_resume()` (Layer 3 ↔ Layer 4)

This runs when `_processNext` finds a task stuck in `uploading` (i.e. the app was
killed mid-upload and just relaunched). `_resume()` — `queue.dart:540`. Returns
`true` if it's now *waiting on a native background chain* (so the scheduler backs
off and lets the 15s pump re-check).

Order of checks (fast paths first — never re-upload bytes unnecessarily):

1. **Chain already finished natively?** `engine.getChainStatus(taskId)`:
   - `'success'` → the CompleteWorker + CallbackWorker finished **while the app
     was dead**. Read the persisted `fileUrl`, `markCompleted`, done. **No
     re-upload.**
   - `'running'` → chain still running natively. Return `true` (wait; the pump
     re-checks). **No re-upload.**
   - `'failed'`/`'unknown'` → fall through and try to re-drive.
2. **Direct upload (no multipart state)?** `checkUploadCompleted(taskId)`:
   - done → send callback → complete.
   - not done → cancel stale workers, mark `pending` to restart cleanly.
3. **Multipart parts already done natively?** `checkUploadCompleted(taskId)`:
   - all parts `SUCCEEDED` → jump straight to `_completeAndFinish` (§9) using the
     **persisted** `uploadId`/`key`/ETags. **No re-upload of bytes.**
4. **Otherwise** → `refreshPresignedUrls()` for the remaining parts (they may
   have expired) → `uploadParts()` for only what's left → `_completeAndFinish`.

> **This is the "instant sync" magic:** on relaunch the DB shows where each video
> was, and the native layer tells us what finished while we were dead. We resume
> from the exact point, never from zero.

### How native results survive the app being dead
`CompleteWorker.kt` and `CallbackWorker.kt` write their outcome directly into
**SharedPreferences** (`writeChainStatus`) — `running` / `success` / `failed`
plus `fileUrl` and `error`. So even if the Dart observer died with the process,
the result is durable. `getChainStatus` reads SharedPreferences first, then falls
back to live WorkManager records.

---

## 8. The 15-Second Pump (safety net) — `_startPump()`

`queue.dart:94`. A `Timer.periodic(15s)` that:
1. Finds tasks stuck `uploading` for > 10 minutes that aren't actively being
   processed → treats them as **stale** → `abortMultipart()` (with persisted
   `uploadId`+`key`) → `clearMultipartState()` → `markFailed('Timed out')`.
   **Edge case:** a worker silently died and left a zombie task.
2. If the processing lock is free → `_processNext()` (picks up any `pending` or a
   still-`running` native chain that just finished).
3. `_persistence.optimize()` — periodic SQLite maintenance (VACUUM/analyze).

This is what re-checks a `'running'` chain after `_resume` backed off in §7.

---

## 9. Phase 3+4 — Complete Multipart + Callback (native, survives kill)

Triggered at the end of `_processMultipart` (fresh) or `_completeAndFinish`
(resume). The **key idea**: this runs **natively** so it finishes even if the app
is killed right after the last part uploads.

### 9.1 `completeMultipartAndCallback()` — `native_background_engine.dart`
- Builds the **complete body**: `{ key, uploadId, parts:[{partNumber, eTag}] }`.
  - `key` = the persisted S3 object key (**required by your backend**; missing it
    was the original HTTP 400 cause).
  - `eTag` = the **quoted** value straight from the S3 header (your backend
    expects it verbatim).
- Calls native `scheduleCompleteAndCallback(taskId, ...)` → Android chains
  `CompleteWorker → CallbackWorker` in WorkManager (iOS: background session).

### 9.2 `CompleteWorker.kt` (Android)
- POSTs the complete body to `/video-post/upload/complete`.
- Backend calls S3 `CompleteMultipartUpload` → **S3 joins the parts into one
  file**.
- Extracts `fileUrl` from the response.
- **Edge cases:** HTTP 400/500 → retry 2×; HTTP 401 → refresh token via
  `TokenRefreshUtil` and retry; writes `running`/`failed` to SharedPreferences.
- On success → chains to `CallbackWorker`.

### 9.3 `CallbackWorker.kt` (Android)
- POSTs the "create lesson/video" body to the callback endpoint (e.g.
  `/course/module/lesson`) with an **Idempotency-Key** (`<taskId>_callback`).
- **Edge case:** duplicate/retried callback → backend returns **409**, which we
  treat as **success** (idempotent — the row already exists).
- HTTP 401 → token refresh + retry. Retries 3×.
- Writes final `success`/`failed` to SharedPreferences (durable result).

### 9.4 Back in Dart
- If the native chain returns `success` + `fileUrl` → `updateFileUrl()`,
  `_completeTask()` (see §11), done.
- If the native channel is unavailable (e.g. desktop) → **Dart fallback**:
  `completeMultipart()` then `sendCallback()` over plain HTTP.

---

## 10. `_sendCallback()` — creating the server row (direct-upload path)

`queue.dart:_sendCallback`. Used by direct uploads and as the resume/fallback
path. Builds the callback via `config.buildCallback(task)` and calls
`engine.sendCallback(callback, dbTaskId: task.id)`. On Android this goes through
the native `scheduleCallback` (survives kill). **Edge case:** no callback
configured → returns `true` (nothing to do). Failure → task marked failed
(retryable).

---

## 11. `_completeTask()` — finish + cache cleanup

`queue.dart`. Every success path funnels through this:
1. `markCompleted(id)` — SQLite row → `completed`, progress 1.0.
2. If `shouldDeleteSourceOnComplete(task)` is true (file lives in temp/cache) →
   delete the source file. **Frees disk promptly** so multiple 3 GB temp copies
   don't fill storage. **Edge case:** delete failure never fails the upload (it's
   best-effort).

When the last active upload finishes, `UploadForegroundService` detects (via
WorkManager query) that no upload work remains and **stops itself** — the
"Uploading…" notification disappears.

---

## 12. Cancel / Retry / Remove (user actions)

- **Cancel** (`cancel(id)`): `engine.cancelUpload(id)` stops native workers →
  `abortMultipart(uploadId, key)` frees the S3 session → `markCancelled(id)`.
- **Retry** (`retry(id)`): `clearMultipartState(id)` → `markPending(id)` →
  `_processNext()`. Starts the whole flow fresh.
- **Remove** (`remove(id)`): deletes the row (only meaningful for terminal
  tasks).

---

## 13. Platform Deadfalls (know these for 3 GB uploads)

- **Android battery savers / Chinese OEMs (Xiaomi, Oppo, Vivo):** may kill
  WorkManager despite the foreground service. Mitigation: the FGS + `dataSync`
  type + notification is your main defense; consider prompting the user to
  disable battery optimization for the app.
- **Android 14 `dataSync` FGS cap:** ~6 hours/day cumulative. Many back-to-back
  3 GB uploads on slow data could hit it. Wi-Fi-only mode reduces the risk.
- **iOS background URLSession is *discretionary* by default on cellular:** iOS may
  delay uploads. The background session is the ONLY iOS API that survives kill,
  which is exactly what we use.
- **Presigned URL expiry (24h):** handled by re-init on 403 (§6.2).
- **Disk pressure:** we stream byte-ranges (never copy the file) and delete
  cache copies on completion (§11).

---

## 14. Quick Reference — Function Call Order (happy path, big file)

```
User taps Upload
 └─ _handleUpload()                         [upload_video_screen.dart]
     └─ provider.addToQueue()               [unified_upload_queue_provider.dart]
         ├─ _hasInFlightFile()  (dup guard)
         ├─ _ensureNotificationPermission()
         └─ queue.add()                     [queue.dart]
             ├─ persistence.insert()  → row = 'pending'
             └─ _processNext()
                 ├─ claimNextPending()  → row = 'uploading'
                 ├─ engine.initUpload()          ── PHASE 1 (S3 CreateMultipartUpload)
                 └─ _processMultipart()
                     ├─ persistence.updateMultipartState(uploadId, key)
                     ├─ engine.uploadParts()      ── PHASE 2 (native WorkManager / URLSession)
                     │    └─ UploadWorker.doWork() × N parts (byte-range PUT → ETag)
                     ├─ persistence.recordPartCompletion(eTag) × N
                     └─ engine.completeMultipartAndCallback()
                          ├─ CompleteWorker  ── PHASE 3 (S3 CompleteMultipartUpload = JOIN)
                          └─ CallbackWorker   ── PHASE 4 (create lesson row, 409 = ok)
                     └─ _completeTask()  → row = 'completed' + delete cache file
```

## 15. Quick Reference — State Machine

```
pending ──claim──► uploading ──parts+complete+callback──► completed
   ▲                   │  │                                    
   │ retry             │  └──abort──► failed ──retry──► pending 
   └───────────────────┘                                       
                       └──user cancel──► cancelled             
```

| State | Meaning | Set by |
|---|---|---|
| `pending` | Waiting its FIFO turn | `insert`, `markPending`, `retry` |
| `uploading` | Actively uploading (or resuming) | `claimNextPending`, `_processNext` |
| `completed` | Done + row created on server | `_completeTask` |
| `failed` | Error (retryable) | `markFailed` |
| `cancelled` | User cancelled | `markCancelled` |

## 16. Quick Reference — The 4 Backend APIs

| Phase | Endpoint (example) | Body | Who calls it |
|---|---|---|---|
| Init | `/course/module/lesson/upload` | `{videoFilename, videoContentType, videoFileSize, moduleID}` | `initUpload` (Dart, foreground) |
| Part PUT | presigned S3 URL | raw byte-range | `UploadWorker` / URLSession (native) |
| Complete | `/video-post/upload/complete` | `{key, uploadId, parts:[{partNumber, eTag}]}` | `CompleteWorker` (native) |
| Abort | `/video-post/upload/abort` | `{key, uploadId}` | `abortMultipart` on failure/cancel |
| Callback | `/course/module/lesson` | `{title, moduleId, videoUrl, duration, fileSize}` | `CallbackWorker` (native) |

## 17. Quick Reference — Where State Lives

| Data | Where it's stored | Survives app kill? |
|---|---|---|
| Task list, progress, state | SQLite `upload_queue_v2.db` | ✅ Yes |
| S3 `uploadId`, `key` | SQLite (`s3UploadId`, `s3Key` cols) | ✅ Yes |
| Part ETags | SQLite (`partETags` col) | ✅ Yes |
| In-flight byte transfer | WorkManager / background URLSession | ✅ Yes |
| Complete/callback outcome | Android SharedPreferences (`writeChainStatus`) | ✅ Yes |
| UI progress bars | Provider (in-memory) | ❌ No — rebuilt from DB on launch |
| Provider itself | RAM | ❌ No — recreated on launch |

---

## 18. TL;DR (one paragraph)

Tapping Upload writes a `pending` row to SQLite and kicks a **single FIFO
processor**. It picks the oldest task, calls **Init** (S3 multipart session +
presigned URLs + `key`), then uploads every part **natively** (Android
WorkManager / iOS background URLSession) streaming byte-ranges from the original
file so 3 GB works with tiny memory. Each part's **quoted ETag** is saved to
SQLite. When all parts are up, native **CompleteWorker** tells the backend to make
**S3 join the parts**, then **CallbackWorker** creates the lesson row (409 =
already-done = success). Every outcome is persisted, so if the app is **killed**
at any point, on relaunch the Provider is rebuilt, `_resume` asks the native layer
"what finished while I was dead?", and continues from the exact point — never
re-uploading bytes. A 15-second pump cleans up zombies and drives the next video.
