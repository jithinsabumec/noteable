import 'dart:io' as io;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rive/rive.dart' as rive;

import 'firebase_options.dart';
import 'screens/auth_wrapper.dart';
import 'screens/main_screen.dart';
import 'services/auth_service.dart';
import 'services/purchase_service.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize RevenueCat with user ID if logged in (links purchases across devices)
  final appUserId = AuthService().getUserId();
  await PurchaseService().initialize(appUserId: appUserId);

  final riveReady = await rive.RiveNative.init();
  if (!riveReady) {
    debugPrint('Failed to initialize RiveNative runtime');
  }

  await StorageService().initialize();
  await _requestStoragePermissions();

  runApp(const MyApp());
}

Future<void> _requestStoragePermissions() async {
  try {
    if (io.Platform.isAndroid || io.Platform.isIOS) {
      final storageStatus = await Permission.storage.request();
      if (!storageStatus.isGranted) {
        debugPrint('Storage permission not granted: $storageStatus');
      }
    }
  } catch (error) {
    debugPrint('Error requesting storage permissions: $error');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Noteable',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        fontFamily: 'Geist',
      ),
      home: const AppHome(),
    );
  }
}

class AppHome extends StatelessWidget {
  const AppHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuthWrapper(
        child: (isGuestMode, onExitGuestMode) => MainScreen(
          isGuestMode: isGuestMode,
          onExitGuestMode: onExitGuestMode,
        ),
      ),
    );
  }
}
