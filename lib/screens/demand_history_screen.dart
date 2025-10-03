// lib/screens/demand_history_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../services/database_helper.dart';
import '../services/firebase_sync_service.dart';

class DemandHistoryScreen extends StatefulWidget {
  const DemandHistoryScreen({Key? key}) : super(key: key);

  @override
  State<DemandHistoryScreen> createState() => _DemandHistoryScreenState();
}

class _DemandHistoryScreenState extends State<DemandHistoryScreen> {
  final db = DatabaseHelper();
  final _syncService = FirebaseSyncService();
  List<Map<String, dynamic>> _days = [];
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadDays();
  }

  /// Load one row per demandDate with latest status (Open/Closed)
  Future<void> _loadDays() async {
    final list = await db.rawQuery('''
      SELECT id, demandDate, MAX(closed) AS closed
      FROM demand_batch
      GROUP BY demandDate
      ORDER BY demandDate DESC
    ''');
    if (!mounted) return;
    setState(() => _days = list);
  }

  /// Sync all demand/purchase order data
  Future<void> _syncAllData() async {
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

    if (result.success) await _loadDays();
  }

  /// Build and share a PDF for a given batch/date
  Future<void> _exportPdf(int batchId, String date) async {
    try {
      final productTotals = await db.getBatchDetails(batchId);
      final clientRows = await db.getBatchClientDetails(batchId);

      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (_) => [
            pw.Header(
              level: 0,
              child: pw.Text(
                'Purchase Order – $date',
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 8),
            if (productTotals.isNotEmpty)
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Product Totals', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  pw.Table.fromTextArray(
                    headers: ['Product', 'Quantity'],
                    data: productTotals.map((r) => [r['productName'] ?? '', '${r['totalQty'] ?? 0}']).toList(),
                  ),
                ],
              )
            else
              pw.Text('No products ordered'),
            pw.SizedBox(height: 16),
            if (clientRows.isNotEmpty)
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Client-wise Details', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  pw.Table.fromTextArray(
                    headers: ['Client', 'Product', 'Qty'],
                    data: clientRows.map((r) => [r['clientName'] ?? '', r['productName'] ?? '', '${r['qty']}']).toList(),
                  ),
                ],
              )
            else
              pw.Text('No individual client entries'),
          ],
        ),
      );

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/purchase_order_$date.pdf');
      await file.writeAsBytes(await pdf.save());
      await Share.shareXFiles([XFile(file.path)], text: 'Purchase Order – $date');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showDetails(int batchId, String date) async {
    final totals = await db.getBatchDetails(batchId);
    final clients = await db.getBatchClientDetails(batchId);
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Purchase Order – $date', style: const TextStyle(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          child: totals.isEmpty && clients.isEmpty
              ? const Text('No demand recorded for this day')
              : SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (totals.isNotEmpty) ...[
                  const Text('Product Totals', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  ...totals.map((r) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.inventory_2, size: 20),
                    title: Text(r['productName'] ?? ''),
                    trailing: Text('Qty: ${r['totalQty'] ?? 0}'),
                  )),
                  const Divider(),
                ],
                if (clients.isNotEmpty) ...[
                  const Text('Client-wise', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  ...clients.map((r) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.person, size: 20),
                    title: Text(r['clientName'] ?? ''),
                    subtitle: Text(r['productName'] ?? ''),
                    trailing: Text('Qty: ${r['qty']}'),
                  )),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          if (totals.isNotEmpty || clients.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _exportPdf(batchId, date);
              },
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Export PDF'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = FirebaseAuth.instance.currentUser != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase Order History'),
        actions: [
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
                : const Icon(Icons.sync),
            tooltip: 'Sync all data',
            onPressed: _isSyncing ? null : _syncAllData,
          ),
        ],
      ),
      body: Column(
        children: [
          // Offline indicator
          if (!isLoggedIn)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Colors.orange.shade100,
              child: Row(
                children: [
                  Icon(Icons.cloud_off, size: 16, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  const Text('Offline mode - Login to sync data',
                      style: TextStyle(fontSize: 12, color: Colors.orange)),
                ],
              ),
            ),

          // List of previous purchase orders
          Expanded(
            child: _days.isEmpty
                ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No purchase-order history', style: TextStyle(fontSize: 18, color: Colors.grey)),
                  Text('Create some purchase orders to see history', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
                : RefreshIndicator(
              onRefresh: _loadDays,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _days.length,
                itemBuilder: (ctx, i) {
                  final b = _days[i];
                  final closed = (b['closed'] ?? 0) == 1;
                  final date = b['demandDate']?.toString() ?? '';
                  final id = (b['id'] as int?) ?? -1;

                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: closed ? Colors.green : Colors.orange,
                        child: Icon(closed ? Icons.check : Icons.pending, color: Colors.white, size: 20),
                      ),
                      title: Text(date, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(closed ? 'Closed' : 'Open'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                            tooltip: 'Export PDF',
                            onPressed: () => _exportPdf(id, date),
                          ),
                          if (!closed)
                            IconButton(
                              icon: const Icon(Icons.remove_red_eye, color: Colors.blue),
                              tooltip: 'View Details',
                              onPressed: () => _showDetails(id, date),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

