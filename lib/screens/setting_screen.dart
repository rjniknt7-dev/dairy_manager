// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/backgroud_sync_service.dart';
import '../widgets/sync_button.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic>? _syncStatus;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadSyncStatus();
  }

  Future<void> _loadSyncStatus() async {
    setState(() => _loading = true);

    try {
      final status = await BackgroundSyncService().getSyncStatus();
      setState(() {
        _syncStatus = status;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _forceUploadAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Force Upload All Data?'),
        content: Text(
          'This will mark all local data as unsynced and re-upload everything to the cloud. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Upload'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _loading = true);

    try {
      final result = await BackgroundSyncService().forceUploadAll();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.success ? Colors.green : Colors.red,
        ),
      );

      if (result.success) {
        await _loadSyncStatus();
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Force upload failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Logout'),
        content: Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text('Settings & Sync'),
        backgroundColor: Colors.green,
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : ListView(
        padding: EdgeInsets.all(16),
        children: [
          // User Info Card
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.green,
                child: Icon(Icons.person, color: Colors.white),
              ),
              title: Text(user?.email ?? 'Not logged in'),
              subtitle: Text(user != null ? 'Logged in' : 'Offline mode'),
              trailing: IconButton(
                icon: Icon(Icons.logout, color: Colors.red),
                onPressed: _logout,
                tooltip: 'Logout',
              ),
            ),
          ),

          SizedBox(height: 16),

          // Sync Controls Card
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cloud Sync',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: SyncButton(showLabel: true),
                  ),

                  SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _forceUploadAll,
                      icon: Icon(Icons.cloud_upload),
                      label: Text('Force Upload All'),
                    ),
                  ),

                  SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _loadSyncStatus,
                      icon: Icon(Icons.refresh),
                      label: Text('Refresh Status'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: 16),

          // Sync Status Card
          if (_syncStatus != null) ...[
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sync Status',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    SizedBox(height: 16),

                    _buildStatusRow(
                      'Connection',
                      _syncStatus!['hasConnection'] == true
                          ? 'Online'
                          : 'Offline',
                      _syncStatus!['hasConnection'] == true
                          ? Colors.green
                          : Colors.red,
                    ),

                    _buildStatusRow(
                      'Authentication',
                      _syncStatus!['isAuthenticated'] == true
                          ? 'Logged in'
                          : 'Not logged in',
                      _syncStatus!['isAuthenticated'] == true
                          ? Colors.green
                          : Colors.orange,
                    ),

                    Divider(height: 32),

                    Text(
                      'Data Sync Status',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SizedBox(height: 12),

                    _buildTableStatus('Clients', _syncStatus!['clients']),
                    _buildTableStatus('Products', _syncStatus!['products']),
                    _buildTableStatus('Bills', _syncStatus!['bills']),
                    _buildTableStatus('Bill Items', _syncStatus!['bill_items']),
                    _buildTableStatus('Ledger', _syncStatus!['ledger']),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, Color color) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color),
            ),
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableStatus(String table, Map<String, dynamic>? data) {
    if (data == null) return SizedBox.shrink();

    final total = data['total'] ?? 0;
    final unsynced = data['unsynced'] ?? 0;
    final percent = data['syncedPercent'] ?? 100;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(table),
              Text(
                '$unsynced unsynced / $total total',
                style: TextStyle(
                  color: unsynced > 0 ? Colors.orange : Colors.green,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          SizedBox(height: 4),
          LinearProgressIndicator(
            value: percent / 100,
            backgroundColor: Colors.grey[300],
            valueColor: AlwaysStoppedAnimation(
              unsynced > 0 ? Colors.orange : Colors.green,
            ),
          ),
        ],
      ),
    );
  }
}