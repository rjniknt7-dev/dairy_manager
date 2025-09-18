// lib/screens/demand_screen.dart
import 'package:flutter/material.dart';
import 'package:printing/printing.dart'; // for PDF sharing
import '../services/pdf_service.dart';   // helper to build pdf bytes
import '../services/database_helper.dart';
import '../models/client.dart';
import '../models/product.dart';
import 'demand_details_screen.dart';
import '../services/backup_service.dart'; // Firestore backup

class DemandScreen extends StatefulWidget {
  const DemandScreen({Key? key}) : super(key: key);

  @override
  State<DemandScreen> createState() => _DemandScreenState();
}

class _DemandScreenState extends State<DemandScreen> {
  final db = DatabaseHelper();
  final BackupService _backup = BackupService();

  List<Client> _clients = [];
  List<Product> _products = [];

  int? _selClientId;
  int? _selProductId;
  final _qtyCtrl = TextEditingController();

  int? _batchId;
  bool _batchClosed = false;

  List<Map<String, dynamic>> _totals = [];
  List<Map<String, dynamic>> _clientDetails = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final clients = await db.getClients();
    final products = await db.getProducts();
    final batchId = await db.getOrCreateBatchForDate(DateTime.now());
    final batchRow = await db.getBatchById(batchId);
    final totals = await db.getCurrentBatchTotals(batchId);
    final details = await db.getBatchClientDetails(batchId);

    if (!mounted) return;
    setState(() {
      _clients = clients;
      _products = products;
      _batchId = batchId;
      _totals = totals;
      _clientDetails = details;
      _batchClosed = (batchRow?['closed'] ?? 0) == 1;
    });
  }

  Future<void> _addOrder() async {
    if (_batchClosed) {
      _showSnack('Batch is closed. Cannot add more orders.');
      return;
    }
    if (_batchId == null || _selClientId == null || _selProductId == null) {
      _showSnack('Please select client, product and quantity.');
      return;
    }

    final q = double.tryParse(_qtyCtrl.text.trim());
    if (q == null || q <= 0) {
      _showSnack('Enter a valid quantity.');
      return;
    }

    await db.insertDemandEntry(
      batchId: _batchId!,
      clientId: _selClientId!,
      productId: _selProductId!,
      quantity: q,
    );

    _qtyCtrl.clear();
    await _loadAll();
    _showSnack('Purchase order added.');
  }

  Future<void> _closeOrderDay() async {
    if (_batchId == null || _batchClosed) return;
    await db.closeBatch(_batchId!, createNextDay: true);
    if (!mounted) return;
    _showSnack('Today’s purchase orders closed and stock updated.');
    await _loadAll();
  }

  /// Export current totals as a PDF that can be shared
  Future<void> _exportPdf() async {
    if (_totals.isEmpty) {
      _showSnack('No purchase orders to export.');
      return;
    }
    final dateStr = DateTime.now().toIso8601String().substring(0, 10);
    final pdfData = await PDFService.buildPurchaseOrderPdf(
      date: dateStr,
      totals: _totals,
    );
    await Printing.sharePdf(
      bytes: pdfData,
      filename: 'purchase_order_$dateStr.pdf',
    );
  }

  /// Push today’s batch to Firestore (manual sync)
  Future<void> _syncToCloud() async {
    if (_batchId == null) return;
    try {
      await _backup.backupDemandBatch(_batchId!);
      if (!mounted) return;
      _showSnack('Batch synced to Firestore.');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Sync failed: $e');
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateTime.now().toIso8601String().substring(0, 10);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text('Purchase Orders – $dateStr'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            tooltip: 'Sync to Firestore',
            onPressed: _syncToCloud,
          ),
          IconButton(
            icon: const Icon(Icons.list),
            tooltip: 'Product Totals',
            onPressed: () {
              if (_batchId != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DemandDetailsScreen(batchId: _batchId!),
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: 'Close & Update Stock',
            onPressed: _batchClosed ? null : _closeOrderDay,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<int>(
                value: _selClientId,
                hint: const Text('Select Client'),
                items: _clients
                    .map((c) =>
                    DropdownMenuItem<int>(value: c.id!, child: Text(c.name)))
                    .toList(),
                onChanged: (v) => setState(() => _selClientId = v),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: _selProductId,
                hint: const Text('Select Product'),
                items: _products
                    .map((p) => DropdownMenuItem<int>(
                    value: p.id!, child: Text('${p.name} (₹${p.price})')))
                    .toList(),
                onChanged: (v) => setState(() => _selProductId = v),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _qtyCtrl,
                decoration: const InputDecoration(labelText: 'Quantity'),
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add Purchase'),
                    onPressed: _batchClosed ? null : _addOrder,
                  ),
                  const SizedBox(width: 12),
                  if (_batchClosed)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.orange[100],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Batch Closed',
                        style: TextStyle(color: Colors.orange),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Today’s Product Totals',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.picture_as_pdf, color: Colors.indigo),
                    tooltip: 'Export Purchase Order PDF',
                    onPressed: _exportPdf,
                  ),
                ],
              ),
              _totals.isEmpty
                  ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No purchase orders yet'),
              )
                  : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _totals.length,
                itemBuilder: (_, i) {
                  final row = _totals[i];
                  return ListTile(
                    dense: true,
                    title: Text(row['productName'] ?? ''),
                    trailing: Text('Qty: ${row['totalQty'] ?? 0}'),
                  );
                },
              ),
              const Divider(),
              const Text(
                'Client-wise Orders',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              _clientDetails.isEmpty
                  ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No client entries'),
              )
                  : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _clientDetails.length,
                itemBuilder: (_, i) {
                  final r = _clientDetails[i];
                  return ListTile(
                    title: Text('${r['clientName']}'),
                    subtitle: Text('${r['productName']}'),
                    trailing: Text('Qty: ${r['qty']}'),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
