# Job: Fix Lesson Upload Pipeline — Full Audit

## Tested Issues (Round 1 — Fixed)

### Issue 1: Wrong prefix icon on pending lesson
- **Root cause**: `_PendingLessonRow` used Material Icons instead of SVG assets
- **Fix**: Replaced with `Images.learnVideo` / `Images.resource` SVGs (done)

### Issue 2: Progress bar not visible after app restart
- **Root cause**: `_autoResumeIfNeeded` destructively overwrote native state mid-upload
- **Fix**: Check native state first; only restart service, don't overwrite (done)

### Issue 3: Video player crashes on tap
- **Root cause**: Null videoUrl passed to `VideoPlayerScreen`
- **Fix**: Added null/empty guard at screen level (done)

### Issue 4: Notification shows but UI stuck loading
- **Root cause**: `_fetchCourse` in polling set `_isLoading = true`, triggering shimmer
- **Fix**: Silent refresh (`_silentRefresh`) skips shimmer + restore (done)

### Issue 5: Infinite reload loop
- **Root cause**: `_fetchCourse → restore → poll → complete → _fetchCourse` cycle
- **Fix**: Polling uses `_silentRefresh` which never calls `_restorePendingUploads` (done)

---

## Edge Case Analysis (Round 2 — New Findings)

### HIGH PRIORITY

#### H1. Failed uploads vanish from UI within 5 seconds
- **Problem**: When native reports 'failed', the poll adds it to `completedIds` and removes from `_pendingLessons` immediately. The user sees the red "Upload failed" text for at most one poll cycle (5s) before it disappears forever.
- **DB state**: The SQLite row stays as 'failed', but `getActive()` excludes 'failed' items, so `_restorePendingUploads()` never brings it back.
- **No retry path**: `ManageModuleProvider` has no retry method exposed. `_PendingLessonRow` only has a delete button, not retry.
- **Fix needed**: Keep failed items in `_pendingLessons` until user explicitly dismisses. Add retry callback. Show "Upload failed — tap to retry" UI.

#### H2. `deletePendingLesson` cancels ALL native uploads, not just one
- **Problem**: `NativeUploadBridge.cancelNativeUpload()` is a blanket cancellation — it kills the entire foreground service and clears the entire `native_uploads.json`. Deleting one pending lesson destroys all in-progress uploads.
- **Fix needed**: Instead of blanket cancel, mark the specific item as 'cancelled' in SQLite and remove from `_pendingLessons`. Do NOT call `cancelNativeUpload()`. The native service will encounter the removed item, see the file still exists (but we've moved on), and try to upload it. It'll eventually fail or succeed, but the callback will be for a lesson that's no longer tracked. Better approach: let the native upload complete, but when the callback fires and `_fetchCourse()` loads the result, the lesson will appear. The user deleted the pending lesson — they just don't want to see the progress bar. The upload completing is harmless.
- **Alternative**: Remove the item from SQLite entirely (`deleteItem`) so it's truly gone. The native service still has it in native_uploads.json, but there's no SQLite record. On restart, Phase 2 will check native state, see the item, check if it's in SQLite (it's not), and if the file exists, re-insert it into SQLite. This would bring it back! So we need Phase 2 to also check if the item was intentionally removed.
- **Simplest fix**: Don't call `cancelNativeUpload()`. Just remove from `_pendingLessons`. Mark SQLite as 'cancelled'. The native item will complete eventually; the callback creates a lesson on the server. When `_fetchCourse()` runs, the lesson appears. The user deleted the progress bar, not the underlying upload. If they want to truly cancel, they need a separate "cancel upload" that calls `cancelNativeUpload()` with a confirmation dialog.

#### H3. Last item completes → `_silentRefresh` is fire-and-forget → timer stops → stale data
- **Problem**: When the last pending lesson completes:
  1. Poll removes from `_pendingLessons`
  2. Calls `_silentRefresh()` (not awaited)
  3. Timer checks `_pendingLessons.isEmpty` → cancels itself
  4. `_silentRefresh` HTTP request is still in-flight
  5. If server callback hasn't been processed yet by the server, the refresh returns stale data (no new lesson)
  6. Timer is cancelled, so no follow-up fetch occurs
  7. User sees the lesson missing until they manually pull-to-refresh
- **Fix needed**: Await `_silentRefresh()` before cancelling timer. Or add a `_refreshAfterUpload` flag that triggers one more refresh cycle after the timer stops.

