# Video/Resource Upload System — How It Works

## 1. Three Storage Layers

```
┌──────────────────────────────────────────────────────────────────┐
│                    STORAGE LAYERS                                │
│                                                                  │
│  FlutterSecureStorage (FSS)         ┌───────────────────────┐    │
│  ┌─────────────────────────┐        │  SQLite (upload_queue) │    │
│  │ pending_upload_* keys   │        │  ┌──────────────────┐  │    │
│  │ (JSON per entry)        │◄──────►│  │ id, filePath,    │  │    │
│  │                         │        │  │ status, uploadUrl │  │    │
│  │ + atomic_queue JSON     │        │  │ ...              │  │    │
│  └─────────────────────────┘        │  └──────────────────┘  │    │
│            │                        └───────────────────────┘    │
│            │ syncQueueToNative                                    │
│            ▼                                                      │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │  native_uploads.json (shared file between processes)      │    │
│  │  ┌────────────────────────────────────────────────────┐   │    │
│  │  │ items: [{id, filePath, uploadUrl, status, ...}]     │   │    │
│  │  │ activeIndex, isUploading, lastUpdated               │   │    │
│  │  └────────────────────────────────────────────────────┘   │    │
│  └──────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────┘
```

---

## 2. Full Upload Flow (App Alive)

```
USER picks videos
       │
       ▼
  1. SAVE TO STORAGE
     ├─ Insert each into SQLite (status: pending)
     ├─ Save path to FlutterSecureStorage (FSS)
     └─ Sync queue to native JSON file via MethodChannel
       │
       ▼
  2. START UPLOAD
     ├─ Start native :upload process (UploadReschedulerService)
     │   └─ This runs in a SEPARATE Android process
     │      → SURVIVES if user kills the app from Task Manager
     │
     ├─ Start Dart background isolate (flutter_background_service)
     │   └─ This runs for UI progress updates
     │      → DIES if user kills the app
       │
       ▼
  3. FOR EACH VIDEO in queue (sequential):
     │
     ├─ 3a. FETCH PRESIGNED URL
     │      POST /api/v1/assets/upload → get {uploadUrl, fileUrl}
     │      Save uploadUrl → SQLite + native JSON
     │
     ├─ 3b. UPLOAD TO S3
     │      PUT {uploadUrl} with file bytes
     │      Progress: 0% → 100%
     │      Notifications update in real-time
     │
     ├─ 3c. CALL SERVER API
     │      POST /api/v1/posts/video with {title, videoUrl, ...}
     │      (or course/lesson/resources endpoint)
     │
     └─ 3d. MARK COMPLETED
          SQLite: status = 'completed'
          Native JSON: status = 'completed'
          Notification: "Upload complete"
       │
       ▼
  4. QUEUE EMPTY → stop service
     └─ "All uploads complete" notification
```

---

## 3. What Happens When App is Killed (Task Manager)

```
┌─────────────────────────────────────────────────────────────────────┐
│  USER SWIPES APP FROM RECENT TASKS                                 │
│                                                                     │
│  ┌─────────────────────┐           ┌─────────────────────────┐      │
│  │  MAIN PROCESS dies  │           │  :upload PROCESS lives  │      │
│  │                     │           │                         │      │
│  │  • Dart VM destroyed │           │  • UploadRescheduler    │      │
│  │  • flutter_background│           │    Service continues    │      │
│  │    service stops     │           │                         │      │
│  │  • Notification from │           │  • Still has:           │      │
│  │    Dart disappears   │           │    - WakeLock + WifiLock│      │
│  │                     │           │    - Foreground notif    │      │
│  │  • 3 storage layers  │           │    - native_uploads.json│      │
│  │    persisted already│           │    - S3 upload in flight│      │
│  └─────────────────────┘           └─────────────────────────┘      │
│                                                                     │
│  :upload process continues looping through queue:                   │
│                                                                     │
│     while (items left in native_uploads.json):                       │
│       ├─ Read next item                                             │
│       ├─ Upload to S3 (HttpURLConnection PUT)                      │
│       ├─ Update notification progress (stays in notification bar)   │
│       ├─ Mark item completed in JSON                               │
│       └─ Loop to next item                                         │
│                                                                     │
│     When queue empty:                                               │
│       └─ stopSelf() → notification removed                          │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 4. What Happens on Reboot

```
PHONE REBOOTS
       │
       ▼
  BootReceiver.kt fires (ACTION_BOOT_COMPLETED)
       │
       ├─ Enqueue WorkManager periodic check (3 min interval)
       └─ Enqueue WorkManager one-time check (immediate)
              │
              ▼
         UploadWorker checks native_uploads.json
              │
              ├─ No file or empty → done
              │
              └─ Has pending items
                      │
                      ▼
                 Start UploadReschedulerService
                      │
                      ▼
                 Resume processing queue from where it left off
