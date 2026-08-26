import 'package:flutter/services.dart';

class AndroidTracker {
  static const MethodChannel _channel = MethodChannel('com.tracker/android');

  /// Checks if Usage Access permission is turned on
  static Future<bool> hasUsagePermission() async {
    final bool granted = await _channel.invokeMethod('checkPermission');
    return granted;
  }

  /// Opens Android Settings so the user can grant permission
  static Future<void> openPermissionSettings() async {
    await _channel.invokeMethod('openPermissionSettings');
  }

  /// Returns active app package name (e.g. "com.mojang.minecraftpe")
  static Future<String?> getActivePackageName() async {
    final String? pkg = await _channel.invokeMethod('getForegroundPackage');
    return pkg;
  }

  /// Minimizes/blocks game by redirecting user to home screen
  static Future<void> killGameToHome() async {
    await _channel.invokeMethod('killGameToHome');
  }
}
