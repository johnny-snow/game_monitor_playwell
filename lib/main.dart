import 'dart:io';
import 'package:flutter/material.dart';
import 'game_tracker_service.dart';
import 'android_tracker.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final GameTrackerService _tracker = GameTrackerService();
  final TextEditingController _appInputController = TextEditingController();

  bool _hasAndroidPermission = true;
  bool _isMonitoring = false;
  String _statusMessage = "Enter package name and tap Start";

  @override
  void initState() {
    super.initState();
    _checkAndroidPermissions();

    if (Platform.isWindows) {
      _appInputController.text = "notepad.exe";
    } else if (Platform.isAndroid) {
      _appInputController.text = "com.android.chrome"; // Put target app here
    }
  }

  Future<void> _checkAndroidPermissions() async {
    if (Platform.isAndroid) {
      final granted = await AndroidTracker.hasUsagePermission();
      setState(() => _hasAndroidPermission = granted);
    }
  }

  void _startTracking() {
    final targetApp = _appInputController.text.trim();
    if (targetApp.isEmpty) return;

    // Set target app with 1 minute limit for testing
    _tracker.setTargetGame(targetApp, 1);

    setState(() {
      _isMonitoring = true;
      _statusMessage = "Tracking active for: $targetApp";
    });

    _tracker.startMonitoring(
      onLimitReached: (activeApp) {
        setState(() {
          _statusMessage = "TIME EXPIRED FOR $activeApp!";
        });
      },
    );
  }

  String _formatDuration(int totalSeconds) {
    final duration = Duration(seconds: totalSeconds);
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  @override
  void dispose() {
    _tracker.dispose();
    _appInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text("Game Specific Tracker")),
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextField(
                controller: _appInputController,
                decoration: const InputDecoration(
                  labelText: 'Target App Package Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),

              StreamBuilder<Map<String, dynamic>>(
                stream: _tracker.timeStream,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Text("00:00", style: TextStyle(fontSize: 48));
                  }

                  final data = snapshot.data!;
                  final isTargetActive = data['isTargetActive'] as bool;
                  final elapsed = data['elapsedSeconds'] as int;
                  final activeApp = data['activeApp'] as String;

                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isTargetActive
                          ? Colors.green.shade50
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isTargetActive ? Colors.green : Colors.red,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          isTargetActive
                              ? "GAME IS ACTIVE (Ticking)"
                              : "GAME IN BACKGROUND (Paused)",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isTargetActive
                                ? Colors.green.shade800
                                : Colors.red.shade800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          "Foreground: $activeApp",
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 15),
                        Text(
                          _formatDuration(elapsed),
                          style: const TextStyle(
                            fontSize: 52,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),
              Text(_statusMessage),
              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: _startTracking,
                child: const Text('Start Tracking Target Game'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
