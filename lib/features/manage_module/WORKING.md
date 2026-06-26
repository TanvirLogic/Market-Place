# Module & Lesson Management — Full Feature Documentation

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          FLUTTER (Dart)                                  │
│                                                                          │
│  ┌─────────────────────┐    ┌──────────────────────────────────────┐     │
│  │  ManageModuleScreen  │    │  ManageModuleProvider               │     │
│  │  (UI + gestures)     │───▶│  - Module/Lesson CRUD               │     │
│  │                      │    │  - _queueItemToLesson (in-memory)   │     │
│  │  ManageModuleAdd     │    │  - _startProgressPolling (5s timer) │     │
│  │  LessonSheet         │    │  - _restorePendingUploads()         │     │
│  │  (bottom sheet)      │    └──────────┬──────────────────────────┘     │
│  └──────────────────────┘               │                                │
│                                         │ calls                          │
│                                         ▼                                │
│  ┌──────────────────────────────────────────────────────────────────┐    │
│  │              UnifiedUploadQueueProvider                          │    │
│  │  - addModuleLessonToQueue(videoPath, lessonTitle, moduleId,     │    │
│  │                              courseId, lessonId)                 │    │
│  │  - addResourceToQueue(...)                                       │    │
│  │  - retryFailed(), cancelTask(), etc.                             │    │
│  └──────────┬───────────────────────┬───────────────────────────────┘    │
│             │                       │                                    │
│             ▼                       ▼                                    │
│  ┌──────────────────┐   ┌────────────────────────┐                      │
│  │ UploadPathStorage │   │ UploadQueueRepository  │                      │
│  │ (FlutterSecure    │   │ (SQLite: upload_queue  │                      │
│  │  Storage / FSS)   │   │  .db)                  │                      │
│  │ Crash Layer 1     │   │ Crash Layer 2          │                      │
│  └──────────────────┘   └───────────┬────────────┘                      │
│                                     │                                    │
│  ┌──────────────────────────────────┴──────────────────────────────┐    │
│  │              native_upload_bridge.dart (MethodChannel)           │    │
│  │  - startNativeUpload(filePath, uploadUrl, ...)                   │    │
│  │  - startQueueProcessing()                                       │    │
│  │  - getQueueItems() / getNativeQueueStatus()                     │    │
│  └─────────────────────────────────────┬────────────────────────────┘    │
│                                        │ MethodChannel                  │
│                                        ▼                                │
├──────────────────────────────────────────────────────────────────────────┤
│                        ANDROID (Kotlin)                                  │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────┐       │
│  │  MainActivity.kt                                             │       │
│  │  - configureFlutterEngine()                                  │       │
│  │  - Handles all MethodChannel calls                           │       │
│  │  - Delegates to UploadStateManager / UploadReschedulerService│       │
│  └──────────┬───────────────────────────────────────────────────┘       │
│             │                                                            │
│             ▼                                                            │
│  ┌──────────────────────────┐    ┌──────────────────────────────┐       │
│  │  UploadStateManager      │    │  UploadReschedulerService    │       │
│  │  - native_uploads.json   │    │  (Foreground Service)        │       │
│  │  - save/load/clear       │───▶│  - processQueue()            │       │
│  │  - markItemStatus()      │    │  - performS3Upload()         │       │
│  │  - updateItemProgress()  │    │  - performServerCallback()   │       │
│  │  Crash Layer 3           │    └──────────────────────────────┘       │
│  └──────────────────────────┘                                           │
└──────────────────────────────────────────────────────────────────────────┘
```

## File-by-File Breakdown

### 1. Models (`lib/features/manage_module/data/manage_module_models.dart`)

```dart
enum LessonType { video, resource }

class Lesson {
  int id;              // unique lesson ID
  String title;        // display title
  String duration;     // formatted "MM:SS"
  LessonType type;     // video or resource
  String? videoUrl;    // S3 URL (set after upload completes)
  String? fileUrl;     // S3 URL for resources
  double uploadProgress; // 0.0 → 1.0
  String uploadStatus;   // 'pending', 'uploading', 'completed', 'failed'
}