```

---

## 5. What Happens When App is Re-Opened

```
USER RE-OPENS APP
       │
       ▼
  native_init.dart runs (4-phase recovery)
       │
       ├─ PHASE 1: Recover from FlutterSecureStorage
       │   Read FSS → insert pending items into SQLite
       │   Remove stale entries (file deleted)
       │
       ├─ PHASE 2: Recover from native JSON
       │   Read native_uploads.json
       │   Items already completed → remove from FSS
       │   Items pending → add to SQLite
       │   Items failed → mark in SQLite
       │   Clear native JSON file
       │
       ├─ PHASE 3: Clear stale locks
       │   Reset items stuck as 'uploading' > 30 min → 'pending'
       │
       └─ PHASE 4: Auto-resume if items remain
           If SQLite has pending items:
             ├─ Sync queue to native JSON
             ├─ Start :upload process
             └─ Start Dart background isolate

  ── USER SEES: Current upload status instantly
     ── No errors, no "resume" button needed
```

---

## 6. Error Handling

```
┌────────────────────────────────────────────────────────────────────┐
│  ERROR                      WHAT HAPPENS                          │
│────────────────────────────────────────────────────────────────────│
│  File deleted before        Skip item, mark failed,               │
│  upload starts              continue to next in queue              │
│                                                                   │
│  Network down mid-upload    Wait up to 5 min, then retry           │
│                            (with exponential backoff: 2s, 4s, 8s) │
│                                                                   │
│  Presigned URL expired      Item stays as 'pending' in queue       │
│                            (re-fetched when re-processed)          │
│                                                                   │
│  S3 returns 4xx/5xx         Retry 3 times, then mark failed        │
│                            Continue to next item                   │
│                                                                   │
│  Phone sleeps               WakeLock prevents CPU sleep            │
│                            WifiLock prevents WiFi disconnect       │
│                                                                   │
│  OS kills :upload process   START_STICKY restarts service          │
│  (low memory)               WorkManager also detects orphans       │
│                                                                   │
│  Single upload fails         Only that item marked failed          │
│  (entire queue NOT wiped)   Remaining items continue processing    │
│                                                                   │
│  JSON file corrupt          Load returns null → fresh start        │
└────────────────────────────────────────────────────────────────────┘
```

---

## 7. Upload Types

All 4 types follow the same pattern, just different API endpoints:

```
       ┌─────────────┬──────────────────────────┬─────────────────────────────┐
       │ Type        │ Presigned URL Endpoint    │ Server Callback             │
       ├─────────────┼──────────────────────────┼─────────────────────────────┤
       │ Video Post  │ /api/v1/assets/upload    │ POST /api/v1/posts/video    │
       │ Course      │ /api/v1/upload/course    │ POST /api/v1/create/course  │
       │ Lesson      │ /api/v1/upload/module    │ POST /api/v1/module/lesson  │
       │ Resource    │ /api/v1/upload/resource  │ POST /api/v1/module/resource│
       └─────────────┴──────────────────────────┴─────────────────────────────┘
```

---

## 8. Key Files Reference

```
Native Android (Kotlin):
  UploadReschedulerService.kt   ← Main upload engine (survives kill)
  UploadStateManager.kt         ← Queue persistence
  UploadWorker.kt               ← WorkManager safety net
  MainActivity.kt               ← MethodChannel bridge
  BootReceiver.kt               ← Reboot recovery

Native iOS (Swift):
  BackgroundUploadManager.swift ← URLSession background uploads
  AppDelegate.swift             ← Bridge + session handling

Flutter (Dart):
  background_upload_service.dart  ← Dart queue processor + native orchestrator
  native_upload_bridge.dart       ← MethodChannel calls to native
  upload_path_storage.dart        ← FSS queue persistence
  upload_notification_service.dart ← Local notifications
  native_init.dart                ← App startup recovery (4 phases)
  upload_queue_repository.dart    ← SQLite CRUD

Config:
  AndroidManifest.xml           ← Permissions + service declarations
  Info.plist                    ← iOS background modes
```

---

## 9. The One Critical Bug That Was Fixed

```
BEFORE (broken):
  Upload item 1 → success
    → processQueue(item2) called
    → finally { stopSelf() } ← KILLS SERVICE
    → item 2 never runs
    → 15 MINUTE GAP until WorkManager detects
    → User sees stalled notification for 15 min

AFTER (fixed):
  Upload item 1 → success
    → Remove from JSON, save state
    → LOOP back for item 2
    → Upload item 2 → success
    → Remove from JSON, save state
    → LOOP back → queue empty
    → stopSelf() ← ONLY when empty
    → Notification: "All uploads complete"
```
