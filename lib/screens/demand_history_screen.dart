// lib/screens/demand_history_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../services/database_helper.dart';
import '../services/backup_service.dart';

class DemandHistoryScreen extends StatefulWidget {
  const DemandHistoryScreen({Key? key}) : super(key: key);

  @override
  State<DemandHistoryScreen> createState() => _DemandHistoryScreenState();
}

class _DemandHistoryScreenState extends State<DemandHistoryScreen> {
  final db = DatabaseHelper();
  final BackupService _backup = BackupService();
  List<Map<String, dynamic>> _days = [];

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

  /// Optional: Push full demand history to Firestore
  Future<void> _syncAllBatches() async {
    try {
      await _backup.backupAllDemandBatches(); // implement in BackupService
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All demand batches synced to Firestore')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup failed: $e')),
      );
    }
  }

  /// Build and share a PDF for a given batch/date
  Future<void> _exportPdf(int batchId, String date) async {
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
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Product Totals',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Table.fromTextArray(
            headers: ['Product', 'Quantity'],
            data: productTotals
                .map((r) => [
              r['productName'] ?? '',
              '${r['totalQty'] ?? 0}',
            ])
                .toList(),
          ),
          pw.SizedBox(height: 16),
          pw.Text('Client-wise Details',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          clientRows.isEmpty
              ? pw.Text('No individual client entries')
              : pw.Table.fromTextArray(
            headers: ['Client', 'Product', 'Qty'],
            data: clientRows
                .map((r) => [
              r['clientName'] ?? '',
              r['productName'] ?? '',
              '${r['qty']}'
            ])
                .toList(),
          ),
        ],
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/purchase_order_$date.pdf');
    await file.writeAsBytes(await pdf.save());
    await Share.shareXFiles([XFile(file.path)],
        text: 'Purchase Order – $date');
  }

  Future<void> _showDetails(int batchId, String date) async {
    final totals = await db.getBatchDetails(batchId);
    final clients = await db.getBatchClientDetails(batchId);

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Purchase Order – $date'),
        content: SizedBox(
          width: double.maxFinite,
          child: totals.isEmpty
              ? const Text('No demand recorded for this day')
              : ListView(
            shrinkWrap: true,
            children: [
              const Text('Product Totals',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              ...totals.map((r) => ListTile(
                dense: true,
                title: Text(r['productName'] ?? ''),
                trailing: Text('Qty: ${r['totalQty'] ?? 0}'),
              )),
              const Divider(),
              const Text('Client-wise',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              if (clients.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(4),
                  child: Text('No individual client entries'),
                )
              else
                ...clients.map((r) => ListTile(
                  dense: true,
                  title: Text(r['clientName'] ?? ''),
                  subtitle: Text(r['productName'] ?? ''),
                  trailing: Text('Qty: ${r['qty']}'),
                )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase Order History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            tooltip: 'Sync all to Firestore',
            onPressed: _syncAllBatches,
          ),
        ],
      ),
      body: _days.isEmpty
          ? const Center(child: Text('No purchase-order history'))
          : ListView.builder(
        itemCount: _days.length,
        itemBuilder: (ctx, i) {
          final b = _days[i];
          final closed = (b['closed'] ?? 0) == 1;
          final date = b['demandDate']?.toString() ?? '';
          final id = (b['id'] as int?) ?? -1;

          return ListTile(
            title: Text(date),
            subtitle: Text(closed ? 'Closed' : 'Open'),
            onTap: () => _showDetails(id, date),
            trailing: IconButton(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
              tooltip: 'Export PDF',
              onPressed: () => _exportPdf(id, date),
            ),
          );
        },
      ),
    );
  }
}
