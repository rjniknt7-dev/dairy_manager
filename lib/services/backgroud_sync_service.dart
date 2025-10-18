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
  StreamSubscription? _connectivitySubscription;
  StreamSubscription? _authSubscription;

  bool _isRunning = false;
  DateTime? _lastSyncAttempt;

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
        .listen((result) async {
      if (result != ConnectivityResult.none) {
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
    });

    // ✅ Sync when user logs in
    _authSubscription = FirebaseAuth.instance
        .authStateChanges()
        .listen((user) async {
      if (user != null) {
        debugPrint('👤 User logged in - triggering sync');
        await Future.delayed(const Duration(seconds: 2));
        await _attemptSync('user_login');
      }
    });

    debugPrint('✅ Background sync service started (interval: ${syncInterval.inHours}h)');
  }

  Future<void> _attemptSync(String trigger) async {
    if (!await _syncService.canSync) {
      debugPrint('📴 Cannot sync ($trigger) - offline or not authenticated');
      return;
    }

    _lastSyncAttempt = DateTime.now();
    debugPrint('🔄 Auto-sync triggered: $trigger');

    try {
      final result = await _syncService.syncAllData();
      if (result.success) {
        debugPrint('✅ Auto-sync completed ($trigger)');
      } else {
        debugPrint('⚠️ Auto-sync failed ($trigger): ${result.message}');
      }
    } catch (e) {
      debugPrint('❌ Auto-sync error ($trigger): $e');
    }
  }

  /// Manual sync trigger
  Future<SyncResult> syncNow() async {
    if (!await _syncService.canSync) {
      return SyncResult(
        success: false,
        message: 'No internet connection or not logged in',
      );
    }

    debugPrint('🔄 Manual sync triggered');
    _lastSyncAttempt = DateTime.now();
    return await _syncService.syncAllData();
  }

  /// Force upload all local data to cloud
  Future<SyncResult> forceUploadAll() async {
    if (!await _syncService.canSync) {
      return SyncResult(
        success: false,
        message: 'No internet connection or not logged in',
      );
    }

    debugPrint('⬆️ Force upload triggered');
    return await _syncService.forceUploadAllData();
  }

  /// Get current sync status
  Future<Map<String, dynamic>> getSyncStatus() async {
    final status = await _syncService.getSyncStatus();
    status['lastSyncAttempt'] = _lastSyncAttempt?.toIso8601String();
    return status;
  }

  void dispose() {
    _syncTimer?.cancel();
    _connectivitySubscription?.cancel();
    _authSubscription?.cancel();
    _isRunning = false;
    debugPrint('🛑 Background sync service stopped');
  }
}