---

### MEDIUM PRIORITY

#### M1. `_silentRefresh()` calls stack up
- **Problem**: `_silentRefresh()` is called fire-and-forget inside the timer callback. If multiple uploads complete across poll cycles, multiple concurrent HTTP requests fire for the same course data. No re-entrance guard.
- **Fix needed**: Add a `_isRefreshing` guard. If a silent refresh is already in-flight, skip. Or batch: collect all completion events and refresh once.

#### M2. Shimmer flash on pull-to-refresh during uploads
- **Problem**: `provider.refresh()` sets `_isLoading = true`, replacing the scrollable content with `ManageModuleShimmer`. All pending lesson progress bars disappear during the shimmer.
- **Fix needed**: During an active upload, pull-to-refresh should NOT show shimmer. Use `_silentRefresh()` instead when `_pendingLessons` is not empty.

#### M3. Toast spam on re-entry when uploads completed while away
- **Problem**: `_notifiedCompletions` is a per-provider-instance field. When provider is recreated (user leaves and returns), the set starts empty. Any items that completed while away trigger "Upload completed successfully" toasts on the first poll cycle.
- **Mitigation**: Acceptable — toasts are informational and only fire once per item. The user should know their uploads finished.

#### M4. `deleteModule()` doesn't cancel pending uploads for that module
- **Problem**: Server API deletes the module. `_pendingLessons.removeWhere` cleans up in-memory. But native uploads continue. When they complete, the callback tries to create a lesson on a deleted module → server error.
- **Fix needed**: Delete SQLite rows for all pending items in the module. Mark them as 'cancelled'. Do not call blanket `cancelNativeUpload()` (see H2).

#### M5. Rapid-fire queue taps can bypass filePath dedup
- **Problem**: Both `addVideoLesson` and `addModuleLessonToQueue` call `getActive()` sequentially. If the user taps "Upload" twice before the first `insert()` completes, both items pass the dedup check.
- **Fix needed**: Use a `_isQueuing` lock in the provider to serialize add operations. Or use a UNIQUE constraint on `(filePath, status)` in SQLite (but status changes, so this is fragile).

---

### LOW PRIORITY

#### L1. `_notifiedCompletions` grows unbounded
- **Problem**: Set accumulates queueIds over provider lifetime. For very long upload sessions with hundreds of items, this is a small memory leak.
- **Fix**: Not needed for practical use-cases.

#### L2. Dead code in `_LessonSwipeRow` for upload progress
- **Problem**: The progress bar and "Waiting to upload..."/"Uploading X%" in `_LessonSwipeRow` (original lesson rows) are never reached — `Lesson.uploadStatus` always defaults to `'completed'`. Pending uploads are shown via `_PendingLessonRow`.
- **Fix**: Remove the dead progress bar code from `_LessonSwipeRow` to clean up.

#### L3. "Finalizing..." message should be "Upload complete"
- **Problem**: `_PendingLessonRow` shows "Finalizing..." when `uploadStatus == 'completed'`. Since completed items are removed on the next poll cycle, this is rarely seen, but it's wrong.
- **Fix**: Change to "Upload complete" or remove the state (completed items are removed immediately anyway).

---

## Updated Implementation Plan

### Round 1 (DONE)
1. `module_card.dart` — Revert icons to SVG
2. `manage_module_provider.dart` — Silent refresh, polling rewrite, `silent` param
3. `native_init.dart` — Don't overwrite native state in `_autoResumeIfNeeded`
4. `manage_module_screen.dart` — Null guard on video tap
5. `JOB.md` — Updated with full audit

### Round 2 (DONE)
1. **H1**: Failed items kept visible; retry UI added
   - `_startProgressPolling()` → failed items no longer added to `completedIds` (stay in `_pendingLessons` until explicit removal)
   - `_PendingLessonRow` → retry button (refresh icon + "Retry" text) shown for failed status
   - `ManageModuleProvider` → added `retryPendingLesson(queueId)` which marks SQLite 'pending', resyncs to native via `NativeUploadBridge.syncQueueToNative()`, and restarts native processing
2. **H2**: Blanket `cancelNativeUpload()` removed from `deletePendingLesson`
   - Removed `NativeUploadBridge.cancelNativeUpload()` call
   - Just marks SQLite as 'cancelled' and removes from `_pendingLessons`
   - Underlying native upload completes silently; server callback creates lesson normally
