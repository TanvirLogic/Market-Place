# Eduverse-Clone — Developer Context

## Architecture
- **Framework:** Flutter (SDK ^3.11.1)
- **State Management:** Provider (ChangeNotifier + Consumer)
- **HTTP Client:** `package:http` (no Dio)
- **Routing:** Named routes via `onGenerateRoute` in `app/app_routes.dart`
- **Theming:** Material 3, light/dark via `ThemeProvider`
- **Auth:** JWT tokens stored in `flutter_secure_storage`, user in `SharedPreferences`

## Key Directories
- `lib/features/` — Feature modules (auth, courses, course_details, manage_module, home, hub, profile, etc.)
- `lib/global/core/` — Shared services, widgets, config
- `lib/app/` — App-level wiring (routes, URLs, themes, providers)

## Upload System (background queue)
- **Upload Queue Package:** `packages/upload_queue/` — reusable Dart package
- **Legacy Provider:** `UnifiedUploadQueueProvider` — still in use, being migrated
- **Engine:** `package:http` — direct S3 PUT (< 15MB) or multipart PUT (>= 15MB) via presigned URLs
- **No multipart/form-data used** — all backend calls are `application/json` POST, S3 uploads are binary PUT
- **Unified init endpoint** — same POST returns `{isMultipart: false, uploadUrl, fileUrl}` or `{isMultipart: true, uploadId, parts[], fileUrl}`
- **Upload types:** `module_lesson`, `resource`, `video_post`, `course`, `course_intro`, `course_thumb`
- **Endpoint patterns:**
  - Init/Complete: `/course/module/lesson/upload`, `/course/module/resource/assets/upload`, `/video-post/assets/upload`, `/course/assets/upload`
  - Callbacks: `/course/module/lesson`, `/course/module/resource`, `/video-post`, `/course`
- **Avatars/Covers:** Separate non-queued 2-step (presigned URL → PUT → confirm)

## Data Layer
- SQLite via `sqflite` for upload queue persistence
- Manual JSON parsing (no freezed/json_serializable)
- `NetworkCaller` handles GET/POST/PUT/DELETE with auto 401 retry

## Key Providers
| Provider | File |
|---|---|
| `UnifiedUploadQueueProvider` | `features/courses/providers/unified_upload_queue_provider.dart` |
| `ManageModuleProvider` | `features/manage_module/providers/manage_module_provider.dart` |
| `AuthController` (static) | `features/auth/data/models/auth_controller.dart` |
| `ThemeProvider` | `app/providers/theme_provider.dart` |
| `VideoPlayerProvider` | `global/core/providers/video_player_provider.dart` |

## Models
- `UploadQueueItem`, `PartETag`, `PartPresignedUrl`, `MultipartInitResult`, `ModuleLessonMetadata` — in `features/courses/data/models/upload_task.dart`
- `PendingLesson`, `CourseModule`, `Lesson`, `Module`, `LessonType` — in `features/manage_module/data/manage_module_models.dart`

## API Base URL
`http://108.181.195.154:3000/api/v1` (in `app/config/app_config.dart`)

## Running the Project
- `flutter pub get`
- `flutter run` (requires Android/iOS device or emulator)
