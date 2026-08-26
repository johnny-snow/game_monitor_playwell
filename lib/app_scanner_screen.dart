import 'package:flutter/material.dart';
import 'android_tracker.dart';
import 'database_helper.dart';
import 'known_games.dart';

class AppScannerScreen extends StatefulWidget {
  const AppScannerScreen({super.key});

  @override
  State<AppScannerScreen> createState() => _AppScannerScreenState();
}

class _AppScannerScreenState extends State<AppScannerScreen> {
  List<Map<String, String>> _installedApps = [];
  final Map<String, bool> _gameSelection = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _scanAndLoad();
  }

  Future<void> _scanAndLoad() async {
    final apps = await AndroidTracker.getInstalledApps();
    await DatabaseHelper.instance.autoSyncKnownGames(apps, knownGamePackageIds);

    final savedApps = await DatabaseHelper.instance.getAllSavedApps();
    Map<String, bool> savedMap = {};
    for (var app in savedApps) {
      savedMap[app['package_name'] as String] = (app['is_game'] as int) == 1;
    }

    for (var app in apps) {
      String pkg = app['packageName']!;
      bool isGame = savedMap.containsKey(pkg)
          ? savedMap[pkg]!
          : (knownGamePackageIds.contains(pkg) ||
                app['isGameDefault'] == 'true');
      _gameSelection[pkg] = isGame;
    }

    if (mounted) {
      setState(() {
        _installedApps = apps;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSelection() async {
    for (var app in _installedApps) {
      String pkg = app['packageName']!;
      String name = app['appName']!;
      bool isGame = _gameSelection[pkg] ?? false;
      await DatabaseHelper.instance.saveAppClassification(pkg, name, isGame);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("App selections saved successfully!")),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    // Filter apps based on search query
    final filteredDrawerApps = _installedApps.where((app) {
      final name = app['appName']!.toLowerCase();
      final pkg = app['packageName']!.toLowerCase();
      return name.contains(_searchQuery) || pkg.contains(_searchQuery);
    }).toList();

    final trackedApps = _installedApps.where((app) {
      final pkg = app['packageName']!;
      return _gameSelection[pkg] == true &&
          (app['appName']!.toLowerCase().contains(_searchQuery) ||
              pkg.toLowerCase().contains(_searchQuery));
    }).toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Manage Games"),
          bottom: const TabBar(
            tabs: [
              Tab(text: "App Drawer Apps"),
              Tab(text: "Added Games"),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.check, color: Color(0xFF10B981)),
              onPressed: _saveSelection,
              tooltip: "Save",
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Search Bar
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        labelText: "Search apps...",
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Color(0xFF10B981),
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = "");
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        isDense: true,
                      ),
                      onChanged: (val) {
                        setState(() => _searchQuery = val.toLowerCase());
                      },
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // TAB 1: Filtered App Drawer Apps
                        ListView.builder(
                          itemCount: filteredDrawerApps.length,
                          itemBuilder: (context, index) {
                            final app = filteredDrawerApps[index];
                            final pkg = app['packageName']!;
                            final name = app['appName']!;
                            final isGame = _gameSelection[pkg] ?? false;
                            final isAutoDetected = knownGamePackageIds.contains(
                              pkg,
                            );

                            return CheckboxListTile(
                              title: Row(
                                children: [
                                  Expanded(child: Text(name)),
                                  if (isAutoDetected)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFF10B981,
                                        ).withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        "Auto-Detected",
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Color(0xFF10B981),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Text(
                                pkg,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              value: isGame,
                              activeColor: const Color(0xFF10B981),
                              onChanged: (val) {
                                setState(() {
                                  _gameSelection[pkg] = val ?? false;
                                });
                              },
                            );
                          },
                        ),

                        // TAB 2: Filtered Added Games
                        trackedApps.isEmpty
                            ? const Center(
                                child: Text(
                                  "No matching games found.",
                                  style: TextStyle(color: Colors.grey),
                                ),
                              )
                            : ListView.builder(
                                itemCount: trackedApps.length,
                                itemBuilder: (context, index) {
                                  final app = trackedApps[index];
                                  final pkg = app['packageName']!;
                                  final name = app['appName']!;

                                  return ListTile(
                                    leading: const Icon(
                                      Icons.sports_esports,
                                      color: Color(0xFF10B981),
                                    ),
                                    title: Text(name),
                                    subtitle: Text(
                                      pkg,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                        color: Colors.redAccent,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _gameSelection[pkg] = false;
                                        });
                                      },
                                    ),
                                  );
                                },
                              ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
