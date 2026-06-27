# Manage Module — Lesson Upload Full Flow

## UI Entry Point
**`manage_module_screen.dart`** (line 216)
User taps **"+ Video"** on a module → calls `ManageModuleAddLessonSheet.show()`

```
manage_module_screen.dart:216-232
  → ManageModuleAddLessonSheet.show(
       lessonType: LessonType.video,
       moduleId: provider.modules[index].id,
       courseId: provider.courseId,
       onAddLesson: provider.addVideoLesson,
     )
```

## File Picker → Submit
**`manage_module_add_lesson_sheet.dart`** (lines 72-115)
- User picks video from gallery via `ImagePicker.pickVideo()` (line 72)
- Taps "Upload" (line 92)
- Calls back to `widget.onAddLesson(title, file)` which is `provider.addVideoLesson`

## Provider: Queue the Upload
**`manage_module_provider.dart` — `addVideoLesson()`** (lines 621-678)

| Step | Line | What happens |
|------|------|-------------|
| 1. Lock | 627-630 | `_isQueuing` guard — prevents concurrent queue operations |
| 2. Dedup | 639 | `_checkDedupOrCleanup(filePath)` — checks ALL SQLite statuses for same filePath + uploadType |
| 3. Queue to native | 643-650 | `queueProvider.addModuleLessonToQueue(videoPath, lessonTitle, moduleId, courseId, lessonId)` |
| 4. Create PendingLesson | 659-668 | `PendingLesson(queueId, lessonId, title, type, filePath, uploadProgress: 0.0, uploadStatus: 'pending', moduleId)` |
| 5. Store | 670 | `_pendingLessons[queueId] = pending` — stored in map |
| 6. Notify UI | 672 | `notifyListeners()` — widget rebuilds, shows pending card |
| 7. Start polling | 673 | `_startProgressPolling()` — begins monitoring native queue every 5s |
| 8. Unlock | 675-677 | `_isQueuing = false` in `finally` block |

## Unified Provider: Native Sync
**`unified_upload_queue_provider.dart` — `addModuleLessonToQueue()`** (lines ~520-651)

| Step | Line | What happens |
|------|------|-------------|
| 1. Dedup | 533-549 | All-status `getAll()` — prevents duplicate across all statuses |
| 2. Metadata | 551-556 | Creates `ModuleLessonMetadata(moduleId, courseId, lessonTitle, contentType, lessonId)` |
| 3. SQLite insert | 587 | `UploadQueueRepository.insert(item)` — status='pending' |
| 4. Notify → UI updates | 588-590 | `_queue = getActive(); _checkNextActive(); notifyListeners()` |
| 5. Permission | 580-585 | `_ensureNotificationPermission()` |
| 6. Presigned URL | 592-600 | `BackgroundUploadService.fetchPresignedUrl()` → POST to server → returns `{uploadUrl, fileUrl}` |
| 7. Native sync | 617-629 | `NativeUploadBridge.startNativeUpload(filePath, uploadUrl, fileUrl, callbackUrl, callbackBody, ...)` |
| 8. Update SQLite | 636-640 | `UploadQueueRepository.updateUrls(id, uploadUrl, fileUrl)` |
| 9. Start processing | 642-647 | `NativeUploadBridge.startQueueProcessing()` |
| 10. Start polling | 649 | `_startNativeCompletionPolling()` — every 3s |

## Native Upload Service (Kotlin :upload process)
**`native_upload_bridge.dart`** (lines 68-99, 34-42)
- `startNativeUpload()` → MethodChannel → Kotlin `UploadReschedulerService`
- Survives app kill (separate process)
- Reads `native_uploads.json` for recovery
- Uploads to S3 via presigned URL
- Fires server callback on completion (POST to `Urls.courseModuleLessonUrl` with `{title, videoUrl, moduleId, duration, fileSize}`)

## Two Parallel Polling Loops

### 1. Progress Polling (ManageModuleProvider — every 5s)
**`manage_module_provider.dart` — `_startProgressPolling()`** (lines 680-791)

Tracks PendingLesson UI state via `NativeUploadBridge.getQueueItems()`.

| Event | Lines | Behavior |
|-------|-------|----------|
| Status → 'completed' | 711-721 | Marks SQLite completed, shows toast, adds to `completedIds` |
| Status → 'failed' | 722-726 | Shows as failed in UI (no removal) |
| Native empty, but items remain | 731-761 | Fix B: cross-references SQLite, cleans up orphans/completed |
| Completed items removed | 765-770 | Removes from `_pendingLessons` + `clearCompleted()` (NOT awaited) |
| After completion | 773 | `_silentRefresh()` — re-fetches course data from server |
| All done | 778-786 | Cancels timer, schedules one final refresh after 10s |

### 2. Completion Polling (UnifiedUploadQueueProvider — every 3s)
**`unified_upload_queue_provider.dart` — `_startNativeCompletionPolling()`** (lines 80-120)

Manages SQLite + native state cleanup for all upload types.

| Event | Lines | Behavior |
|-------|-------|----------|
| Status 'completed' | 91-101 | `markCompleted(queueId)` + `removePathByFilePath(filePath)` |
| After any completed | 103-105 | `await clearCompleted()` |
| All items done | 110-115 | `clearState()` + `clearAll()` + cancel timer |

## Recovery Pipeline (App Restart)
**`native_init.dart`** (lines 29-264, called once on app start)

| Phase | Lines | What it does |
|-------|-------|-------------|
| Phase 1: FSS recovery | 41-85 | `_recoverPendingUploads()` — reads FlutterSecureStorage, re-queues |
| Phase 2: Native orphans | 96-205 | `_recoverNativeOrphans()` — checks `native_uploads.json` + SQLite |
| Phase 3: Stale locks | 208-215 | `_clearStaleLocks()` — resets 'uploading' → 'pending' |
| Phase 4: Auto-resume | 220-264 | `_autoResumeIfNeeded()` — if native empty, sync from SQLite to native |

