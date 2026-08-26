import 'dart:async';
import 'dart:io';
import 'windows_tracker.dart';
import 'android_tracker.dart';

class GameTrackerService {
  String? _targetGame; // The specific game package/exe to track
  int _maxAllowedSeconds = 0;
  int _elapsedSeconds = 0;

  Timer? _ticker;
  final _timeStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get timeStream => _timeStreamController.stream;

  /// Set the single game/app to track
  void setTargetGame(String packageOrExe, int limitInMinutes) {
    _targetGame = packageOrExe.toLowerCase().trim();
    _maxAllowedSeconds = limitInMinutes * 60;
    _elapsedSeconds = 0; // Reset timer for new game
  }

  Future<String?> _getActiveApp() async {
    if (Platform.isWindows) {
      return WindowsTracker.getActiveExecutableName();
    } else if (Platform.isAndroid) {
      return await AndroidTracker.getActivePackageName();
    }
    return null;
  }

  void startMonitoring({required Function(String activeApp) onLimitReached}) {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_targetGame == null || _targetGame!.isEmpty) return;

      final rawApp = await _getActiveApp();
      final activeApp = rawApp?.toLowerCase().trim() ?? '';

      // ONLY increment if the active app equals our targeted game
      if (activeApp == _targetGame) {
        _elapsedSeconds++;

        _timeStreamController.add({
          'targetGame': _targetGame,
          'activeApp': activeApp,
          'isTargetActive': true,
          'elapsedSeconds': _elapsedSeconds,
          'maxSeconds': _maxAllowedSeconds,
        });

        // Trigger limit if reached
        if (_maxAllowedSeconds > 0 && _elapsedSeconds >= _maxAllowedSeconds) {
          if (Platform.isAndroid) {
            await AndroidTracker.killGameToHome();
          }
          onLimitReached(_targetGame!);
        }
      } else {
        // Send status update showing the target game is paused/inactive
        _timeStreamController.add({
          'targetGame': _targetGame,
          'activeApp': activeApp.isEmpty ? 'System / Background' : activeApp,
          'isTargetActive': false,
          'elapsedSeconds': _elapsedSeconds,
          'maxSeconds': _maxAllowedSeconds,
        });
      }
    });
  }

  void stopMonitoring() {
    _ticker?.cancel();
  }

  void dispose() {
    _ticker?.cancel();
    _timeStreamController.close();
  }
}