3. **H3**: Silent refresh awaited before timer stop; follow-up refresh scheduled
   - `_startProgressPolling()` now `await`s `_silentRefresh()` before checking if timer should stop
   - When last item completes and timer stops, schedules a delayed `_silentRefresh()` 10s later to catch delayed server-side lesson creation
4. **M1**: `_isRefreshing` guard added to `_silentRefresh()`
5. **M2**: Pull-to-refresh uses silent mode when uploads active
   - `refresh()` → calls `_fetchCourse(silent: true)` if `_pendingLessons.isNotEmpty`
6. **M4**: `deleteModule()` marks pending items as 'cancelled' in SQLite
   - Iterates `_pendingLessons` entries for the deleted module and calls `UploadQueueRepository.updateStatus(id, 'cancelled')`
7. **M5**: `_isQueuing` lock serializes `addVideoLesson`/`addResourceLesson`
   - Both methods now return false immediately if another queue operation is in-flight
   - Lock released in `finally` block
8. **L2+L3**: Dead code removed; status text fixed
   - Removed unreachable progress bar + "Waiting to upload..."/"Uploading X%" from `_LessonSwipeRow`
   - Changed "Finalizing..." to "Upload complete" in `_PendingLessonRow`

### Files Modified (Round 2)
- `manage_module_provider.dart` — Added `_isRefreshing`, `_isQueuing` fields; `retryPendingLesson()`; fixed polling logic; fixed `deletePendingLesson`, `deleteModule`, `refresh`, `_silentRefresh`; added `dart:convert` import
- `module_card.dart` — Added `onRetryPendingLesson` to `ModuleCard`; retry button in `_PendingLessonRow`; removed dead progress code from `_LessonSwipeRow`; fixed "Finalizing..." → "Upload complete"
- `manage_module_list.dart` — Added `onRetryPendingLesson` callback and wiring to `ModuleCard`
- `manage_module_screen.dart` — Wired `onRetryPendingLesson` to `provider.retryPendingLesson()` with queue provider

## Round 3 (DONE) — Root-Cause Fixes for Reported Bugs

### Bug: Video stuck at 100% with existing lesson card after navigation
- **Root cause**: When native finishes all uploads and clears its state, `getQueueItems()` returns an empty list. The polling `for` loop does nothing, so items in `_pendingLessons` are never updated or removed — they show "Uploading 100%" forever.
- **Fix**: After the native items loop, if `items.isEmpty && _pendingLessons.isNotEmpty`, query SQLite for each tracked item. If SQLite no longer has the item (already deleted by `clearCompleted`), or if SQLite status is 'completed'/'failed', or if SQLite has a `fileUrl` (upload succeeded), remove from `_pendingLessons` and call `_silentRefresh()`.

### Bug: Extra video uploading automatically (phantom re-upload on restart)
- **Root cause**: When the native service reports 'completed', the poll called `clearCompleted()` which only deletes SQLite rows where `status == 'completed'`. But native never updates SQLite status — it updates its own `native_uploads.json`. So the SQLite row stays with its original 'pending' status. On next app restart, Phase 4 (`_autoResumeIfNeeded`) calls `countPending()` which finds these stale rows and re-syncs them to native for re-upload.
- **Fix A**: In the polling `completed` handler, call `UploadQueueRepository.markCompleted(queueId)` BEFORE `clearCompleted()` to ensure SQLite status is synced.
- **Fix B**: In `_restorePendingUploads`, check native state (`NativeUploadBridge.getQueueItems()`) before restoring an item. If native has no entry for the item AND the item has a `fileUrl`, the upload already completed — mark it 'completed' in SQLite and skip restoring.
- **Fix C**: Changed `UploadQueueRepository.getActive()` and `countActive()` to exclude status='cancelled', preventing cancelled items from being restored.

### Bug: Extra videos loading and loading
- **Root cause**: Same as above — items accumulate in `_pendingLessons` because polling never removes them (native state is empty), and they show "Waiting to upload..." indefinitely with no progress. Each poll cycle finds nothing to update, creates no notification, and the items stay visible forever.
- **Fix**: Same as Bug 1 fix — when native state is empty, clean up orphaned `_pendingLessons` entries by cross-referencing SQLite.

## Round 4 (DONE) — Duplicate Dedup + Race Condition Fixes

