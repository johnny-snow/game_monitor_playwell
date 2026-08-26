import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('playwell.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE profiles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE
      )
    ''');

    await db.execute('''
      CREATE TABLE apps (
        package_name TEXT PRIMARY KEY,
        app_name TEXT,
        is_game INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE daily_targets (
        day_index INTEGER PRIMARY KEY, -- 1=Mon, 7=Sun
        target_minutes INTEGER DEFAULT 120
      )
    ''');

    await db.execute('''
      CREATE TABLE session_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        profile_name TEXT,
        package_name TEXT,
        date TEXT, -- YYYY-MM-DD
        seconds_played INTEGER
      )
    ''');

    // Default daily targets (120 mins/day)
    for (int i = 1; i <= 7; i++) {
      await db.insert('daily_targets', {'day_index': i, 'target_minutes': 120});
    }
  }

  Future<void> saveProfile(String name) async {
    final db = await instance.database;
    await db.insert('profiles', {
      'name': name,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<String>> getProfiles() async {
    final db = await instance.database;
    final result = await db.query('profiles');
    return result.map((e) => e['name'] as String).toList();
  }

  Future<void> setAppClassification(
    String packageName,
    String appName,
    bool isGame,
  ) async {
    final db = await instance.database;
    await db.insert('apps', {
      'package_name': packageName,
      'app_name': appName,
      'is_game': isGame ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getUnrecognizedApps() async {
    final db = await instance.database;
    return await db.query('apps', where: 'is_game = 0');
  }

  Future<void> setDailyTargets(Map<int, int> targets) async {
    final db = await instance.database;
    targets.forEach((day, minutes) async {
      await db.update(
        'daily_targets',
        {'target_minutes': minutes},
        where: 'day_index = ?',
        whereArgs: [day],
      );
    });
  }

  Future<int> getTargetForDay(int dayIndex) async {
    final db = await instance.database;
    final res = await db.query(
      'daily_targets',
      where: 'day_index = ?',
      whereArgs: [dayIndex],
    );
    return res.isNotEmpty ? (res.first['target_minutes'] as int) : 120;
  }

  Future<void> addPlayTime(
    String profile,
    String packageName,
    int seconds,
  ) async {
    final db = await instance.database;
    final dateStr = DateTime.now().toIso8601String().split('T')[0];

    final existing = await db.query(
      'session_logs',
      where: 'profile_name = ? AND package_name = ? AND date = ?',
      whereArgs: [profile, packageName, dateStr],
    );

    if (existing.isNotEmpty) {
      final current = existing.first['seconds_played'] as int;
      await db.update(
        'session_logs',
        {'seconds_played': current + seconds},
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    } else {
      await db.insert('session_logs', {
        'profile_name': profile,
        'package_name': packageName,
        'date': dateStr,
        'seconds_played': seconds,
      });
    }
  }

  Future<List<Map<String, dynamic>>> getLogsForDate(String date) async {
    final db = await instance.database;
    return await db.query('session_logs', where: 'date = ?', whereArgs: [date]);
  }

  Future<List<Map<String, dynamic>>> getAllLogs() async {
    final db = await instance.database;
    return await db.query('session_logs');
  }

  // Add these helper methods inside your existing DatabaseHelper class:

  Future<void> saveAppClassification(
    String packageName,
    String appName,
    bool isGame,
  ) async {
    final db = await instance.database;
    await db.insert('apps', {
      'package_name': packageName,
      'app_name': appName,
      'is_game': isGame ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getTrackedGames() async {
    final db = await instance.database;
    return await db.query('apps', where: 'is_game = 1');
  }

  Future<List<Map<String, dynamic>>> getAllSavedApps() async {
    final db = await instance.database;
    return await db.query('apps');
  }

  // Inside DatabaseHelper class in lib/database_helper.dart:

  Future<void> autoSyncKnownGames(
    List<Map<String, String>> installedApps,
    Set<String> knownIds,
  ) async {
    final db = await instance.database;

    // Fetch currently saved user preferences so we don't overwrite manual toggles
    final savedApps = await db.query('apps');
    final Set<String> alreadySavedPackages = savedApps
        .map((e) => e['package_name'] as String)
        .toSet();

    for (var app in installedApps) {
      String pkg = app['packageName']!;
      String name = app['appName']!;
      bool isDefaultGame = app['isGameDefault'] == 'true';

      // Auto-mark if:
      // 1. It is in your custom knownGamePackageIds list OR
      // 2. Android system reports it as a game
      bool isGame = knownIds.contains(pkg) || isDefaultGame;

      // Only insert if user hasn't already configured this app manually
      if (!alreadySavedPackages.contains(pkg) && isGame) {
        await db.insert('apps', {
          'package_name': pkg,
          'app_name': name,
          'is_game': 1,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
  }

  Future<int> getTodayTotalPlayTime(String profileName) async {
    final db = await instance.database;
    final todayStr = DateTime.now().toIso8601String().split('T')[0];

    final List<Map<String, dynamic>> result = await db.rawQuery(
      '''
    SELECT SUM(duration_seconds) as total 
    FROM play_logs 
    WHERE profile_name = ? AND date(timestamp) = ?
    ''',
      [profileName, todayStr],
    );

    if (result.isNotEmpty && result.first['total'] != null) {
      return result.first['total'] as int;
    }
    return 0;
  }

  // Inside DatabaseHelper class in lib/database_helper.dart

  Future<List<Map<String, dynamic>>> getTodayAppBreakdown(
    String profileName,
  ) async {
    final db = await instance.database;
    final todayStr = DateTime.now().toIso8601String().split('T')[0];

    return await db.rawQuery(
      '''
    SELECT p.package_name, SUM(p.duration_seconds) as total_seconds, a.app_name
    FROM play_logs p
    LEFT JOIN apps a ON p.package_name = a.package_name
    WHERE p.profile_name = ? AND date(p.timestamp) = ?
    GROUP BY p.package_name
    ORDER BY total_seconds DESC
    ''',
      [profileName, todayStr],
    );
  }

  // Inside DatabaseHelper class in lib/database_helper.dart:

  Future<List<Map<String, dynamic>>> getTodayAppUsageBreakdown(
    String profileName,
  ) async {
    final db = await instance.database;
    final todayStr = DateTime.now().toIso8601String().split('T')[0];

    return await db.rawQuery(
      '''
    SELECT 
      pl.package_name,
      COALESCE(a.app_name, pl.package_name) AS app_name,
      SUM(pl.duration_seconds) AS total_seconds
    FROM play_logs pl
    LEFT JOIN apps a ON pl.package_name = a.package_name
    WHERE pl.profile_name = ? AND date(pl.timestamp) = ?
    GROUP BY pl.package_name
    ORDER BY total_seconds DESC
  ''',
      [profileName, todayStr],
    );
  }
}
