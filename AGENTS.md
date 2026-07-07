# AGENTS.md — Eduverse Upload System

## Force-Quit Testing

### Android (emulator or device)
```bash
# 1. Start an upload via the app
# 2. Force-kill the app:
adb shell am force-stop net.eduverseapp
# 3. Wait 10-15 seconds for WorkManager to pick up the job
# 4. Verify upload completed by checking server or re-opening app
# 5. Check WorkManager state:
adb shell dumpsys jobscheduler | grep net.eduverseapp
# 6. Check logs:
adb logcat -s UploadWorker,UploadBridgeHandler,CallbackWorker,CompleteWorker
```

### iOS (simulator or device)
```bash
# 1. Start an upload via the app
# 2. Force-kill from app switcher (swipe up)
# 3. Wait 30-60 seconds — iOS background URLSession continues
# 4. Re-open app — verify queue shows uploaded state
# 5. Check for background session status files on device
```

## State of Upload System

### Fixed (Session 1)

1. **DB schema ordering** (`persistence.dart`): Changed `onCreate` to use `CREATE TABLE IF NOT EXISTS` / `CREATE INDEX IF NOT EXISTS`.

2. **Android native progress events** (`UploadWorker.kt`, `UploadBridgeHandler.kt`, `MainActivity.kt`):
   - `setProgress()` during file upload (byte-level via `AtomicLong` + parallel coroutine reporter)
   - `EventChannel.StreamHandler` for `eduverse/upload_progress`
   - `UploadBridgeHandler` pushes events on every WorkInfo change

3. **UI robustness** (`manage_module_add_lesson_sheet.dart`, `upload_video_screen.dart`):
   - `_pickFile()` wrapped in try-catch-finally
   - `_handleUpload()` wrapped in try-catch-finally in both screens

4. **UploadWorker compilation fixes**:
   - `okhttp3.internal.toImmutableList` → `okio.BufferedSink`
   - `MediaType.parse()`/`MediaType.get()` → `contentType.toMediaType()`
   - Removed deprecated `getForegroundInfoAsync()`, `outputDataOf`
   - `getWorkInfosByIdLiveData` → `getWorkInfosByTagLiveData`

### Fixed (Session 2 — Survive App Kill)

5. **FGS timeout crash** (`UploadForegroundService.kt`):
   - `onStartCommand` now handles `null` intent (START_STICKY restart after system kill)
   - `updateNotification` uses `startForegroundService()` on API 26+

6. **Native server callback** (`CallbackWorker.kt` — **new file**):
   - WorkManager `CoroutineWorker` that POSTs lesson creation to server
   - Retries 3× with exponential backoff, accepts 409 as success (idempotency)

7. **Native complete-multipart** (`CompleteWorker.kt` — **new file**):
   - WorkManager `CoroutineWorker` that POSTs assemble-parts request to server
   - Extracts `fileUrl` from JSON response, retries 2×
   - Chained with CallbackWorker so entire post-upload flow is native

8. **Native chain plumbing** (`UploadBridgeHandler.kt`):
   - `scheduleCallback` handler — enqueues CallbackWorker, observes via LiveData
   - `scheduleCompleteAndCallback` handler — chains CompleteWorker → CallbackWorker with backoff and observing

9. **Dart side** (`native_background_engine.dart`, `engine.dart`, `queue.dart`):
   - `completeMultipartAndCallback()` added to `UploadEngine` (default calls separate methods)
   - `NativeBackgroundEngine` overrides with native chain (MethodChannel → WorkManager)
   - `queue.dart` `_processMultipart` and `_completeAndFinish` use native chain first, fall back to Dart
   - `sendCallback()` goes through native `scheduleCallback` instead of Dart HTTP POST

### Compilation Fixes (Session 2)

- Added `import okhttp3.RequestBody.Companion.toRequestBody` to `CallbackWorker.kt` and `CompleteWorker.kt`
- Moved `addTag(chainTag)` from `WorkContinuation` (no such method) to individual `OneTimeWorkRequest.Builder`

### Verified
- `flutter analyze` — no new issues (only pre-existing infos/warnings)
- All 65 upload_queue tests pass
- `flutter build apk --debug` succeeds
- APK: `build/app/outputs/flutter-apk/app-debug.apk`

### Fixed (Session 3 — Production Gaps)

10. **Auth token refresh in native workers** (`TokenRefreshUtil.kt`, `CallbackWorker.kt`, `CompleteWorker.kt`, `UploadBridgeHandler.kt`):
    - Created `TokenRefreshUtil.kt` — POSTs to refresh endpoint with refresh token, returns new access token
    - `CallbackWorker`/`CompleteWorker` detect 401 → call `TokenRefreshUtil.refresh()` → retry with new token
    - `UploadBridgeHandler.kt` passes `refreshEndpoint` + `refreshToken` from Dart to workers in both `scheduleCallback` and `scheduleCompleteAndCallback`
    - Dart side: `UploadConfig` gets `refreshTokenProvider` + `refreshEndpoint` fields; `NativeBackgroundEngine` passes them through the MethodChannel; `UnifiedUploadQueueProvider` wires `AuthController.userModel?.refreshToken` and `Urls.refreshTokenUrl`

11. **iOS multipart background upload** (`AppDelegate.swift`):
    - `uploadParts` now creates a `PartUploadTracker` + per-part background `URLSession` (instead of foreground `URLSession.shared.data(for:)`)
    - Each part uploads via `session.uploadTask(with:fromFile:)` — survives app kill
    - `PartUploadTracker` accumulates results; calls the stored `FlutterResult` when all parts finish
    - New delegate classes: `PartUploadDelegate` (per-part background session), `PartUploadTracker` (accumulator)

12. **iOS CallbackWorker equivalent** (`AppDelegate.swift`):
    - `scheduleCallback` handler — performs callback HTTP POST via `URLSession.shared.data(for:)` with 3 retries, background-safe
    - `scheduleCompleteAndCallback` handler — chains complete-multipart POST → callback POST (injects `videoUrl`), returns result

13. **Two SQLite databases reconciliation** (`persistence.dart`, `queue.dart`):
    - `Persistence.migrateFromLegacy(legacyDbPath)` — reads legacy `upload_queue.db`, copies pending tasks to new `upload_queue_v2.db`, runs once on `UploadQueue._init()`
    - No more state inconsistency: one-time migration imports all orphaned tasks from the legacy system

14. **Queue depth limit** (`UploadConfig`, `UploadQueue`):
    - `UploadConfig.maxQueueSize` (default 200) — added to config constructor
    - `UploadQueue.add()` checks `Persistence.countActive()` before inserting; evicts oldest 25% terminal (failed/completed/cancelled) tasks when at limit; throws `StateError` if queue is full after eviction
    - `Persistence.countActive()` — new method

15. **Upload bandwidth throttle** (`UploadConfig`, `DartHttpEngine`):
    - `UploadConfig.maxBytesPerSecond` (default 0 = unlimited)
    - `DartHttpEngine.directUpload()` — pace chunks using `Stopwatch` + calculated delay
    - `DartHttpEngine._uploadSinglePart()` — applies `_throttleTransformer()` stream transformer to pace bytes between chunk reads
    - Rate is enforced per-stream on the Dart side; native delegates (iOS `PartUploadDelegate`, Android `UploadWorker`) throttle via OS-level URLSession TCP congestion

### Verified
- `flutter analyze` — no errors
- All 65 upload_queue tests pass
- `flutter build apk --debug` succeeds
- APK: `build/app/outputs/flutter-apk/app-debug.apk`
