import 'package:edtech/app/app.dart';
import 'package:edtech/app/platform_init.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initPlatformServices();
  final prefs = await SharedPreferences.getInstance();
  runApp(App(prefs: prefs));
}