class CourseModule {
  int id;
  String title;
  List<Lesson> lessons;
  bool isExpanded;
  int order;
  int courseId;
}
```

**Purpose**: Simple data classes used by the UI to render module/lesson lists. The `uploadProgress` and `uploadStatus` fields drive the progress bars during upload.

---

### 2. Screen (`lib/features/manage_module/presentation/screens/manage_module_screen.dart`)

**Entry point**: `ManageModuleScreen(courseId)` — a `StatelessWidget` that wraps `ManageModuleProvider` in a `ChangeNotifierProvider`.

**Body**: `_ManageModuleBody` — a `StatefulWidget` that builds the entire scrolling course-editor UI:

```
┌─────────────────────────────────────┐
│  ManageModuleHeader                  │  ← course thumbnail + edit button
│  ManageModuleMeta                    │  ← title, short desc, meta tags
│  ManageModuleDescription (x2)        │  ← description + requirements
│  ─── divider ───                     │
│  "Swipe left to delete or edit"      │
│  ManageModuleList                    │  ← scrollable list of modules
│    ├─ Module 1 (expandable)          │     each module shows its lessons
│    │   ├─ Lesson 1 (video)           │     with drag-to-reorder, swipe-
│    │   ├─ Lesson 2 (resource)        │     to-delete, tap-to-play
│    │   └─ + Add Video / Resource     │
│    ├─ Module 2 ...
│    └─ + Add Module (bottom bar)      │
└─────────────────────────────────────┘
```

**Key wiring** (lines 190-201): The `onAddVideo` callback opens `ManageModuleAddLessonSheet`, which returns `(title, file, onProgress)` and calls `provider.addVideoLesson()`.

---

### 3. Add Lesson Sheet (`lib/features/manage_module/presentation/widgets/manage_module_add_lesson_sheet.dart`)

A bottom sheet with:
- **UploadZone** — tap to pick a file (uses `ImagePicker.pickVideo()` for videos, `FilePicker` for resources)
- **Title field** — max 60 chars with validation
- **Upload button** — calls `onAddLesson(title, file, _)` which triggers `provider.addVideoLesson()`

After successful upload queuing, the sheet auto-closes via `Navigator.of(context).pop()`.

---

### 4. Manage Module Provider (`lib/features/manage_module/providers/manage_module_provider.dart`)

The central orchestrator for module management. Key responsibilities:

#### State it holds:
| Field | Type | Purpose |
|-------|------|---------|
| `_modules` | `List<CourseModule>` | Full module/lesson tree |
| `_queueItemToLesson` | `Map<int, int>` | Maps queueId → lessonId (in-memory, rebuilt on restore) |
| `_pendingFileUrls` | `Map<int, String>` | Cache of S3 URLs while upload is in progress |
| `_nextModuleId` / `_nextLessonId` | `int` | Local ID counters for new items |

#### Core Methods:

**`addVideoLesson(int moduleIndex, String title, XFile videoFile, {queueProvider})`**
1. Creates a `Lesson(id, title, 'pending')` and adds it to the module's lesson list
2. Calls `queueProvider.addModuleLessonToQueue(videoPath, lessonTitle, moduleId, courseId, lessonId)`
3. Maps the returned `queueId` → `lessonId` in `_queueItemToLesson`
4. Starts `_startProgressPolling()`

**`_startProgressPolling()`** — runs a `Timer.periodic` every **5 seconds** that:
- Calls `NativeUploadBridge.getQueueItems()` to read `native_uploads.json`
- Updates each lesson's `uploadProgress` and `uploadStatus` from native state
- When native queue empties, marks all remaining mapped lessons as `'completed'`
- Stops the timer when `_queueItemToLesson` is empty

**`_restorePendingUploads()`** — called after `_fetchCourse()` completes. For each pending queue item in SQLite:
1. Parses `ModuleLessonMetadata` from the stored metadata JSON
2. Uses `meta.lessonId` (new!) to restore the `_queueItemToLesson` mapping
3. Creates a placeholder `Lesson` with `pending` status and adds it to the UI
4. Starts polling so progress continues to update

---

### 5. Unified Upload Queue Provider (`lib/features/courses/providers/unified_upload_queue_provider.dart`)

The unified upload engine used by all upload types (video post, course, module lesson, resource).

**`addModuleLessonToQueue(videoPath, lessonTitle, moduleId, courseId, {lessonId})`**
```
┌─────────────────────────────────────────────────────────────┐
│  1. Validate file exists                                    │
│  2. Build ModuleLessonMetadata{moduleId, courseId,           │
│       lessonTitle, lessonId}  ← lessonId now persisted!     │
│  3. Save to FlutterSecureStorage (Crash Layer 1)            │
│  4. Check notification permission                           │
│  5. Insert into SQLite (Crash Layer 2) → get id             │
│  6. Fetch presigned S3 URL from server                      │
│  7. Build callback body with {title, videoUrl, moduleId,    │
│       duration, fileSize}                                    │
│  8. Sync to native via NativeUploadBridge.startNativeUpload │
│      → writes native_uploads.json (Crash Layer 3)           │
│  9. Update SQLite with uploadUrl/fileUrl, status='uploading'│
│  10. Start native queue processing                          │
│  11. Return queueId (SQLite auto-increment id)              │
└─────────────────────────────────────────────────────────────┘
```

**`addResourceToQueue(...)`** — identical flow but for resource files (different endpoint, callback URL, content type).

---

### 6. Upload Task Models (`lib/features/courses/data/models/upload_task.dart`)

```dart
class ModuleLessonMetadata {
  int moduleId;
  int courseId;
  String lessonTitle;
  String? contentType;
  int? lessonId;          // ← NEW: persists queue→lesson mapping
}

