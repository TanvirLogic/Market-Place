# API Implementation Guide — Eduverse

A prompt-based approach. Give an AI the **API Details + Response** + one of the prompts below, and it will generate the exact files to paste.

**Base URL:** `http://108.181.195.154:3000/api/v1` (defined in `lib/app/urls.dart`)

---

## Project Architecture (30-second overview)

This project does **NOT** use Clean Architecture layers (no `UseCase`, `Repository`, `DataSource`, `Either`, `Failure`). Instead:

```
Screen → Provider (ChangeNotifier) → NetworkCaller → API
```

- **Provider** calls `getNetworkCaller()` → `postRequest()` / `getRequest()` / `putRequest()` directly
- **Auth endpoints** use `getNetworkCaller(isPublic: true)` (no Bearer token, no refresh)
- **Non-auth endpoints** use `getNetworkCaller()` (auto-sends Bearer token, auto-refresh on 401)
- **No UseCase / Repository / DataSource classes** — providers talk to NetworkCaller directly
- **API URLs** are static strings in `lib/app/urls.dart`
- **Providers** are registered in `lib/app/app.dart` via `MultiProvider`
- **Error message key** is `'message'` — the server must return `{"message": "..."}` on errors

---

## Quick Steps (Any API)

1. **Add the URL** to `lib/app/urls.dart`
2. **Register the provider** in `lib/app/app.dart`
3. **Pick the pattern** below that matches your API
4. **Copy the prompt** and fill in your API details + JSON response
5. **Send to an AI** — it will return file paths and code
6. **Paste the code** into the specified files
7. **Wire the UI** — use `Consumer<YourProvider>` in your screen

---

## Part 1: API Integration Patterns

### Pattern 1: Simple Fetch (GET a list or single object)

Use when: `GET /courses`, `GET /profile/me`, etc.

#### Prompt to give AI:

```
I have a Flutter project using Provider + NetworkCaller. I need to integrate an API endpoint.

Project details:
- Package name: edtech
- Base URL: http://108.181.195.154:3000/api/v1 (define new endpoints in lib/app/urls.dart)
- Network calls: getNetworkCaller().getRequest(url: Url) / .postRequest(url:, body:) in the provider
- Auth: use getNetworkCaller() for most endpoints (auto Bearer + refresh)
- Public: use getNetworkCaller(isPublic: true) for login/register/forgot-password (no token)
- Response format: jsonDecode returns Map. Access data via response['data']
- Error messages: server returns {"message": "..."} — errorMessage is extracted automatically
- Provider pattern: ChangeNotifier with isLoading, errorMessage, data fields + notifyListeners()
- Provider registration: in lib/app/app.dart via ChangeNotifierProvider
- Toast: ToastService.showError() / showSuccess() / showInfo()
- Logger: AppLogger.i() / .e() / .w() for debug logging
- The getNetworkCaller() already handles: Bearer token header, 401 auto-refresh, token persistence in SecureStorage

API Details:
- Endpoint: {endpoint_url}
- Method: GET
- Response: {response_json}

I need you to generate:
1. URL constant in lib/app/urls.dart (if not already there)
2. Provider at lib/features/{feature}/providers/{name}_provider.dart — ChangeNotifier with fetchData(), isLoading, errorMessage, data getters. Uses getNetworkCaller().getRequest() directly.
3. Provider registration line for lib/app/app.dart
Return ONLY the file path and the code content for each file.
```

---

### Pattern 2: Create / Update (POST / PUT with body)

Use when: `POST /course`, `PUT /profile/update`, etc.

#### Prompt to give AI:

```
I have a Flutter project using Provider + NetworkCaller. I need to integrate a create/update API.

Project details:
- Same as Pattern 1 (above)
- POST calls: getNetworkCaller().postRequest(url:, body:)
- PUT calls: getNetworkCaller().putRequest(url:, body:)
- Return type: Future<bool> — true on success, toast error on failure
- Loading state: isLoading bool with notifyListeners()

API Details:
- Endpoint: {endpoint_url}
- Method: POST
- Request body: {request_body_json}
- Response: {response_json}

Generate:
1. URL constant in lib/app/urls.dart (if not there)
2. Provider with update method returning Future<bool>
3. Provider registration line for lib/app/app.dart
```

