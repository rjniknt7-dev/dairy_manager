// lib/screens/demand_details_screen.dart
import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/backup_service.dart';

class DemandDetailsScreen extends StatefulWidget {
  final int batchId;
  const DemandDetailsScreen({Key? key, required this.batchId}) : super(key: key);

  @override
  State<DemandDetailsScreen> createState() => _DemandDetailsScreenState();
}

class _DemandDetailsScreenState extends State<DemandDetailsScreen> {
  final db = DatabaseHelper();
  final BackupService _backup = BackupService();

  late Future<List<Map<String, dynamic>>> _futureRows;

  @override
  void initState() {
    super.initState();
    _futureRows = db.getBatchClientDetails(widget.batchId);
  }

  Future<void> _syncBackup() async {
    try {
      // Call your backup service; adjust if you have a specific method for batch sync
      await _backup.backupDemandBatch(widget.batchId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup synced to Firestore')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Demand Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            tooltip: 'Sync to Firestore',
            onPressed: _syncBackup,
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _futureRows,
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }

          final rows = snap.data ?? [];
          if (rows.isEmpty) {
            return const Center(child: Text('No demand lines for this batch'));
          }

          // ---- Group by clientId ----
          final Map<int, List<Map<String, dynamic>>> grouped = {};
          for (final r in rows) {
            final cid = (r['clientId'] as int?) ?? -1;
            grouped.putIfAbsent(cid, () => []).add(r);
          }

          final clients = grouped.entries.toList();

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: clients.length,
            itemBuilder: (ctx, i) {
              final productRows = clients[i].value;
              final clientName =
                  (productRows.first['clientName'] as String?) ?? 'Unknown';

              // Calculate total qty per client
              final totalQty = productRows.fold<double>(
                0.0,
                    (sum, r) =>
                sum +
                    (r['qty'] is num
                        ? (r['qty'] as num).toDouble()
                        : 0.0),
              );

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 2,
                child: ExpansionTile(
                  title: Text(
                    clientName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  subtitle: Text('Total Qty: $totalQty'),
                  children: productRows.map((pr) {
                    final productName = pr['productName'] as String? ?? '';
                    final qty =
                    pr['qty'] is num ? (pr['qty'] as num).toString() : '0';
                    return ListTile(
                      dense: true,
                      title: Text(productName),
                      trailing: Text('Qty: $qty'),
                    );
                  }).toList(),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
