// lib/widgets/sync_button.dart
import 'package:flutter/material.dart';
import '../services/backgroud_sync_service.dart';

class SyncButton extends StatefulWidget {
  final bool showLabel;

  const SyncButton({Key? key, this.showLabel = true}) : super(key: key);

  @override
  State<SyncButton> createState() => _SyncButtonState();
}

class _SyncButtonState extends State<SyncButton> {
  bool _syncing = false;

  Future<void> _handleSync() async {
    if (_syncing) return;

    setState(() => _syncing = true);

    try {
      final result = await BackgroundSyncService().syncNow();

      if (!mounted) return;

      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Synced successfully'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 8),
                Expanded(child: Text(result.message)),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.showLabel) {
      return ElevatedButton.icon(
        onPressed: _syncing ? null : _handleSync,
        icon: _syncing
            ? SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(Colors.white),
          ),
        )
            : Icon(Icons.cloud_sync),
        label: Text(_syncing ? 'Syncing...' : 'Sync Now'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
        ),
      );
    }

    return IconButton(
      onPressed: _syncing ? null : _handleSync,
      icon: _syncing
          ? SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      )
          : Icon(Icons.cloud_sync),
      tooltip: 'Sync with cloud',
    );
  }
}