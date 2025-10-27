// lib/services/app_initializer.dart
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'backgroud_sync_service.dart';
import 'firebase_sync_service.dart';
import 'database_helper.dart';

/// ✅ Centralized app initialization service
class AppInitializer {
  static final AppInitializer _instance = AppInitializer._internal();
  factory AppInitializer() => _instance;
  AppInitializer._internal();

  final BackgroundSyncService _backgroundSync = BackgroundSyncService();
  final FirebaseSyncService _syncService = FirebaseSyncService();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// ✅ Initialize app (call this in main.dart)
  Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('⏭️ App already initialized');
      return;
    }

    debugPrint('🚀 Initializing app...');

    try {
      // 1. Initialize database
      await _initializeDatabase();

      // 2. Check if user is authenticated
      final isAuthenticated = FirebaseAuth.instance.currentUser != null;

      if (isAuthenticated) {
        // 3. Perform initial sync
        await _performInitialSync();

        // 4. Start background sync (6 hours interval)
        _backgroundSync.startBackgroundSync(
          syncInterval: const Duration(hours: 6),
        );

        // 5. Schedule cleanup (weekly)
        await _schedulePeriodicCleanup();
      } else {
        debugPrint('👤 User not authenticated - skipping sync');
      }

      _isInitialized = true;
      debugPrint('✅ App initialization complete');
    } catch (e, stackTrace) {
      debugPrint('❌ App initialization failed: $e');
      debugPrint('Stack trace: $stackTrace');
      _isInitialized = false;
      rethrow;
    }
  }

  /// ✅ Initialize database
  Future<void> _initializeDatabase() async {
    try {
      debugPrint('📂 Initializing database...');
      await _dbHelper.database; // This triggers database creation
      debugPrint('✅ Database initialized');
    } catch (e) {
      debugPrint('❌ Database initialization failed: $e');
      rethrow;
    }
  }

  /// ✅ Perform initial sync on app startup
  Future<void> _performInitialSync() async {
    try {
      debugPrint('🔄 Performing initial sync...');

      final prefs = await SharedPreferences.getInstance();
      final lastSync = prefs.getString('last_full_sync');
      final shouldForceSync = lastSync == null;

      if (shouldForceSync) {
        debugPrint('📥 First time sync - restoring from cloud...');
        final result = await _syncService.restoreFromFirebaseIfEmpty();
        debugPrint('✅ Initial restore: ${result.message}');
      } else {
        debugPrint('🔄 Regular sync...');
        final result = await _syncService.syncAllData();
        if (result.success) {
          debugPrint('✅ Initial sync successful');
        } else {
          debugPrint('⚠️ Initial sync failed: ${result.message}');
        }
      }

      // Update last sync timestamp
      await prefs.setString('last_full_sync', DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('⚠️ Initial sync failed: $e (continuing offline)');
    }
  }

  /// ✅ Schedule periodic cleanup of old deleted records
  Future<void> _schedulePeriodicCleanup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCleanup = prefs.getString('last_cleanup');

      // Only cleanup if last cleanup was more than 7 days ago
      if (lastCleanup != null) {
        final lastCleanupDate = DateTime.parse(lastCleanup);
        if (DateTime.now().difference(lastCleanupDate).inDays < 7) {
          debugPrint('⏭️ Skipping cleanup - last cleanup was ${DateTime.now().difference(lastCleanupDate).inDays} days ago');
          return;
        }
      }

      debugPrint('🧹 Performing periodic cleanup...');
      await _backgroundSync.cleanupOldRecords(daysOld: 90);
      await prefs.setString('last_cleanup', DateTime.now().toIso8601String());
      debugPrint('✅ Cleanup complete');
    } catch (e) {
      debugPrint('⚠️ Cleanup failed: $e');
    }
  }

  /// ✅ Manual sync trigger
  Future<SyncResult> manualSync() async {
    return await _backgroundSync.syncNow();
  }

  /// ✅ Force upload all local data
  Future<SyncResult> forceUploadAll() async {
    return await _backgroundSync.forceUploadAll();
  }

  /// ✅ Get sync status
  Future<Map<String, dynamic>> getSyncStatus() async {
    return await _backgroundSync.getSyncStatus();
  }

  /// ✅ Reset app (useful for logout or troubleshooting)
  Future<void> resetApp() async {
    try {
      debugPrint('🔄 Resetting app...');

      // Stop background sync
      _backgroundSync.dispose();

      // Clear preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // Reset sync status
      await _syncService.resetSyncStatus();

      _isInitialized = false;
      debugPrint('✅ App reset complete');
    } catch (e) {
      debugPrint('❌ App reset failed: $e');
      rethrow;
    }
  }

  /// ✅ Cleanup on app close
  void dispose() {
    _backgroundSync.dispose();
    _isInitialized = false;
    debugPrint('🛑 App initializer disposed');
  }

  /// ✅ Get initialization status with details
  Map<String, dynamic> getStatus() {
    return {
      'initialized': _isInitialized,
      'syncRunning': _backgroundSync.isSyncing,
      'backgroundSyncEnabled': _backgroundSync.isRunning,
      'lastSync': _backgroundSync.lastSyncAttempt?.toIso8601String(),
      'authenticated': FirebaseAuth.instance.currentUser != null,
    };
  }
}