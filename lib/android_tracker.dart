import 'package:flutter/services.dart';

class AndroidTracker {
  static const MethodChannel _channel = MethodChannel('com.playwell/tracker');

  static Future<bool> checkPermission() async {
    try {
      final bool hasPermission = await _channel.invokeMethod('checkPermission');
      return hasPermission;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestPermission() async {
    try {
      await _channel.invokeMethod('requestPermission');
    } catch (_) {}
  }

  static Future<void> requestIgnoreBatteryOptimizations() async {
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (_) {}
  }

  static Future<void> startForegroundService() async {
    try {
      await _channel.invokeMethod('startForegroundService');
    } catch (_) {}
  }

  static Future<void> stopForegroundService() async {
    try {
      await _channel.invokeMethod('stopForegroundService');
    } catch (_) {}
  }

  static Future<List<Map<String, String>>> getInstalledApps() async {
    try {
      final List<dynamic> apps = await _channel.invokeMethod(
        'getInstalledApps',
      );
      return apps.map((e) => Map<String, String>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<String?> getActivePackageName() async {
    try {
      final String? pkg = await _channel.invokeMethod('getForegroundApp');
      return pkg;
    } catch (_) {
      return null;
    }
  }

  static Future<void> killGameToHome() async {
    try {
      await _channel.invokeMethod('killToHome');
    } catch (_) {}
  }
}