---

### Pattern 3: File Upload with Presigned URL (Avatar / Cover / Course Assets)

Use when: POST to get upload URL → PUT file to S3 → PUT to confirm.

Current reference implementations:
- Avatar: `lib/features/avatar/providers/avatar_upload_provider.dart`
- Cover: `lib/features/avatar/providers/cover_upload_provider.dart`
- Course assets: `lib/features/courses/providers/course_upload_provider.dart`

#### Prompt to give AI:

```
I have a Flutter project using Provider + NetworkCaller. I need to integrate a presigned URL upload flow.

Project details:
- Same as Pattern 1
- Step 1: POST to API with body (filename/contentType) → get {uploadUrl, fileUrl}
- Step 2: PUT file bytes to S3 via http.StreamedRequest (64KB chunks, progress tracking)
- Step 3: PUT to API with body {fileUrl} to confirm
- Use http.StreamedRequest for S3 PUT (not NetworkCaller)
- Use NetworkCaller's postRequest / putRequest for API calls
- Progress: uploadProgress double (0.0-1.0), notifyListeners() on each chunk
- Reference: lib/features/avatar/providers/avatar_upload_provider.dart

API Details:
- Get URL endpoint: {endpoint_1} — POST — body: {filename, contentType}
- Confirm endpoint: {endpoint_2} — PUT — body: {fileUrl}

Generate:
1. URL constants in lib/app/urls.dart
2. Provider with full 3-step flow (get URL → stream to S3 with progress → confirm)
   - Pick file via ImagePicker (for images) or ImagePicker.pickVideo (for video)
   - Track _step enum for UI state (uploadingUrls, uploadingToS3, confirming, done, error)
   - buttonText getter for multi-step button status
   - Cancel support (_isCancelled bool, _activeClient, cancel() method)
3. Provider registration line for lib/app/app.dart
```

---

### Pattern 4: Delete (DELETE)

Use when: `DELETE /courses/:id`, etc.

`NetworkCaller.deleteRequest()` is available — same auto-auth, refresh, and logging as all other methods.

#### Prompt to give AI:

```
I have a Flutter project using Provider + NetworkCaller. I need to integrate a DELETE endpoint.

Project details:
- Same as Pattern 1
- DELETE calls: getNetworkCaller().deleteRequest(url:)
- Return type: Future<bool>

API Details:
- Endpoint: {endpoint_url}
- Method: DELETE
- Response: {response_json}

Generate:
1. URL constant in lib/app/urls.dart
2. Provider method using getNetworkCaller().deleteRequest()
```

---

### Pattern 5: Paginated List (GET with page/limit)

Use when: `GET /courses?page=1&limit=10`.

Simply pass query params in the URL:

```dart
final url = '${Urls.courseListUrl}?page=$page&limit=$limit';
final response = await getNetworkCaller().getRequest(url: url);
final listData = response.responseData['data'];
final items = (listData['items'] as List).map(...);
final hasMore = listData['page'] < listData['totalPages'];
```

---

### Pattern 6: Search / Filter (GET with query params)

Same as a regular GET — just append query params to the URL string:

```dart
final url = '${Urls.searchUrl}?q=${Uri.encodeComponent(query)}&filter=$filter';
final response = await getNetworkCaller().getRequest(url: url);
```

For debounced search in the UI, use a `Timer` with 500ms delay in the provider.

---

### Pattern 7: Auth Endpoint (Login / Register / Refresh / Verify OTP)

Use when: the endpoint returns tokens. **Must use `getNetworkCaller(isPublic: true)`**.

#### Prompt to give AI:

