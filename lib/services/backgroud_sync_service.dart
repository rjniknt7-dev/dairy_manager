// lib/services/background_sync_service.dart
// ✅ OPTIMIZED: Less frequent background sync for backup use case
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_sync_service.dart';

class BackgroundSyncService {
  static final BackgroundSyncService _instance = BackgroundSyncService._internal();
  factory BackgroundSyncService() => _instance;
  BackgroundSyncService._internal();

  final FirebaseSyncService _syncService = FirebaseSyncService();
  Timer? _syncTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription; // ✅ Fixed type
  StreamSubscription<User?>? _authSubscription;

  bool _isRunning = false;
  DateTime? _lastSyncAttempt;
  bool _isSyncing = false; // ✅ Prevent overlapping syncs

  /// ✅ IMPROVED: Configurable sync interval (default: 6 hours for backup use case)
  void startBackgroundSync({Duration syncInterval = const Duration(hours: 6)}) {
    if (_isRunning) {
      debugPrint('⏭️ Background sync already running');
      return;
    }

    _isRunning = true;

    // ✅ Periodic sync (6 hours instead of 10 minutes for battery efficiency)
    _syncTimer = Timer.periodic(syncInterval, (_) async {
      await _attemptSync('periodic');
    });

    // ✅ Sync when connectivity returns (with debounce)
    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen(
          (List<ConnectivityResult> results) async {
        // ✅ Fixed: Check if any connection is available
        final hasConnection = !results.contains(ConnectivityResult.none);

        if (hasConnection) {
          // ✅ Debounce: Don't sync if we synced in last 5 minutes
          if (_lastSyncAttempt != null &&
              DateTime.now().difference(_lastSyncAttempt!).inMinutes < 5) {
            debugPrint('⏭️ Skipping sync - recently synced');
            return;
          }

          debugPrint('🌐 Connection restored');
          await Future.delayed(const Duration(seconds: 3)); // Wait for stable connection
          await _attemptSync('connectivity_restored');
        }
      },
      onError: (error) {
        debugPrint('⚠️ Connectivity stream error: $error');
      },
      cancelOnError: false, // ✅ Keep listening even after errors
    );

    // ✅ Sync when user logs in
    _authSubscription = FirebaseAuth.instance
        .authStateChanges()
        .listen(
          (User? user) async {
        if (user != null) {
          debugPrint('👤 User logged in - triggering sync');
          await Future.delayed(const Duration(seconds: 2));
          await _attemptSync('user_login');
        }
      },
      onError: (error) {
        debugPrint('⚠️ Auth stream error: $error');
      },
      cancelOnError: false,
    );

    debugPrint('✅ Background sync service started (interval: ${syncInterval.inHours}h)');
  }

  Future<void> _attemptSync(String trigger) async {
    // ✅ Prevent overlapping syncs
    if (_isSyncing) {
      debugPrint('⏭️ Sync already in progress, skipping $trigger');
      return;
    }

    if (!await _syncService.canSync) {
      debugPrint('📴 Cannot sync ($trigger) - offline or not authenticated');
      return;
    }

    _isSyncing = true;
    _lastSyncAttempt = DateTime.now();
    debugPrint('🔄 Auto-sync triggered: $trigger');

    try {
      final result = await _syncService.syncAllData();
      if (result.success) {
        debugPrint('✅ Auto-sync completed ($trigger)');
      } else {
        debugPrint('⚠️ Auto-sync failed ($trigger): ${result.message}');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Auto-sync error ($trigger): $e');
      debugPrint('Stack trace: $stackTrace');
    } finally {
      _isSyncing = false; // ✅ Always release lock
    }
  }

  /// Manual sync trigger
  Future<SyncResult> syncNow() async {
    if (_isSyncing) {
      return SyncResult(
        success: false,
        message: 'Sync already in progress',
      );
    }

    if (!await _syncService.canSync) {
      return SyncResult(
        success: false,
        message: 'No internet connection or not logged in',
      );
    }

    debugPrint('🔄 Manual sync triggered');
    _lastSyncAttempt = DateTime.now();
    _isSyncing = true;

    try {
      return await _syncService.syncAllData();
    } finally {
      _isSyncing = false;
    }
  }

  /// Force upload all local data to cloud
  Future<SyncResult> forceUploadAll() async {
    if (_isSyncing) {
      return SyncResult(
        success: false,
        message: 'Sync already in progress',
      );
    }

    if (!await _syncService.canSync) {
      return SyncResult(
        success: false,
        message: 'No internet connection or not logged in',
      );
    }

    debugPrint('⬆️ Force upload triggered');
    _isSyncing = true;

    try {
      return await _syncService.forceUploadAllData();
    } finally {
      _isSyncing = false;
    }
  }

  /// Get current sync status
  Future<Map<String, dynamic>> getSyncStatus() async {
    final status = await _syncService.getSyncStatus();
    status['lastSyncAttempt'] = _lastSyncAttempt?.toIso8601String();
    status['isSyncing'] = _isSyncing;
    status['backgroundSyncEnabled'] = _isRunning;
    return status;
  }

  /// ✅ Clean up old deleted records (call weekly)
  Future<void> cleanupOldRecords({int daysOld = 90}) async {
    await _syncService.cleanupDeletedRecords(daysOld: daysOld);
  }

  /// ✅ Properly dispose resources
  void dispose() {
    _syncTimer?.cancel();
    _connectivitySubscription?.cancel();
    _authSubscription?.cancel();
    _syncTimer = null;
    _connectivitySubscription = null;
    _authSubscription = null;
    _isRunning = false;
    _isSyncing = false;
    debugPrint('🛑 Background sync service stopped');
  }

  /// ✅ Check if service is running
  bool get isRunning => _isRunning;

  /// ✅ Check if currently syncing
  bool get isSyncing => _isSyncing;

  /// ✅ Get last sync time
  DateTime? get lastSyncAttempt => _lastSyncAttempt;
}