enum UploadTaskType { videoPost, course, moduleLesson, resource }

class CourseUploadMetadata {
  String courseTitle, shortDescription, description, requirements;
  String language, level, type;
  double price;
  String? videoPath;
}
```

**Purpose**: Serialized to JSON and stored in SQLite's `metadata` column. The `lessonId` field is the key to recovering the `_queueItemToLesson` mapping after app restart.

---

### 7. SQLite Repository (`lib/features/courses/data/repositories/upload_queue_repository.dart`)

**Table**: `upload_queue`

| Column | Type | Purpose |
|--------|------|---------|
| `id` | INTEGER PK AUTOINCREMENT | Queue item ID (used as `queueId`) |
| `filePath` | TEXT | Local file path |
| `title` | TEXT | Display title |
| `fileSize` | INTEGER | Bytes |
| `uploadUrl` / `fileUrl` | TEXT | Presigned S3 URLs (set after fetch) |
| `status` | TEXT | `pending`, `uploading`, `completed`, `failed`, `cancelled` |
| `bytesUploaded` | INTEGER | Progress tracking |
| `uploadType` | TEXT | `module_lesson`, `resource`, `video_post`, `course` |
| `metadata` | TEXT | JSON blob (contains `ModuleLessonMetadata`) |

**Key queries**: `insert`, `getActive`, `getByStatus`, `updateUrls`, `markCompleted`, `markFailed`, `resetStaleUploading`.

---

### 8. Background Upload Service (`lib/features/courses/services/background_upload_service.dart`)

| Method | Purpose |
|--------|---------|
| `fetchPresignedUrl()` | HTTP POST to server → returns `{uploadUrl, fileUrl}` |
| `fetchCoursePresignedUrls()` | Gets presigned URLs for thumbnail + video in one request |
| `syncAndStartNative()` | (Unused) Syncs FSS queue to native |
| `uploadFileToS3()` | **Streaming** PUT to S3 (fixed to avoid OOM) |

**Presigned URL flow**:
```
POST /api/upload-url  Body: {videoFilename, videoContentType, moduleID}
  ↓
Response: {data: {uploadUrl: "https://s3...", fileUrl: "https://cdn..."}}
  ↓