```
I have a Flutter project using Provider + NetworkCaller. I need to integrate an auth API.

Project details:
- Same as Pattern 1
- CRITICAL: Use getNetworkCaller(isPublic: true) — do NOT send Bearer token
- AuthController: static class at lib/features/auth/data/models/auth_controller.dart
  - Static fields: accessToken?, userModel?
  - Static methods: saveUserData(token, UserModel), clearUserData()
- SecureStorage stores access + refresh tokens (lib/global/core/services/secure_storage.dart)
- UserModel: lib/features/auth/data/models/user_model.dart (has fromJson/toJson)
- Token save must happen AFTER the API call in the provider method
- Response format: {"message": "...", "data": {"user": {...}, "accessToken": "...", "refreshToken": "..."}}

API Details:
- Endpoint: {endpoint_url}
- Method: POST
- Request body: {request_body_json}
- Response: {response_json}

Generate:
1. URL constant in lib/app/urls.dart (if not there)
2. Provider method in the appropriate existing provider (sign_in_provider.dart, sign_up_provider.dart, verify_otp_provider.dart, or password_reset_provider.dart)
   - Calls getNetworkCaller(isPublic: true).postRequest()
   - Saves tokens via AuthController.saveUserData() on success
   - Returns Future<bool>
```

---

### Pattern 8: Refetch Profile After Mutation (Avatar/Cover/Profile Update)

Already handled — every upload/update provider has an `onUploadSuccess` callback. The profile screen sets it in `initState`:

```dart
context.read<AvatarUploadProvider>().onUploadSuccess = (newUrl) {
  context.read<MentorProfileProvider>().fetchProfile();
};
```

---

## Part 2: UI Consumption Patterns

Once a provider is set up, here's how to consume it in the **presentation layer**.

### Pattern UI-1: Three-State Screen (Loading / Error / Data)

The most common pattern. Show a shimmer while loading, an error state on failure, and the full UI on success.

```dart
// In your screen's build method:
Consumer<YourProvider>(
  builder: (context, provider, _) {
    // 1. LOADING STATE
    if (provider.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Title')),
        body: const YourSkeleton(), // shimmer or CircularProgressIndicator
      );
    }

    // 2. ERROR STATE
    if (provider.errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Title')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(provider.errorMessage!),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.read<YourProvider>().fetchData(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // 3. DATA STATE
    final data = provider.data;
    if (data == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Title')),
        body: const Center(child: Text('No data available')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Title')),
      body: YourContent(data: data),
    );
  },
);
```

**Existing references:**
- `course_details_screen.dart` — shows `_CourseDetailsSkeleton` while `course == null`, then full UI
- `student_profile_screen.dart` — Consumer with loading/error/data branches

### Pattern UI-2: Init Fetch on Screen Open

Always call your provider's fetch method in `initState` via `addPostFrameCallback`:

```dart
// For a StatefulWidget:
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    context.read<YourProvider>().fetchData();
  });
}
```

**For screen-scoped providers** (created inline with `ChangeNotifierProvider`):

```dart
class YourScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CourseDetailProvider()..loadCourse('1'),
      child: _YourBody(),
    );
  }
}
```

**Existing references:**
- `enrolled_course_screen.dart` — passes provider directly in `create`
- `course_details_screen.dart` — calls `loadCourse` in `initState`
- `student_profile_screen.dart` — calls `fetchProfile()` in `initState`

### Pattern UI-3: Form Submission with Loading Button

Use `AuthButton` widget for forms. It shows a `CircularProgressIndicator` while the provider is loading.

```dart
Consumer<YourProvider>(
  builder: (context, provider, _) => AuthButton(
    text: "Submit",
    isLoading: provider.isLoading,
    onPressed: provider.isLoading
        ? null
        : () async {
            final success = await provider.submitData(...);
            if (success && context.mounted) {
              Navigator.pop(context); // or push to next screen
            }
          },
  ),
)
```

**Existing references:**
- `sign_in_screen.dart` — `AuthButton` with `provider.inProgress`
- `edit_profile_screen.dart` — `AuthButton` with `provider.isLoading`

### Pattern UI-4: Form Validation + API Call

Collect form values → validate → call provider → handle result.

```dart
final _formKey = GlobalKey<FormState>();
final _emailController = TextEditingController();
final _passwordController = TextEditingController();

void _handleSubmit() async {
  if (!_formKey.currentState!.validate()) return;

  final provider = context.read<YourProvider>();
  final success = await provider.submitData(
    _emailController.text.trim(),
    _passwordController.text,
  );

  if (success && context.mounted) {
    Navigator.pushReplacementNamed(context, AppRoutes.nextScreen);
  }
}
```

