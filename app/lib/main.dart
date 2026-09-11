import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_jailbreak_detection/flutter_jailbreak_detection.dart';
import 'package:flutter_windowmanager/flutter_windowmanager.dart';

import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  bool isCompromised = true;
  try {
    isCompromised = await FlutterJailbreakDetection.jailbroken;
  } catch (_) {
    // Fail closed — if detection is unavailable, block to protect patient data
  }

  if (isCompromised) {
    runApp(const _DeviceBlockedApp());
    return;
  }

  if (Platform.isAndroid) {
    // Prevents screenshots, screen recording, and task-switcher thumbnails
    await FlutterWindowManager.addFlags(FlutterWindowManager.FLAG_SECURE);
  }

  runApp(const ParkinSenseApp());
}

/// Shown when the app detects a rooted/jailbroken device.
class _DeviceBlockedApp extends StatelessWidget {
  const _DeviceBlockedApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: Scaffold(
        backgroundColor: Colors.grey.shade100,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.security, size: 64, color: Colors.red.shade700),
                const SizedBox(height: 24),
                Text(
                  'Device Not Supported',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'ParkinSense cannot run on a rooted or jailbroken device. '
                  'This restriction protects sensitive patient health data.',
                  style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