Upload uses uploadUrl; callback uses fileUrl
```

---

### 9. Upload Path Storage (`lib/global/core/services/upload_path_storage.dart`)

**Crash Layer 1** — before SQLite insert, saves upload intent to `FlutterSecureStorage`:
- Key: `pending_upload_<timestamp>`
- Value: `{filePath, uploadType, title, metadata, createdAt}`

Also maintains an **atomic queue** JSON blob for native sync.

---

### 10. Native Upload Bridge (`lib/global/core/services/native_upload_bridge.dart`)

MethodChannel bridge (`eduverse/upload_bridge`) between Flutter and Kotlin:

| Method | Purpose |
|--------|---------|
| `startNativeUpload()` | Passes upload info to native for crash‑proof persistence |
| `startQueueProcessing()` | Starts the foreground service (`:upload` process) |
| `getQueueItems()` | Reads `native_uploads.json` → returns status + progress + fileUrl |
| `getNativeQueueStatus()` | Returns aggregate counts (pending/uploading/completed/failed) |
| `cancelNativeUpload()` | Stops service and clears state |
| `ensureInitialized()` | Schedules WorkManager for periodic recovery checks |

---

### 11. Native Android — MainActivity.kt

Handles all MethodChannel calls:
- **`startNativeUpload`**: Appends item to `native_uploads.json` via `UploadStateManager`
- **`startQueueProcessing`**: Starts `UploadReschedulerService` foreground service
- **`getNativeQueueItems`**: Reads `native_uploads.json` and returns items with progress
- **`getNativeQueueStatus`**: Returns aggregate counts
- **`scheduleWorkManager`**: Enqueues periodic WorkManager for orphan recovery

Also handles the `eduverse/video_metadata` channel for reading video duration/size via `MediaMetadataRetriever`.

---

### 12. Native Android — UploadStateManager.kt

Manages `native_uploads.json` in `context.filesDir` (Crash Layer 3):

| Method | Purpose |
|--------|---------|
| `save(items, activeIndex, isUploading)` | Writes full JSON state file |
| `load()` | Reads and parses state file |
| `clear()` | Deletes state file |
| `markItemStatus(id, status, error)` | Updates a single item's status |
| `updateItemProgress(id, progress)` | Updates progress percentage |
| `removeCompletedAndFailed()` | Cleans up done/failed items |
| `getNextPending()` | Gets the next item to process |

---

### 13. Native Android — UploadReschedulerService.kt

**The actual upload engine** — a foreground service running in the `:upload` process.

**`processQueue(queue: List<PendingUpload>)`** — sequential processor:

```
For each item in queue:
  1. Check network availability (wait up to 5 minutes if offline)
  2. Verify file exists and is non-empty
  3. Set status → 'uploading'
  4. performS3Upload(file, uploadUrl, contentType)
     ├─ HttpURLConnection PUT with streaming (64KB buffer)
     ├─ setFixedLengthStreamingMode (no memory buffering)
     ├─ Read timeout: 600s (10 min) | Connect timeout: 60s
     ├─ Reports progress every 5% change
     └─ 3 retries with exponential backoff (5s, 10s, 15s)
  5. performServerCallback(callbackUrl, callbackBody, authToken)
     └─ POST JSON to create lesson record on server
  6. Mark 'completed' in native_uploads.json
  7. Show completion notification
  8. After batch completes, check for new pending items
```

**Wake lock**: 60 minutes (prevents CPU sleep during large uploads).
**WiFi lock**: `WIFI_MODE_FULL_HIGH_PERF` (maintains high-speed WiFi).

---

### 14. Native Init (`lib/app/native_init.dart`)

**4-Phase Recovery Pipeline** (runs on every app start):

```
Phase 1 - FSS Recovery
  └─ Re-insert items from FlutterSecureStorage into SQLite
     (handles crash before SQLite insert)

Phase 2 - Native Orphan Recovery
  └─ Read native_uploads.json via MethodChannel
  └─ Mark completed/failed items in SQLite
  └─ Prevent re-upload of already-processed items

Phase 3 - Stale Lock Clear
  └─ Reset items stuck in 'uploading' >30 min back to 'pending'

Phase 4 - Auto Resume
  └─ If pending items remain, rebuild native queue from SQLite
  └─ Restart the foreground service
```

---

## Complete Upload Flow (Step by Step)

```
User taps "Add Video" in ManageModuleScreen
  │
  ▼
ManageModuleAddLessonSheet.show()
  ├─ User picks video (ImagePicker)
  ├─ User enters title
  └─ Taps "Upload Video"
      │
      ▼
