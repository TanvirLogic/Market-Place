# Eduverse Project Review

**Review Date:** June 21, 2026  
**Project Type:** Flutter Mobile Application (EdTech Platform)  
**Package Name:** edtech

---

## 1. Project Overview

Eduverse is a feature-rich EdTech mobile application with:
- User authentication (email/password, Google Sign-In, OTP verification)
- Student & mentor profiles with avatar/cover photo upload via presigned S3 URLs
- Course browsing, details, and enrollment
- Video playback using media_kit (mpv/FFmpeg native)
- Mentor dashboard with metrics and revenue tracking
- Ads management system
- Social feed and notifications

---

## 2. Architecture Analysis

### 2.1 Architecture Pattern
- **Feature-First with Provider + ChangeNotifier**
- Code is organized by business features (auth, home, courses, hub, etc.)
- Each feature has three conceptual layers: `data/`, `providers/`, `presentation/`

### 2.2 State Management
- Uses `provider` package (NOT Riverpod)
- Providers extend `ChangeNotifier`
- Global providers registered in `MultiProvider` in `app/app.dart:36-56`
- Screen-scoped providers created inline with `ChangeNotifierProvider`

### 2.3 Unidirectional Data Flow
```
Screen (UI) → Provider (Business Logic) → NetworkCaller (HTTP) → API
Screen ← Consumer<Provider> ← notifyListeners()
```

### 2.4 Key Architectural Rules
1. Screens never call HTTP directly - all via Provider → NetworkCaller chain
2. Providers never import `flutter/material.dart`
3. Models are pure Dart classes (no Flutter dependencies)
4. Auth data stored in `flutter_secure_storage` for tokens, `shared_preferences` for user data

---

## 3. Directory Structure

```
lib/
├── main.dart                           # Entry point
├── app/
│   ├── app.dart                        # Root widget with MultiProvider
│   ├── app_routes.dart                 # Named routes (25 routes)
│   ├── app_theme.dart                  # Light/Dark theme
│   ├── app_colors.dart                 # Color constants
│   ├── urls.dart                       # API endpoint builders
│   ├── setup_network_caller.dart       # NetworkCaller factory with 401 handling
│   └── providers/
│       └── theme_provider.dart         # ThemeMode management
├── global/core/
│   ├── services/
│   │   ├── network_caller.dart         # HTTP client (GET/POST/PUT/DELETE)
│   │   ├── logger_service.dart         # API request logging
│   │   ├── toast_service.dart          # In-app notifications
│   │   ├── secure_storage.dart         # Token persistence
│   │   └── upload_notification_service.dart # Background upload notifications
│   ├── models/
│   │   └── network_response.dart       # Response DTO
│   ├── widgets/                        # Shared UI components
│   └── constants/
│       └── sizes.dart                  # Padding/spacing constants
└── features/
    ├── auth/                           # Authentication
    ├── home/                           # Main navigation shell
    ├── courses/                        # Course upload/video upload
    ├── course_details/                 # Course detail view
    ├── hub/                            # Settings, dashboard, payments
    ├── social/                         # Video feed
    ├── notifications/                  # Notification list
    └── profile/                        # Student/Mentor profile + avatar
```

---

## 4. Feature Completion Status

| Feature | Status | Notes |
|---------|--------|-------|
| Authentication (login, register, OTP, Google Sign-In) | ✅ Real API | `auth/data/services/google_sign_in_service.dart` |
| Token refresh & auto-login | ✅ Real | Splash screen triggers `tryRefreshToken()` |
| Student/Mentor Profiles | ✅ Real API | `profile/me` endpoint |
| Edit Profile | ✅ Real API | `profile/update` endpoint |
| Avatar/Cover upload | ✅ Real | Presigned S3 URLs |
| Change Password | ✅ Real API | `auth/change-password` endpoint |
| Course Details | ⚠️ Mock data | Readme says API removed |
| Course Upload | ✅ Functional | Complex multi-step upload with notification |
| Video Playback | ✅ Real | media_kit integration with VideoPlayerProvider |
| Mentor Dashboard | ⚠️ Partial mock | Some data mocked |
| Ads Manager | ⚠️ UI only | |
| Social Feed | ❌ Static mock | `social/presentation/pages/social_page.dart` uses mock data |
| Notifications | ❌ Static mock | |

---

## 5. Key Technical Components

### 5.1 Authentication Flow
- **UserModel** (`auth/data/models/user_model.dart`): Contains user data + tokens
- **AuthController** (`auth/data/models/auth_controller.dart`): Static class managing token/user persistence
- **SignInProvider** (`auth/providers/sign_in_provider.dart`): 
  - Email/password sign-in
  - Google Sign-In (2-step: idToken → role selection for new users)
  - Token refresh logic
  - Logout with backend call + Google sign-out

