# Eduverse — EdTech Mobile Application

Eduverse is an EdTech platform built with Flutter, featuring authentication, user/mentor profiles with avatar upload, course browsing (mock data), video playback, mentor dashboard, and ad campaigns.

## Architecture: Feature-First with Provider

Feature-first folder structure with `Provider` + `ChangeNotifier` for state management. Providers call a `NetworkCaller` service directly (no repository/use-case abstraction layer).

```
lib/
├── features/
│   ├── auth/              # Login, register, password recovery, Google Sign-In
│   ├── splash/            # Auto-login via token refresh
│   ├── home/              # Main bottom-nav shell (Social/Post/Courses/Hub tabs)
│   ├── courses/           # Course details, enrolled courses, upload course/video, module management
│   ├── hub/               # Settings, mentor dashboard, payments/revenue, ads manager, password/security
│   ├── social/            # Video feed with search
│   ├── notifications/     # In-app notification list
│   ├── profile/
│   │   ├── student/       # Student profile view & edit
│   │   ├── mentor/        # Mentor profile view
│   │   ├── edit/          # Shared edit profile form
│   │   └── avatar/        # Avatar/cover photo upload (presigned S3)
│   └── posts/             # (placeholder)
└── global/core/
    ├── config/            # AppConfig (baseUrl, googleClientId, timeout)
    ├── constants/         # Image asset paths, text colors
    ├── routes/            # AppRoutes (25 named routes + onGenerateRoute)
    ├── services/          # NetworkCaller, LoggerService, ToastService, SecureStorage
    ├── theme/             # AppTheme (light + dark, Urbanist font)
    └── widgets/           # Shared widgets (AuthButton, ShimmerWidget, etc.)
```

### Tech Stack

| Technology | Usage |
|------------|-------|
| Flutter / Dart SDK ^3.11.1 | Framework |
| Provider (ChangeNotifier) | State Management |
| http | REST API client |
| flutter_secure_storage | Token persistence |
| shared_preferences | Email caching & preferences |
| google_sign_in | Google OAuth |
| flutter_svg | SVG icon rendering |
| google_fonts (Urbanist) | Typography |
| image_picker | Avatar/cover image selection |
| image_cropper | Avatar/cover crop UI |
| media_kit + media_kit_video | Video playback (mpv/FFmpeg native decoders) |
| logger | API request/response logging |
| cached_network_image | Image caching |
| url_launcher | Open external links |

## Feature Completion Status

| Feature Area | Status |
|---|---|
| **Authentication** (login, register, OTP, password reset, Google Sign-In) | ✅ Real API calls |
| **Token refresh & auto-login** | ✅ Real |
| **Student & Mentor Profiles** (view) | ✅ Real API |
| **Edit Profile** (save) | ✅ Real API |
| **Avatar / Cover upload** (presigned S3) | ✅ Real |
| **Change Password** | ✅ Real API |
| **Course Details** | ⚠️ Mock data (API removed) |
| **Enrolled Course** | ⚠️ Mock data (API removed) |
| **Course List** | ❌ Not wired to UI |
| **Course Upload / Video Upload** | ❌ UI only, non-functional |
| **Module Management** | ⚠️ Local-only, no API |
| **Social Feed** | ❌ Static mock data |
| **Notifications** | ❌ Static mock data |
| **Ads Manager** | ⚠️ UI mostly |
| **Mentor Dashboard** | ⚠️ Partial mock data |

## Routes

| Route | Page | Arguments |
|-------|------|-----------|
| `/` | SplashPage | — |
| `/login` | LoginPage | — |
| `/register` | RegisterPage | — |
| `/forgot-password` | ForgotPasswordPage | — |
| `/verification` | VerificationPage | `{email}` |
| `/reset-verification` | ResetVerificationPage | — |
| `/reset-password` | SetNewPasswordPage | — |
| `/password-success` | PasswordSuccessPage | `{title, subtitle, buttonText, email}` |
| `/home` | MainNavShell | — |
| `/profile` | StudentProfilePage | — |
| `/mentor-profile` | MentorProfilePage | — |
| `/edit-profile` | EditProfilePage | — |
| `/password-and-security` | PasswordAndSecurityPage | — |
| `/payments-and-revenue` | PaymentsAndRevenuePage | — |
| `/mentor-dashboard` | MentorDashboardPage | — |
| `/full-screen-image` | FullScreenImageViewer | `{imageUrl}` |
| `/upload-video-page` | UploadVideoPage | — |
| `/upload-course-page` | UploadCoursePage | — |
| `/course-details` | CourseDetailsPage | `{courseId}` |
| `/enrolled-course` | EnrolledCoursePage | `{courseId}` |
| `/payment-success` | PaymentSuccessPage | `{amount, courseName, trxId}` |
| `/notifications` | NotificationsPage | — |
| `/manage-module` | ManageModulePage | — |
| `/ads-manager` | AdsManagerPage | — |
| `/ads-create` | AdsCreatePage | — |

## API Configuration

- **Base URL:** `http://108.181.195.154:3000/api/v1/` (`AppConfig.baseUrl`)
- **Timeout:** 30 seconds (`AppConfig.requestTimeout`)
- **Auth endpoints:** Real, wired to backend
- **Course endpoints:** Removed — screens use local mock data (API integration pending)

## Getting Started

1. `flutter pub get`
2. `flutter run`

## Testing

No tests currently exist.

## Documentation

- `API_EXPLANATION.md` — API integration patterns & flows
- `API_IMPLEMENTATION_GUIDE.md` — Implementation guide