After Phase 4, when `ManageModuleProvider` is created:
- `_fetchCourse()` (line 46) runs → fetches course data from server
- `_removeCompletedPendingLessons()` (line 188) — cleans completed from `_pendingLessons`
- `_restorePendingUploads()` (line 191) — restores active items from SQLite → PendingLesson

## UI Status States
**`module_card.dart` — `_PendingLessonRow`** (lines 196-349)

Rendered per-PendingLesson below the module's confirmed lessons.

| `uploadStatus` | UI shows | User can |
|---------------|----------|----------|
| `pending` | Progress bar at 0%, "Waiting..." | Delete (cancels) |
| `uploading` | Progress bar + percentage | Delete (cancels) |
| `completed` | "Upload complete" (briefly, before removal) | — |
| `failed` | Error icon + "Upload failed" + retry button | Retry, Delete |

**`_LessonSwipeRow`** (lines 380-561) — confirmed lessons (from server):
- Swipe left → edit/delete options
- Tap video → `VideoPlayerScreen`
- Tap resource → `launchUrl()` externally

## Dedup Protection (All Levels)

### Level 1: ManageModuleProvider
**`manage_module_provider.dart` — `_checkDedupOrCleanup()`** (lines 797-818)
- `getAll()` (ALL statuses, not just active)
- Same `filePath` + `uploadType` (`module_lesson` or `resource`)
- If `pending/uploading` → block with toast
- If `failed/cancelled/completed` → auto-delete old row, allow re-upload

### Level 2: UnifiedUploadQueueProvider
**`unified_upload_queue_provider.dart`** — `addModuleLessonToQueue()` (lines 533-549)
- Same all-status `getAll()` check
- Independent from provider-level dedup (belt-and-suspenders)

## Error Handling (Every path)

| Failure point | File:Line | Handler |
|---------------|-----------|---------|
| `_isQueuing` locked | `manage_module_provider.dart:627` | Toast + return false |
| `queueProvider == null` | `manage_module_provider.dart:636` | Return false |
| Dedup blocks | `manage_module_provider.dart:639` | Toast + return false |
| Queue exception | `manage_module_provider.dart:651-654` | Toast + return false |
| `queueId <= 0` | `manage_module_provider.dart:657` | Return false |
| File not found | `unified_upload_queue_provider.dart:463-467` | Toast + return 0 |
| Already queued | `unified_upload_queue_provider.dart:474-478` | Toast + return 0 |
| Notification denied | `unified_upload_queue_provider.dart:581-585` | Toast + insert but no upload |
| Presigned URL fails | `unified_upload_queue_provider.dart:600-603` | `_cleanupFailedUpload` + toast |
| Native sync fails | `unified_upload_queue_provider.dart:629-632` | `_cleanupFailedUpload` + toast |
| Queue processing fails | `unified_upload_queue_provider.dart:642-647` | `_cleanupFailedUpload` + toast |
| Polling exception | `manage_module_provider.dart:788` | Caught, logged, loop continues |
| Polling exception (unified) | `unified_upload_queue_provider.dart:118` | Caught, logged, loop continues |

## Key Contracts

1. **PendingLesson appears only after** presigned URL + SQLite insert + native sync all succeed
2. **Failure never removes from UI** — user must retry or delete
3. **Completed items auto-remove** from `_pendingLessons` only after `_silentRefresh()` confirms server has the lesson
4. **Re-upload same file** after failure/cancellation works — old terminal row is deleted by dedup
5. **App kill during upload** — native `:upload` process survives; on restart, recovery pipeline picks up FSS/SQLite items
6. **No hardcoded timeouts** — uploads take as long as needed (no stuck-at-0% detection, no file size limits, no metadata extraction timeout)

## Relevant File Paths

```
lib/features/manage_module/
  presentation/screens/manage_module_screen.dart          — Main screen UI
  presentation/widgets/manage_module_add_lesson_sheet.dart — Video/resource picker sheet
  presentation/widgets/module_card.dart                    — _PendingLessonRow + _LessonSwipeRow
  presentation/widgets/manage_module_list.dart             — List wrapper, passes callbacks
  presentation/widgets/manage_module_edit_course_sheet.dart — Edit course sheet
  presentation/widgets/manage_module_shimmer.dart          — Loading skeleton
  presentation/widgets/manage_module_header.dart           — Course header
  presentation/widgets/manage_module_meta.dart             — Course metadata
  presentation/widgets/manage_module_description.dart      — Course description
  presentation/widgets/manage_module_bottom_bar.dart       — Bottom action bar
  providers/manage_module_provider.dart                    — Core business logic
  data/manage_module_models.dart                           — PendingLesson, Lesson, CourseModule models

lib/features/courses/
  providers/unified_upload_queue_provider.dart             — Centralized queue + native sync
  data/repositories/upload_queue_repository.dart           — SQLite CRUD
  data/models/upload_task.dart                             — UploadQueueItem, CourseUploadMetadata, ModuleLessonMetadata
  services/background_upload_service.dart                  — Presigned URL fetch, S3 upload
  presentation/widgets/upload_zone.dart                    — Upload zone widget

lib/global/core/services/
  native_upload_bridge.dart                                — MethodChannel to Kotlin
  upload_path_storage.dart                                 — FlutterSecureStorage for recovery
  upload_notification_service.dart                         — Android notification channel

lib/app/
  native_init.dart                                         — Recovery pipeline (4 phases)
  setup_network_caller.dart                                — Auth header + 401 redirect
  app_routes.dart                                          — Route definitions
  app.dart                                                 — Root widget + MultiProvider
```
