// lib/screens/demand_details_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/database_helper.dart';
import '../services/firebase_sync_service.dart';

class DemandDetailsScreen extends StatefulWidget {
  final int batchId;
  const DemandDetailsScreen({Key? key, required this.batchId}) : super(key: key);

  @override
  State<DemandDetailsScreen> createState() => _DemandDetailsScreenState();
}

class _DemandDetailsScreenState extends State<DemandDetailsScreen> {
  final db = DatabaseHelper();
  final _syncService = FirebaseSyncService();
  bool _isSyncing = false;
  late Future<List<Map<String, dynamic>>> _futureRows;

  @override
  void initState() {
    super.initState();
    _futureRows = db.getBatchClientDetails(widget.batchId);
  }

  Future<void> _syncDemandData() async {
    if (FirebaseAuth.instance.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Login to sync data'),
          action: SnackBarAction(
            label: 'LOGIN',
            onPressed: () => Navigator.pushNamed(context, '/login'),
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSyncing = true);
    final result = await _syncService.syncAllData();
    setState(() => _isSyncing = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = FirebaseAuth.instance.currentUser != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Demand Details'),
        actions: [
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
                : const Icon(Icons.sync),
            tooltip: 'Sync Data',
            onPressed: _isSyncing ? null : _syncDemandData,
          ),
        ],
      ),
      body: Column(
        children: [
          if (!isLoggedIn)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Colors.orange.shade100,
              child: Row(
                children: [
                  Icon(Icons.cloud_off, size: 16, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  const Text(
                    'Offline mode - Login to sync data',
                    style: TextStyle(fontSize: 12, color: Colors.orange),
                  ),
                ],
              ),
            ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
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
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No demand lines for this batch',
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                // Group rows by clientId
                final grouped = <int, List<Map<String, dynamic>>>{};
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
                    final clientName = (productRows.first['clientName'] as String?) ?? 'Unknown';
                    final totalQty = productRows.fold<double>(
                      0.0,
                          (sum, r) => sum + ((r['qty'] as num?)?.toDouble() ?? 0.0),
                    );

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 2,
                      child: ExpansionTile(
                        title: Text(clientName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        subtitle: Text('Total Qty: $totalQty'),
                        children: productRows.map((pr) {
                          final productName = pr['productName'] as String? ?? '';
                          final qty = (pr['qty'] as num?)?.toString() ?? '0';
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.shopping_bag_outlined, size: 20),
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
          ),
        ],
      ),
    );
  }
}
