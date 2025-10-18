// lib/services/app_initializer.dart
import 'dart:async';
import 'package:flutter/foundation.dart';

/// ✅ Inline sync result class
class SyncResult {
  final bool success;
  final String message;
  SyncResult({required this.success, required this.message});
}

/// ✅ Inline "sync service" logic (replace with your actual DB/API logic)
class _InlineSyncService {
  Future<bool> get canSync async {
    // TODO: Replace with real connectivity + auth check
    return true;
  }

  Future<SyncResult> syncAllData() async {
    // TODO: Replace with your real sync logic
    await Future.delayed(const Duration(seconds: 2));
    return SyncResult(success: true, message: 'Data synced successfully');
  }

  Future<SyncResult> forceUploadAllData() async {
    // TODO: Replace with your real force upload logic
    await Future.delayed(const Duration(seconds: 2));
    return SyncResult(success: true, message: 'All data force uploaded');
  }

  Future<Map<String, dynamic>> getSyncStatus() async {
    return {'status': 'idle'};
  }
}

/// ✅ AppInitializer with background sync
class AppInitializer {
  static final AppInitializer _instance = AppInitializer._internal();
  factory AppInitializer() => _instance;
  AppInitializer._internal();

  final _syncService = _InlineSyncService();
  Timer? _syncTimer;
  bool _isSyncRunning = false;
  DateTime? _lastSyncAttempt;

  /// Start background sync (default every 6 hours)
  void startBackgroundSync({Duration interval = const Duration(hours: 6)}) {
    if (_isSyncRunning) {
      debugPrint('⏭️ Background sync already running');
      return;
    }
    _isSyncRunning = true;

    _syncTimer = Timer.periodic(interval, (_) async {
      await _attemptSync('periodic');
    });

    debugPrint('✅ Background sync started (interval: ${interval.inHours}h)');
  }

  /// Attempt sync (internal)
  Future<void> _attemptSync(String trigger) async {
    if (!await _syncService.canSync) {
      debugPrint('📴 Cannot sync ($trigger) - offline or not authenticated');
      return;
    }

    // Debounce: skip if synced in last 5 minutes
    if (_lastSyncAttempt != null &&
        DateTime.now().difference(_lastSyncAttempt!).inMinutes < 5) {
      debugPrint('⏭️ Skipping sync ($trigger) - recently synced');
      return;
    }

    _lastSyncAttempt = DateTime.now();
    debugPrint('🔄 Sync triggered: $trigger');

    try {
      final result = await _syncService.syncAllData();
      debugPrint('✅ Sync result ($trigger): ${result.message}');
    } catch (e) {
      debugPrint('❌ Sync error ($trigger): $e');
    }
  }

  /// Manual sync trigger
  Future<SyncResult> manualSync() async {
    if (!await _syncService.canSync) {
      return SyncResult(
          success: false,
          message: 'No internet connection or not logged in');
    }

    debugPrint('🔄 Manual sync triggered');
    _lastSyncAttempt = DateTime.now();
    return await _syncService.syncAllData();
  }

  /// Force upload all local data
  Future<SyncResult> forceUploadAll() async {
    if (!await _syncService.canSync) {
      return SyncResult(
          success: false,
          message: 'No internet connection or not logged in');
    }

    debugPrint('⬆️ Force upload triggered');
    return await _syncService.forceUploadAllData();
  }

  /// Get last sync info / status
  Future<Map<String, dynamic>> getSyncStatus() async {
    final status = await _syncService.getSyncStatus();
    status['lastSyncAttempt'] = _lastSyncAttempt?.toIso8601String();
    return status;
  }

  /// Stop background sync
  void dispose() {
    _syncTimer?.cancel();
    _isSyncRunning = false;
    debugPrint('🛑 Background sync stopped');
  }
}
