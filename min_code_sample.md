# ABSOLUTE MINIMUM TAWK CODE

If you just want to add Tawk to your existing app in 2 minutes:

---

## FILE 1: `lib/tawk_service.dart`

```dart
import 'package:flutter_tawk_to_plus/flutter_tawk_to_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TawkService {
  static final TawkService _instance = TawkService._internal();
  factory TawkService() => _instance;
  TawkService._internal();

  final storage = const FlutterSecureStorage();

  Future<void> init(String userId, String name, String email) async {
    await flutter_tawk_to_plus.TawkService().initialize(
      directChatLink: 'https://tawk.to/chat/YOUR_ID/YOUR_WIDGET',
      visitor: TawkVisitor(
        name: name,
        email: email,
        otherAttributes: {'user_id': userId},
      ),
    );
    await storage.write(key: 'user_id', value: userId);
  }

  Future<void> restore() async {
    final id = await storage.read(key: 'user_id');
    if (id != null) {
      await flutter_tawk_to_plus.TawkService().initialize(
        directChatLink: 'https://tawk.to/chat/YOUR_ID/YOUR_WIDGET',
        visitor: TawkVisitor(
          name: 'User',
          email: 'user@example.com',
          otherAttributes: {'user_id': id},
        ),
      );
    }
  }

  Widget get chat => flutter_tawk_to_plus.TawkService().getWebViewWidget();

  Future<void> logout() async => await storage.deleteAll();
}
```

---

## FILE 2: Update `main.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_tawk_to_plus/flutter_tawk_to_plus.dart';
import 'tawk_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  TawkNotificationService().initialize();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    TawkService().restore();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('My App')),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    // Show login button or chat based on state
    return Center(
      child: ElevatedButton(
        onPressed: () {
          // Login (or show chat if already logged in)
          TawkService().init('user_123', 'John Doe', 'john@email.com');
          setState(() {});
        },
        child: const Text('Login & Open Chat'),
      ),
    );
  }
}
```

---

## FILE 3: `pubspec.yaml`

Add these:
```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_tawk_to_plus: ^1.1.1
  flutter_secure_storage: ^9.0.0
```

---

## FILE 4: Android Permissions

Edit `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

---

## THAT'S IT!

### 3 Steps to Use:

1. Replace `'https://tawk.to/chat/YOUR_ID/YOUR_WIDGET'` with your actual link
2. Run `flutter pub get`
3. Run `flutter run`

---

## Show Chat Instead of Button

Replace `_buildBody()` with:

```dart
Widget _buildBody() {
  return TawkService().chat;  // Shows chat directly
}
```

---

## With Login/Logout

```dart
class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkLogin();
  }

  Future<void> _checkLogin() async {
    // Check if user was previously logged in
    _loggedIn = await const FlutterSecureStorage().read(key: 'user_id') != null;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('My App'),
          actions: _loggedIn
              ? [
                  IconButton(
                    icon: const Icon(Icons.logout),
                    onPressed: () async {
                      await TawkService().logout();
                      setState(() => _loggedIn = false);
                    },
                  ),
                ]
              : null,
        ),
        body: _loggedIn
            ? TawkService().chat
            : Center(
                child: ElevatedButton(
                  onPressed: () async {
                    await TawkService().init(
                      'user_123',
                      'John Doe',
                      'john@example.com',
                    );
                    setState(() => _loggedIn = true);
                  },
                  child: const Text('Login'),
                ),
              ),
      ),
    );
  }
}
```

---

## Connect to Real Backend

```dart
Future<void> _loginWithBackend() async {
  // Call your backend API
  final response = await http.post(
    Uri.parse('https://api.yourserver.com/login'),
    body: {'email': email, 'password': password},
  );

  final user = User.fromJson(jsonDecode(response.body));

  // Initialize Tawk
  await TawkService().init(user.id, user.name, user.email);
}

class User {
  final String id;
  final String name;
  final String email;
  User({required this.id, required this.name, required this.email});
  factory User.fromJson(Map json) =>
      User(id: json['id'], name: json['name'], email: json['email']);
}
```

---

**Done! Your app has Tawk chat.** ✅
