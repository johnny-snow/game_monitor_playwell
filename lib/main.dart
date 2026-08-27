import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'database_helper.dart';
import 'excel_exporter.dart';
import 'android_tracker.dart';
import 'app_scanner_screen.dart';
import 'known_games.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PlayWellApp());
}

class PlayWellApp extends StatelessWidget {
  const PlayWellApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F141C),
        primaryColor: const Color(0xFF10B981),
        cardColor: const Color(0xFF1A212D),
        colorScheme: const ColorScheme.dark(primary: Color(0xFF10B981)),
      ),
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  String _activeProfile = "farhan";

  @override
  void initState() {
    super.initState();
    _checkProfile();
  }

  void _checkProfile() async {
    final profiles = await DatabaseHelper.instance.getProfiles();
    if (profiles.isEmpty) {
      _showProfileDialog();
    } else {
      setState(() => _activeProfile = profiles.first);
    }
  }

  void _showProfileDialog() {
    TextEditingController controller = TextEditingController(text: "farhan");
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A212D),
        title: const Text("Who's playing?"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Enter your profile name:"),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                final profileName = controller.text.trim();
                await DatabaseHelper.instance.saveProfile(profileName);
                if (!context.mounted) return;
                setState(() => _activeProfile = profileName);
                Navigator.pop(context);
              }
            },
            child: const Text("OK", style: TextStyle(color: Color(0xFF10B981))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(
        profileName: _activeProfile,
        onSwitchProfile: _showProfileDialog,
      ),
      LeaderboardScreen(activeProfile: _activeProfile),
      CalendarScreen(profileName: _activeProfile),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_currentIndex]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (idx) => setState(() => _currentIndex = idx),
        selectedItemColor: const Color(0xFF10B981),
        unselectedItemColor: Colors.grey,
        backgroundColor: const Color(0xFF1A212D),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.leaderboard),
            label: 'Leaderboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Calendar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// ================= DASHBOARD SCREEN =================
class DashboardScreen extends StatefulWidget {
  final String profileName;
  final VoidCallback onSwitchProfile;

