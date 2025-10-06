import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../services/firebase_sync_service.dart';
import '../services/connectivity_service.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _syncService = FirebaseSyncService();
  bool _isSyncing = false;
  String _syncStatus = '';

  List<_FeatureTile> features = [
    const _FeatureTile(title: 'Purchase Orders', icon: Icons.shopping_cart, route: '/demand', colors: [Colors.green, Colors.greenAccent]),
    const _FeatureTile(title: 'Billing Section', icon: Icons.receipt_long, route: '/billing', colors: [Colors.purple, Colors.deepPurpleAccent]),
    const _FeatureTile(title: 'Billing History', icon: Icons.history, route: '/history', colors: [Colors.teal, Colors.tealAccent]),
    const _FeatureTile(title: 'Ledger Book', icon: Icons.book, route: '/ledgerBook', colors: [Colors.red, Colors.redAccent]),
    const _FeatureTile(title: 'Client Management', icon: Icons.person, route: '/clients', colors: [Colors.blue, Colors.blueAccent]),
    const _FeatureTile(title: 'Product Management', icon: Icons.shopping_cart, route: '/products', colors: [Colors.orange, Colors.deepOrangeAccent]),
    const _FeatureTile(title: 'Stock / Inventory', icon: Icons.inventory_2, route: '/inventory', colors: [Colors.indigo, Colors.indigoAccent]),
    const _FeatureTile(title: 'Purchase Order History', icon: Icons.history, route: '/demandHistory', colors: [Colors.brown, Color(0xFF8D6E63)]),
    const _FeatureTile(title: 'Business Reports', icon: Icons.bar_chart, route: '/reports', colors: [Colors.blue, Colors.lightBlueAccent]),
  ];

  @override
  void initState() {
    super.initState();
    _loadTileOrder().then((_) {
      _autoSyncOnStartup();
    });
  }

  Future<void> _autoSyncOnStartup() async {
    final connectivity = context.read<ConnectivityService>();
    if (FirebaseAuth.instance.currentUser != null && connectivity.isOnline) {
      setState(() {
        _isSyncing = true;
        _syncStatus = 'Syncing your data...';
      });

      final result = await _syncService.syncAllData();

      setState(() {
        _isSyncing = false;
        _syncStatus = result.success ? 'Data synced successfully' : result.message;
      });

      if (result.success) {
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _syncStatus = '');
        });
      }
    } else {
      setState(() {
        _syncStatus = 'Offline Mode - Local data only';
      });
    }
  }

  Future<void> _saveTileOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final order = features.map((f) => f.title).toList();
    await prefs.setString('tile_order', jsonEncode(order));
  }

  Future<void> _loadTileOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('tile_order');
    if (stored != null) {
      final List<String> savedOrder = List<String>.from(jsonDecode(stored));
      features.sort((a, b) {
        final i1 = savedOrder.indexOf(a.title);
        final i2 = savedOrder.indexOf(b.title);
        return i1.compareTo(i2);
      });
    }
  }

  Future<void> _manualSync() async {
    final connectivity = context.read<ConnectivityService>();
    if (!connectivity.isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No internet. Data saved locally.'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() {
      _isSyncing = true;
      _syncStatus = 'Syncing data...';
    });

    final result = await _syncService.syncAllData();

    setState(() {
      _isSyncing = false;
      _syncStatus = result.message;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? Colors.green : Colors.red,
      ),
    );

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _syncStatus = '');
    });
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Logout')),
        ],
      ),
    );

    if (confirmed == true) {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logged out successfully'), backgroundColor: Colors.orange),
        );
        setState(() => _syncStatus = '');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectivity = context.watch<ConnectivityService>();
    final isOnline = connectivity.isOnline;
    final user = FirebaseAuth.instance.currentUser;
    final isLoggedIn = user != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dairy Manager'),
        centerTitle: true,
        backgroundColor: Theme.of(context).primaryColor,
        actions: [
          if (isLoggedIn) ...[
            IconButton(
              icon: _isSyncing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.sync),
              onPressed: _isSyncing ? null : _manualSync,
              tooltip: 'Sync Data',
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.account_circle),
              onSelected: (value) {
                if (value == 'logout') _logout();
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  enabled: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Signed in as:', style: TextStyle(fontSize: 12)),
                      Text(user?.email?.split('@').first ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [Icon(Icons.logout, size: 18), SizedBox(width: 8), Text('Logout')],
                  ),
                ),
              ],
            ),
          ] else ...[
            TextButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/login'),
              icon: const Icon(Icons.login, color: Colors.white),
              label: const Text('Login', style: TextStyle(color: Colors.white)),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          _buildStatusBar(isOnline, isLoggedIn),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ReorderableGridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    final item = features.removeAt(oldIndex);
                    features.insert(newIndex, item);
                  });
                  _saveTileOrder();
                },
                children: [for (final feature in features) _buildTile(feature, key: ValueKey(feature.title))],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(bool isOnline, bool isLoggedIn) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: isOnline ? Colors.green.shade50 : Colors.orange.shade50,
        border: Border(bottom: BorderSide(color: isOnline ? Colors.green.shade200 : Colors.orange.shade200)),
      ),
      child: Row(
        children: [
          Icon(isOnline ? Icons.cloud_done : Icons.cloud_off, size: 16, color: isOnline ? Colors.green.shade700 : Colors.orange.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _syncStatus.isNotEmpty ? _syncStatus : isOnline ? 'Online - Data syncs automatically' : 'Offline Mode - Local data only',
              style: TextStyle(fontSize: 12, color: isOnline ? Colors.green.shade800 : Colors.orange.shade800),
            ),
          ),
          if (_isSyncing)
            const SizedBox(width: 8),
          if (_isSyncing)
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: isOnline ? Colors.green.shade700 : Colors.orange.shade700)),
        ],
      ),
    );
  }

  Widget _buildTile(_FeatureTile feature, {required Key key}) {
    return Material(
      key: key,
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.pushNamed(context, feature.route),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: feature.colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: feature.colors.last.withOpacity(0.4), blurRadius: 6, offset: const Offset(3, 3))],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(feature.icon, size: 48, color: Colors.white),
              const SizedBox(height: 12),
              Text(feature.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureTile {
  final String title;
  final IconData icon;
  final String route;
  final List<Color> colors;

  const _FeatureTile({required this.title, required this.icon, required this.route, required this.colors});
}