### 5.2 Network Layer
- **NetworkCaller** (`global/core/services/network_caller.dart`):
  - Supports GET/POST/PUT/DELETE
  - Automatic token injection via `getNetworkCaller()`
  - 401 handling with `onUnauthorize` callback → clears auth, navigates to login
  - Token refresh retry mechanism via `onRefreshToken` callback
  - Logging via `logger` package

### 5.3 Course Upload Flow
- **CourseUploadProvider** (`courses/providers/course_upload_provider.dart`):
  - Multi-step upload: thumbnail → video → course creation
  - Progress tracking with `UploadStep` enum
  - Background notification service via `UploadNotificationService`
  - S3 direct upload with streaming (handles large files efficiently)
  - Cancellation support

### 5.4 Video Player
- Uses `media_kit` + `media_kit_video` packages
- **VideoPlayerProvider** (`global/core/providers/video_player_provider.dart`):
  - Centralized video controller management
  - Open/dismiss/playback control methods
  - Prevents multiple video players from conflicting

---

## 6. API Configuration

- **Base URL:** `http://108.181.195.154:3000/api/v1` (`AppConfig.baseUrl:10`)
- **Timeout:** 30 seconds (`AppConfig.requestTimeout`)
- **Auth Headers:** `Authorization: Bearer <token>`
- **Error Message Key:** `message` (`setup_network_caller.dart:16`)

**Key Endpoints:**
- Auth: `/auth/login`, `/auth/register`, `/auth/google`, `/auth/refresh`
- Profile: `/profile/me`, `/profile/update`
- Courses: `/course`, `/course-assets/upload`, `/courses`
- Dashboard: `/mentor/dashboard`

---

## 7. Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| flutter | sdk | Framework |
| provider | ^6.1.5+1 | State management |
| http | ^1.2.1 | REST API client |
| flutter_secure_storage | ^10.1.0 | Token persistence |
| shared_preferences | ^2.2.3 | Email caching, preferences |
| google_sign_in | ^6.2.1 | Google OAuth |
| media_kit | ^1.1.10 | Video playback |
| cached_network_image | ^3.4.1 | Image caching |
| google_fonts | ^8.1.0 | Typography |
| logger | ^2.7.0 | Request logging |

---

## 8. Notable Patterns

### 8.1 Provider Template (from `sign_in_provider.dart`)
```dart
class SomeProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;
  
  Future<bool> fetchData() async {
    _isLoading = true;
    notifyListeners();
    
    final response = await getNetworkCaller().getRequest(url: Urls.someUrl);
    
    if (response.isSuccess) {
      // Update state
      _errorMessage = null;
    } else {
      _errorMessage = response.errorMessage;
    }
    
    _isLoading = false;
    notifyListeners();
    return isSuccess;
  }
}
```

### 8.2 Navigation Guard
- Cart/Wishlist tabs check authentication before navigating (`MainNavShell`)
- Unauthorized → redirect to login

### 8.3 Pagination Pattern
- Used in `CategoryListProvider` and `ProductListByCategoryProvider`
- `_currentPageNo` starts at 0, increments before API call
- `_lastPageNo` set once from first response
- Two loading states: `_initialLoading` and `_loadingMoreProduct`

---

## 9. Code Quality Observations

### Strengths
1. **Clean separation of concerns** - screens, providers, models are well-separated
2. **Consistent error handling** - `NetworkResponse` normalizes all API responses
3. **Good use of DI** - `ImagePicker` and `GoogleSignInService` injected in providers for testability
4. **Comprehensive video upload** - Progress tracking, cancellation, background notifications
5. **Responsive video player** - Integrated with `media_kit` for native performance

### Areas for Improvement
1. **No tests** - README confirms no tests exist
2. **Missing localization** - Assets and strings aren't localized
3. **Some provider duplication** - `_refreshToken` exists in both `setup_network_caller.dart` and `sign_in_provider.dart`
4. **Complex CourseModel recreation** - Every update creates a new full `CourseModel` instead of immutable patterns
5. **Hardcoded strings** in UI (e.g., `'You are not eligible to comment'` in `course_detail_provider.dart`)
6. **Social feed uses static mock data** - `social_page.dart` needs API integration

---

## 10. Asset Assets

- App icon: `assets/images/app/`
- Navigation icons: `assets/images/icons/nav/`
- Hub icons: `assets/images/icons/hub/`
- Course icons: `assets/images/icons/course/`
- Profile icons: `assets/images/profile_icons/`
- Social icons: `assets/images/social_icons/`
- Revenue icons: `assets/images/revenue_icons/`

---

## 11. Summary

The project is a well-structured Flutter EdTech application with:
- A working authentication system with JWT and refresh tokens
- Incomplete course-related features (social feed, notifications mocked)
- Strong video upload functionality with progress tracking
- Good architectural patterns following feature-first with Provider

The codebase is production-ready for auth flows and profile features, but social and notification features need backend integration.