  const DashboardScreen({
    super.key,
    required this.profileName,
    required this.onSwitchProfile,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  int _todayPlayedSeconds = 0;
  int _targetMinutes = 120;
  Timer? _ticker;
  String _activeAppName = "No game active";
  bool _isGameRunning = false;
  bool _limitReached = false;
  List<Map<String, dynamic>> _appUsageList = [];

  final Map<int, String> _dayNames = {
    1: "Monday",
    2: "Tuesday",
    3: "Wednesday",
    4: "Thursday",
    5: "Friday",
    6: "Saturday",
    7: "Sunday",
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAndStartService();
    _loadTarget();
    _loadStoredData();
    _runInitialAutoSync();
    _startLiveTracking();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadStoredData();
      _startLiveTracking();
    }
  }

  void _checkAndStartService() async {
    bool hasPermission = await AndroidTracker.checkPermission();
    if (!hasPermission) {
      await AndroidTracker.requestPermission();
    } else {
      await AndroidTracker.requestIgnoreBatteryOptimizations();
      await AndroidTracker.startForegroundService();
    }
  }

  void _runInitialAutoSync() async {
    final apps = await AndroidTracker.getInstalledApps();
    await DatabaseHelper.instance.autoSyncKnownGames(apps, knownGamePackageIds);
  }

  void _loadTarget() async {
    final dayIdx = DateTime.now().weekday;
    final target = await DatabaseHelper.instance.getTargetForDay(dayIdx);
    if (mounted) setState(() => _targetMinutes = target);
  }

  Future<void> _loadStoredData() async {
    final totalSecs = await DatabaseHelper.instance.getTodayTotalPlayTime(
      widget.profileName,
    );
    final usageList = await DatabaseHelper.instance.getTodayAppUsageBreakdown(
      widget.profileName,
    );

    if (mounted) {
      setState(() {
        _todayPlayedSeconds = totalSecs;
        _appUsageList = usageList;
        _limitReached =
            _todayPlayedSeconds >= (_targetMinutes * 60) && _targetMinutes > 0;
      });
    }
  }

  void _startLiveTracking() {
    _ticker?.cancel();

    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) return;

      final currentPkg = await AndroidTracker.getActivePackageName();
      if (currentPkg == null) return;

      final trackedGames = await DatabaseHelper.instance.getTrackedGames();

      final matchingGame = trackedGames.firstWhere(
        (e) => e['package_name'] == currentPkg,
        orElse: () => {},
      );

      if (matchingGame.isNotEmpty) {
        final String appName = matchingGame['app_name'] ?? currentPkg;

        // 1. Calculate today's time target in seconds
        final targetSeconds = _targetMinutes * 60;

        // 2. CHECK IF OVER THE DAILY TARGET LIMIT
        if (_todayPlayedSeconds >= targetSeconds && targetSeconds > 0) {
          if (mounted) {
            setState(() {
              _limitReached = true;
              _activeAppName = "$appName (Blocked)";
              _isGameRunning = false;
            });
          }

          // Immediately boot the user out of the blocked game
          await AndroidTracker.killGameToHome(currentPkg);

          if (!mounted) return;

          // Only show the dialog if it isn't already visible on screen
          if (ModalRoute.of(context)?.isCurrent ?? true) {
            _showLimitReachedDialog(appName);
          }
          return; // Stop tracking time for THIS blocked game tick
        }

        // 3. IF UNDER LIMIT, TRACK TIME NORMALLY
        await DatabaseHelper.instance.addPlayTime(
          widget.profileName,
          currentPkg,
          1,
        );

        if (mounted) {
          setState(() {
            _todayPlayedSeconds += 1;
            _activeAppName = appName;
            _isGameRunning = true;
            _limitReached =
                false; // Reset limit flag so other games/sessions function properly
          });
        }
      } else {
        // No tracked game running in foreground
        if (mounted && (_isGameRunning || _limitReached)) {
          setState(() {
            _activeAppName = "No game active";
            _isGameRunning = false;
            _limitReached = false;
          });
        }
      }
    });
  }

  void _showLimitReachedDialog(String gameName) {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.block, color: Colors.red),
            SizedBox(width: 8),
            Text("Time's Up!"),
          ],
        ),
        content: Text(
          "You have reached your daily limit for $gameName. The game has been closed.",
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context),
            child: const Text("OK", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _formatTimer(int totalSeconds) {
    int hours = totalSeconds ~/ 3600;
    int minutes = (totalSeconds % 3600) ~/ 60;
    int seconds = totalSeconds % 60;
    return "${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
  }

  void _showSetTargetDialog() async {
    Map<int, int> tempTargets = {};
    for (int i = 1; i <= 7; i++) {
      tempTargets[i] = await DatabaseHelper.instance.getTargetForDay(i);
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Set Weekly Limits (Mins)"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(7, (index) {
                    int day = index + 1;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_dayNames[day]!),
                        SizedBox(
                          width: 80,
                          child: TextFormField(
                            initialValue: tempTargets[day].toString(),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(isDense: true),
                            onChanged: (val) {
                              tempTargets[day] = int.tryParse(val) ?? 0;
                            },
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await DatabaseHelper.instance.setDailyTargets(tempTargets);
                    if (!context.mounted) return;
                    _loadTarget();
                    _loadStoredData();
                    Navigator.pop(context);
                  },
                  child: const Text("Save"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    double playedMinutes = _todayPlayedSeconds / 60.0;
    double progressPercent = (_targetMinutes > 0)
        ? (playedMinutes / _targetMinutes).clamp(0.0, 1.0)
        : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Player: ${widget.profileName}",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.switch_account),
                onPressed: widget.onSwitchProfile,
              ),
            ],
          ),
          const SizedBox(height: 15),

          // Live Timer Display
          Card(
            color: _limitReached
                ? Colors.red.shade900
                : (_isGameRunning
                      ? const Color(0xFF064E3B)
                      : const Color(0xFF1A212D)),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.timer,
                        color: _isGameRunning
                            ? Colors.greenAccent
                            : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _limitReached
                            ? "Limit Reached! Games Blocked."
                            : (_isGameRunning
                                  ? "Game Active: $_activeAppName"
                                  : "No Game Running"),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _limitReached
                              ? Colors.white
                              : (_isGameRunning
                                    ? Colors.greenAccent
                                    : Colors.grey),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _formatTimer(_todayPlayedSeconds),
                    style: const TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const Text(
                    "Today's Total Game Time Stored",
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 15),

          // Scan Games Card
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.qr_code_scanner,
                color: Color(0xFF10B981),
              ),
              title: const Text("Scan & Classify Games"),
              subtitle: const Text("Detect launcher apps & select games"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AppScannerScreen(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 15),

          // Target Progress Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Daily Target Progress",
                        style: TextStyle(color: Colors.grey),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, color: Color(0xFF10B981)),
                        onPressed: _showSetTargetDialog,
                        tooltip: "Set Limits",
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  LinearProgressIndicator(
                    value: progressPercent,
                    minHeight: 12,
                    backgroundColor: Colors.black26,
                    color: progressPercent >= 1.0
                        ? Colors.red
                        : const Color(0xFF10B981),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "${playedMinutes.toStringAsFixed(1)} min played of $_targetMinutes min target",
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Tracked App Breakdown List
          const Text(
            "Tracked Apps Usage (Today)",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),

          _appUsageList.isEmpty
              ? const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(
                      child: Text(
                        "No game activity logged for today.",
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _appUsageList.length,
                  itemBuilder: (context, index) {
                    final item = _appUsageList[index];
                    final appName = item['app_name'] as String;
                    final totalSecs = item['total_seconds'] as int;

                    return Card(
                      child: ListTile(
                        leading: const Icon(
                          Icons.sports_esports,
                          color: Color(0xFF10B981),
                        ),
                        title: Text(
                          appName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          item['package_name'] as String,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                        trailing: Text(
                          _formatTimer(totalSecs),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                            fontSize: 14,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }
}

// ================= LEADERBOARD SCREEN =================
class LeaderboardScreen extends StatelessWidget {
  final String activeProfile;

  const LeaderboardScreen({super.key, required this.activeProfile});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "This week's leaderboard",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 15),
          Table(
            border: TableBorder.all(color: Colors.white10),
            children: [
              const TableRow(
                decoration: BoxDecoration(color: Colors.black26),
                children: [
                  Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text(
                      "Rank",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text(
                      "Player",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text(
                      "Weekly Points",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              TableRow(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text("#1"),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(activeProfile),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text("100"),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ================= CALENDAR SCREEN =================
class CalendarScreen extends StatefulWidget {
  final String profileName;

  const CalendarScreen({super.key, required this.profileName});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _selectedDay = DateTime.now();
  List<Map<String, dynamic>> _dayLogs = [];

  @override
  void initState() {
    super.initState();
    _loadLogsForDay(_selectedDay);
  }

  void _loadLogsForDay(DateTime day) async {
    final dateStr = day.toIso8601String().split('T')[0];
    final logs = await DatabaseHelper.instance.getLogsForDate(dateStr);
    setState(() => _dayLogs = logs);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TableCalendar(
          firstDay: DateTime.utc(2025, 1, 1),
          lastDay: DateTime.utc(2030, 12, 31),
          focusedDay: _selectedDay,
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          onDaySelected: (selectedDay, focusedDay) {
            setState(() => _selectedDay = selectedDay);
            _loadLogsForDay(selectedDay);
          },
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _dayLogs.isEmpty
              ? const Center(child: Text("No gaming logs for this date."))
              : ListView.builder(
                  itemCount: _dayLogs.length,
                  itemBuilder: (context, idx) {
                    final log = _dayLogs[idx];
                    return ListTile(
                      title: Text(log['package_name']),
                      trailing: Text(
                        "${(log['seconds_played'] as int) ~/ 60} mins",
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ================= SETTINGS SCREEN =================
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.file_download, color: Color(0xFF10B981)),
            title: const Text("Export Data to Excel"),
            onTap: () async {
              final path = await ExcelExporter.exportGamingData();
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text("Exported to $path")));
            },
          ),
          ListTile(
            leading: const Icon(Icons.security, color: Color(0xFF10B981)),
            title: const Text("Grant Usage Permission"),
            subtitle: const Text("Required for tracking active game time"),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () async {
              await AndroidTracker.requestPermission();
            },
          ),
          ListTile(
            leading: const Icon(Icons.battery_saver, color: Color(0xFF10B981)),
            title: const Text("Disable Battery Optimization"),
            subtitle: const Text(
              "Prevents Android from freezing the timer in the background",
            ),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () async {
              await AndroidTracker.requestIgnoreBatteryOptimizations();
            },
          ),
        ],
      ),
    );
  }
}
