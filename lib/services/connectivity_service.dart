// lib/services/connectivity_service.dart
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityService extends ChangeNotifier {
  bool _isOnline = true;
  bool get isOnline => _isOnline;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  final Connectivity _connectivity = Connectivity();

  ConnectivityService() {
    _initialize();
  }

  Future<void> _initialize() async {
    // ✅ Check initial connection state
    await _checkInitialConnection();

    // ✅ Listen for connectivity changes with error handling
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
          (List<ConnectivityResult> results) {
        _updateConnectionStatus(results);
      },
      onError: (error) {
        debugPrint('❌ Connectivity stream error: $error');
        // ✅ Assume offline on error to be safe
        _isOnline = false;
        notifyListeners();
      },
      cancelOnError: false, // ✅ Keep listening even after errors
    );
  }

  Future<void> _checkInitialConnection() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _updateConnectionStatus(results);
    } catch (e) {
      debugPrint('⚠️ Failed to check initial connectivity: $e');
      _isOnline = false;
      notifyListeners();
    }
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) {
    final wasOnline = _isOnline;

    // ✅ Handle empty list (should be treated as offline)
    _isOnline = results.isNotEmpty && !results.contains(ConnectivityResult.none);

    // ✅ Only notify if status actually changed
    if (wasOnline != _isOnline) {
      notifyListeners();
      debugPrint(_isOnline
          ? '🌐 Connection restored: $results'
          : '📴 Connection lost: $results');
    }
  }

  /// ✅ Manual refresh method (useful for pull-to-refresh)
  Future<void> refresh() async {
    await _checkInitialConnection();
  }

  /// ✅ Get detailed connection type
  Future<List<ConnectivityResult>> getConnectionType() async {
    try {
      return await _connectivity.checkConnectivity();
    } catch (e) {
      debugPrint('⚠️ Failed to get connection type: $e');
      return [ConnectivityResult.none];
    }
  }

  /// ✅ Check if connected via WiFi
  Future<bool> isWiFi() async {
    final results = await getConnectionType();
    return results.contains(ConnectivityResult.wifi);
  }

  /// ✅ Check if connected via mobile data
  Future<bool> isMobile() async {
    final results = await getConnectionType();
    return results.contains(ConnectivityResult.mobile);
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    super.dispose();
    debugPrint('🛑 ConnectivityService disposed');
  }
}