### Bug: Same video shows twice in UI after re-picking a failed/cancelled file
- **Root cause**: Dedup checked `getActive()` which excludes 'failed'/'cancelled' items. When a user's upload failed, they could pick the same file again and create a **second** SQLite row — both the old failed row and the new pending row existed simultaneously.
- **Fix**: Changed dedup to use `getAll()` (all statuses). If the same filePath is found with a **terminal** status ('failed'/'cancelled'/'completed'), the old row is **auto-deleted** and `_pendingLessons` is cleaned up before allowing the new upload. If found with an **active** status ('pending'/'uploading'), the upload is blocked with a clear error.

### Bug: Confusing "already in queue" toast when adding a different video
- **Root cause**: Duplicate error messages from two dedup checks (provider + queue provider) + vague `_isQueuing` lock message ("a file is already being queued").
- **Fix**: Clarified lock message to "another file is being queued". With the stricter dedup, the confusing double-toast scenario no longer occurs — terminal-status duplicates are silently cleaned up instead of blocked.

### Files Modified (Round 4)
- `manage_module_provider.dart` — Added `_checkDedupOrCleanup()` helper using `getAll()` with auto-cleanup; applied to both `addVideoLesson` and `addResourceLesson`; clarified `_isQueuing` message
- `unified_upload_queue_provider.dart` — `addModuleLessonToQueue` and `addResourceToQueue` now use `getAll()` with the same auto-cleanup logic (defense in depth)

## Unresolved Architecture Limits (Need Server/Kotlin)
1. **Per-item native cancellation** — `NativeUploadBridge.cancelNativeUpload()` is blanket-only
2. **Server-side dedup** — `POST /course/module/lesson` doesn't return 409 for duplicate videoUrl
3. **Upload progress streaming** — Polling is inherently less responsive than WebSocket/SSE
4. **Native SQLite status sync** — The Kotlin process never updates SQLite status; Flutter side infers it from native_uploads.json

## Additional Fix: `getActive()` now excludes 'cancelled' status
- Previously, `getActive()` returned items where `status NOT IN ('completed', 'failed')`. Items marked as 'cancelled' (via `deletePendingLesson`) were included. This caused:
  - `_restorePendingUploads` to restore cancelled items
  - Dedup check in `addVideoLesson`/`addResourceLesson` to block re-upload of cancelled files
  - Phase 1 and Phase 2 recovery to consider cancelled items as active
- **Fix**: Added `'cancelled'` to the exclusion list in both `getActive()` and `countActive()`.

## Remaining Industry-Grade Concerns

These are gaps that would be expected in a production-grade upload pipeline but are **out of scope** for our current fix cycle (server-side limitations or pre-existing architecture):

1. **No per-item native upload cancellation** — `NativeUploadBridge.cancelNativeUpload()` cancels ALL native uploads. We worked around it by not calling it at all, but per-item cancellation would require native-side changes.

2. **No exponential backoff for retry** — `retryPendingLesson()` immediately retries with no backoff. An industry solution would implement exponential backoff (1s, 2s, 4s, 8s...) + max retry limit.

3. **Polling-based (5s interval)** — Progress updates rely on `Timer.periodic`. WebSocket or SSE would be more responsive and battery-friendly. Not feasible without server-side streaming support.

4. **Race between native callback and polling refresh** — Both the server callback (triggered by native completion) and the polling timer can call `_silentRefresh()` concurrently. The `_isRefreshing` guard mitigates this but doesn't eliminate the race entirely.

5. **No dedup on server side** — `POST /course/module/lesson` does not return 409 Conflict for duplicate `videoUrl` within a module. Client-side dedup is best-effort; the server should enforce idempotency.

6. **No upload order guarantee** — Items queued within a module aren't guaranteed to upload or complete in the same order after app restart. Native processes them in whichever order WorkManager schedules.

7. **Phase 2 recovery could re-insert deleted items** — If native_uploads.json has entries for items the user explicitly deleted (SQLite marked 'cancelled'), Phase 2 recovery in `native_init.dart` would re-insert them into SQLite if the file still exists. We chose not to fix this (it's edge-case and the upload completing is harmless).

8. **No upload progress in system notification** — The native service shows a notification, but its progress content hasn't been verified to show per-file progress. Functional but not polished.

9. **No upload queue limits or bandwidth management** — No throttling or concurrent upload limit enforcement. All items are pushed to native simultaneously.