**Key points:**
- Always use `Form` + `GlobalKey<FormState>` for validation
- Call `TextEditingController.dispose()` in `dispose()`
- Check `mounted` after async gaps before using `context` or `Navigator`

**Existing references:**
- `sign_in_screen.dart` — full login form with validation
- `edit_profile_screen.dart` — multi-field form with social links

### Pattern UI-5: App-Scoped vs Screen-Scoped Providers

**App-scoped** (registered in `app.dart`): Use for data shared across screens (profile, auth, theme).

```dart
// Read (no rebuild):
context.read<StudentProfileProvider>().fetchProfile();

// Watch (rebuild on change):
context.watch<StudentProfileProvider>().profile;
```

**Screen-scoped** (created inline): Use for data only needed on one screen (course details, upload).

```dart
ChangeNotifierProvider(
  create: (_) => CourseDetailProvider()..loadCourse('1'),
  child: Consumer<CourseDetailProvider>(
    builder: (context, provider, _) {
      if (provider.course == null) return Skeleton();
      return FullUI(course: provider.course!);
    },
  ),
)
```

**Rule of thumb:** If only one screen uses the data, make it screen-scoped. If multiple screens need it, register it in `app.dart`.

### Pattern UI-6: Upload Progress UI

For file uploads with progress tracking:

```dart
Consumer<AvatarUploadProvider>(
  builder: (context, provider, _) {
    if (provider.isUploading) {
      return Column(
        children: [
          LinearProgressIndicator(value: provider.uploadProgress),
          const SizedBox(height: 8),
          Text('${(provider.uploadProgress * 100).toInt()}%'),
        ],
      );
    }
    // Normal state
  },
)
```

**Existing references:**
- `edit_profile_screen.dart` — avatar upload with progress bar
- `upload_course_screen.dart` — multi-step upload with dynamic button text

### Pattern UI-7: Pull-to-Refresh

Wrap content in `RefreshIndicator`:

```dart
RefreshIndicator(
  onRefresh: () => context.read<YourProvider>().fetchData(),
  child: ListView(/* your content */),
)
```

**Existing references:**
- `student_profile_screen.dart` — pull-to-refresh on profile
- `mentor_profile_screen.dart` — pull-to-refresh on mentor profile

### Pattern UI-8: Toast After API Action

Show success/error messages after API calls:

```dart
// In provider:
if (response.isSuccess) {
  ToastService.showSuccess("Item created successfully!");
} else {
  ToastService.showError(response.errorMessage ?? 'Something went wrong');
}
```

**Important:** Toast messages are displayed via `scaffoldMessengerKey` (globally wired in `MaterialApp`), so they work even when providers don't have a `BuildContext`.

### Pattern UI-9: Navigation After API Success

After a successful API call in the provider, the screen decides what to do:

```dart
// In screen:
final success = await provider.submitData(...);
if (success && context.mounted) {
  // Option A: pop back
  Navigator.pop(context);

  // Option B: push to next screen
  Navigator.pushNamed(context, AppRoutes.nextScreen, arguments: {...});

  // Option C: replace current screen
  Navigator.pushReplacementNamed(context, AppRoutes.home);
}
```

**Existing references:**
- `sign_in_screen.dart` — `Navigator.pushReplacementNamed` after sign-in
- `register_screen.dart` — `Navigator.pushNamed` to verification after sign-up
- `edit_profile_screen.dart` — `Navigator.pop` after profile update

### Pattern UI-10: Google Sign-In Flow (Full Example)

Complete UI flow:

```dart
// 1. Show role bottom sheet
final role = await showModalBottomSheet<String>(context: context, builder: ...);
if (role == null || !context.mounted) return;

// 2. Get Google idToken
final idToken = await authProvider.getGoogleIdToken();
if (idToken == null || !context.mounted) return;

// 3. Send to backend
final success = await authProvider.completeGoogleSignIn(idToken, role);
if (success && context.mounted) {
  Navigator.pushReplacementNamed(context, AppRoutes.home);
}
```

**Existing reference:** `sign_in_screen.dart:_GoogleButton.build()` — full implementation.

---

## File Reference