provider.addVideoLesson(moduleIndex, title, videoFile, queueProvider)
  │
  ├─ 1. Create Lesson(id, 'pending') → add to UI list
  │     └─ notifyListeners() → progress bar appears
  │
  ├─ 2. queueProvider.addModuleLessonToQueue(
  │       videoPath, lessonTitle, moduleId, courseId, lessonId)
  │     │
  │     ├─ 2a. Build ModuleLessonMetadata (includes lessonId)
  │     ├─ 2b. Save to FlutterSecureStorage (Crash Layer 1)
  │     ├─ 2c. Insert into SQLite → get queueId (Crash Layer 2)
  │     ├─ 2d. POST to server for presigned S3 URL
  │     │      └─ Response: {uploadUrl, fileUrl}
  │     ├─ 2e. NativeUploadBridge.startNativeUpload()
  │     │      └─ Writes to native_uploads.json (Crash Layer 3)
  │     ├─ 2f. Update SQLite: status='uploading', urls saved
  │     └─ 2g. Return queueId
  │
  ├─ 3. _queueItemToLesson[queueId] = lessonId
  │
  └─ 4. _startProgressPolling()
        └─ Timer.periodic(5s):
              ├─ NativeUploadBridge.getQueueItems()
              ├─ Match by _queueItemToLesson[queueId] → lessonId
              ├─ Update lesson.uploadProgress / lesson.uploadStatus
              └─ notifyListeners() → UI progress bar updates

  Meanwhile, in the background:
  ┌──────────────────────────────────────────────────────────┐
  │  UploadReschedulerService (":upload" process)            │
  │                                                          │
  │  processQueue():                                         │
  │    for each pending item:                                │
  │      1. performS3Upload() ← streams file, no OOM        │
  │         ├─ HttpURLConnection PUT                         │
  │         ├─ 60min wake lock, 10min read timeout           │
  │         ├─ 64KB buffer, reports every 5% progress        │
  │         └─ 3 retries with exponential backoff            │
  │                                                          │
  │      2. performServerCallback() ← creates lesson in DB   │
  │         ├─ POST {title, videoUrl, moduleId, duration}    │
  │         └─ On success → mark 'completed'                 │
  │                                                          │
  │      3. Update native_uploads.json → Flutter polls it    │
  └──────────────────────────────────────────────────────────┘

  When native queue is empty:
  ├─ _startProgressPolling detects empty native state
  ├─ Marks all tracked lessons as 'completed'
  ├─ Sets videoUrl from _pendingFileUrls cache
  └─ Stops polling timer
```

---

## Crash Survival Layers

```
Layer 1: FlutterSecureStorage
  ├─ Saved BEFORE SQLite insert
  ├─ Key: pending_upload_<timestamp>
  └─ Recovery: Phase 1 in native_init.dart — re-inserts into SQLite

Layer 2: SQLite (upload_queue.db)
  ├─ Full queue state with metadata
  ├─ Survives app kill, not process data clear
  └─ Recovery: Phase 3 & 4 — reset stale, auto-resume

Layer 3: Native JSON (native_uploads.json)
  ├─ Written by Kotlin in the main process
  ├─ Read by Kotlin in the :upload process
  ├─ Survives Flutter isolate death
  └─ Recovery: Phase 2 — mark completed/failed in SQLite
```

---

## Queue-to-Lesson Mapping (Why It Works Now)

```
SQLite Row (upload_queue table):
  id=42, status='uploading', metadata='{
    "moduleId": 5,
    "courseId": 12,
    "lessonTitle": "Intro Video",
    "lessonId": 101        ← NEW: persisted!
  }'

In-Memory Map (ManageModuleProvider):
  _queueItemToLesson = { 42: 101 }   ← queueId → lessonId

On App Restart:
  1. _fetchCourse() loads module 5, fetches existing lessons from server
  2. _restorePendingUploads() reads SQLite row id=42
  3. Parses metadata → lessonId=101
  4. Checks if any existing lesson has id=101 → skips if yes
  5. Creates placeholder Lesson(id=101, 'pending')
  6. Restores _queueItemToLesson[42] = 101
  7. Starts polling → gets progress updates from native
```

**Before the fix**: Match was by `lessonTitle` — if two lessons had the same title, or the title changed, the restore would create duplicates or miss items entirely.

---

## Key Configuration Values

| Parameter | Old Value | New Value | Why |
|-----------|-----------|-----------|-----|
| Read timeout | 30s | **600s (10 min)** | 3-4GB uploads take minutes |
| Connect timeout | 30s | **60s** | Conservative for slow networks |
| Wake lock | 10 min | **60 min** | Prevents CPU sleep mid-upload |
| Upload buffer | 8KB | **64KB** | Better throughput, fewer syscalls |
| Progress report | every 1% | every **5%** | Reduces disk I/O, same UX |
| Poll interval | 2s | **5s** | Reduces MethodChannel overhead |
| Retry delay | fixed 2s | **exponential 5s/10s/15s** | Better backoff for transient errors |
| Queue ID source | `DateTime.now()` | **`filePath.hashCode`** | Stable across restarts |
| Lesson match | by title | by **lessonId** | Reliable queue mapping |