| File | Purpose |
|------|---------|
| `lib/app/urls.dart` | All API endpoint strings |
| `lib/app/app.dart` | Provider registration via `MultiProvider` |
| `lib/app/setup_network_caller.dart` | `getNetworkCaller({isPublic})` factory — headers, refresh, unauthorize |
| `lib/global/core/services/network_caller.dart` | `NetworkCaller` class — get/post/put requests, 401 refresh, retry |
| `lib/global/core/models/network_response.dart` | `NetworkResponse` class (isSuccess, responseCode, responseData, errorMessage) |
| `lib/global/core/services/logger_service.dart` | `AppLogger` — colored console logging |
| `lib/global/core/services/toast_service.dart` | `ToastService` — showSuccess/showError/showInfo |
| `lib/global/core/services/secure_storage.dart` | `SecureStorage` — FlutterSecureStorage wrapper for tokens |
| `lib/features/auth/data/models/auth_controller.dart` | `AuthController` — static token/user state |
| `lib/features/auth/data/models/user_model.dart` | `UserModel` — user data model with fromJson/toJson |
| `lib/global/core/widgets/auth_button.dart` | Reusable submit button with disabled state |

---

## Existing Providers (Reference)

| Feature | Provider File | Pattern |
|---------|--------------|---------|
| Sign In | `lib/features/auth/providers/sign_in_provider.dart` | Auth (isPublic) |
| Sign Up | `lib/features/auth/providers/sign_up_provider.dart` | Auth (isPublic) |
| Verify OTP | `lib/features/auth/providers/verify_otp_provider.dart` | Auth (isPublic) |
| Password Reset | `lib/features/auth/providers/password_reset_provider.dart` | Auth (isPublic) |
| Student Profile | `lib/features/student/providers/student_profile_provider.dart` | Simple Fetch |
| Mentor Profile | `lib/features/mentor/providers/mentor_profile_provider.dart` | Simple Fetch + Update |
| Edit Profile (Student) | `lib/features/student/providers/edit_profile_provider.dart` | Create/Update |
| Edit Profile (Mentor) | `lib/features/profile/shared/...` (via MentorProfileProvider) | Create/Update |
| Avatar Upload | `lib/features/avatar/providers/avatar_upload_provider.dart` | Presigned Upload |
| Cover Upload | `lib/features/avatar/providers/cover_upload_provider.dart` | Presigned Upload |
| Course Upload | `lib/features/courses/providers/course_upload_provider.dart` | Presigned Upload (multi-file) |
| Course List | `lib/features/courses/providers/course_list_provider.dart` | Simple Fetch |
| Course Detail | `lib/features/courses/providers/course_detail_provider.dart` | Simple Fetch |
| Enrolled Course | `lib/features/courses/providers/enrolled_course_provider.dart` | Simple Fetch |

---

## Key Conventions

1. **Auth vs non-auth**: Auth providers ALWAYS use `getNetworkCaller(isPublic: true)`. Non-auth providers use `getNetworkCaller()`.
2. **URLs**: All endpoint strings in `lib/app/urls.dart`. One constant per endpoint.
3. **Provider names**: Lowercase with underscores (`sign_in_provider.dart`, `course_upload_provider.dart`).
4. **Provider state fields**: `bool _isLoading`, `String? _errorMessage`, `notifyListeners()`.
5. **Error toasts**: Friendly messages like `'Failed to upload image'`, never raw server text.
6. **Debug logging**: Use `AppLogger.i()` / `AppLogger.e()` instead of `print` / `debugPrint`.
7. **Callback pattern**: Upload providers expose `onUploadSuccess` callback. Profile screens wire it in `initState` to refetch.
8. **Consumer vs watch**: Use `Consumer<X>` when only part of the widget tree needs to rebuild. Use `context.watch<X>()` when the whole build method depends on the provider.

---

## Quick Steps Summary

1. Add endpoint URL to `lib/app/urls.dart`
2. Create provider file in the feature's `providers/` folder
3. Write the method using `getNetworkCaller().getRequest/postRequest/putRequest()`
4. Register provider in `lib/app/app.dart`
5. Use `Consumer<YourProvider>` in the UI screen
6. Call provider method in `initState` via `addPostFrameCallback`
7. Handle loading/error/data states in the UI

*Last updated: 2026-06-13*
