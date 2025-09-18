// lib/screens/history_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../services/database_helper.dart';
import '../models/bill.dart';
import '../models/bill_item.dart';
import '../models/client.dart';
import '../models/product.dart';
import '../services/backup_service.dart'; // ✅ Firestore backup
import 'billing_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({Key? key}) : super(key: key);

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final BackupService _backup = BackupService(); // ✅
  final _dateFmt = DateFormat('yyyy-MM-dd');

  List<Bill> _bills = [];
  Map<int, Client> _clients = {};
  Map<int, Product> _products = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final db = DatabaseHelper();
    final clients = await db.getClients();
    final products = await db.getProducts();

    final dbInstance = await db.database;
    final billsData = await dbInstance.query(
      'bills',
      orderBy: 'date DESC',
    );

    setState(() {
      _bills = billsData.map((e) => Bill.fromMap(e)).toList();
      _clients = {for (final c in clients) c.id!: c};
      _products = {for (final p in products) p.id!: p};
    });
  }

  Future<void> _showBillItems(Bill bill) async {
    final db = DatabaseHelper();
    final items = await db.getBillItems(bill.id!);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Bill – ${_clients[bill.clientId]?.name ?? "Unknown"}'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 400),
          child: SingleChildScrollView(
            child: Column(
              children: items.map((item) {
                final product = _products[item.productId];
                return ListTile(
                  title: Text(product?.name ?? 'Unknown Product'),
                  subtitle: Text('Qty: ${item.quantity} × ₹${item.price}'),
                  trailing: Text(
                    '₹${(item.quantity * item.price).toStringAsFixed(2)}',
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Close'),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }

  /// Delete bill locally and remove its Firestore backup (offline-safe).
  Future<void> _deleteBill(Bill bill) async {
    final db = DatabaseHelper();
    await db.deleteBillCompletely(bill.id!); // local delete first
    try {
      await _backup.deleteBill(bill.id!);    // Firestore delete
    } catch (e) {
      // Don’t block the UI if offline – just inform the user.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Local delete done. Cloud sync pending: $e')),
        );
      }
    }
    _loadData();
  }

  void _confirmDelete(Bill bill) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Bill'),
        content: Text(
          'Delete bill for ${_clients[bill.clientId]?.name ?? "Unknown Client"}?',
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx),
          ),
          TextButton(
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
            onPressed: () async {
              Navigator.pop(ctx);
              await _deleteBill(bill);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Bill deleted')),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _editBill(Bill bill) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BillingScreen(existingBill: bill),
      ),
    );
    _loadData();
  }

  Future<void> _exportPdf(Bill bill) async {
    final db = DatabaseHelper();
    final items = await db.getBillItems(bill.id!);

    final pdf = pw.Document();
    final client = _clients[bill.clientId];
    final total = items.fold<double>(
      0.0,
          (sum, item) => sum + (item.price * item.quantity),
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Dairy Manager Bill',
                style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.Text('Client: ${client?.name ?? "Unknown"}'),
            pw.Text('Date: ${_dateFmt.format(bill.date.toLocal())}'),
            pw.SizedBox(height: 20),
            pw.Table.fromTextArray(
              headers: ['Product', 'Qty', 'Price', 'Total'],
              data: items.map((item) {
                final product = _products[item.productId];
                return [
                  product?.name ?? 'Unknown',
                  item.quantity.toString(),
                  '₹${item.price}',
                  '₹${(item.price * item.quantity).toStringAsFixed(2)}',
                ];
              }).toList(),
            ),
            pw.SizedBox(height: 20),
            pw.Text('Total Amount: ₹${total.toStringAsFixed(2)}',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/bill_${bill.id}.pdf');
    await file.writeAsBytes(await pdf.save());

    await Share.shareXFiles([XFile(file.path)], text: 'Bill PDF');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Billing History')),
      body: _bills.isEmpty
          ? const Center(child: Text('No bills found'))
          : ListView.builder(
        itemCount: _bills.length,
        itemBuilder: (context, index) {
          final bill = _bills[index];
          final client = _clients[bill.clientId];
          return Card(
            margin: const EdgeInsets.all(8),
            child: ListTile(
              title: Text(client?.name ?? 'Unknown Client'),
              subtitle: Text(
                'Date: ${_dateFmt.format(bill.date.toLocal())}\n'
                    'Total: ₹${bill.totalAmount}, '
                    'Paid: ₹${bill.paidAmount}, '
                    'CF: ₹${bill.carryForward}',
              ),
              onTap: () => _showBillItems(bill),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.picture_as_pdf, color: Colors.green),
                    tooltip: 'Export PDF',
                    onPressed: () => _exportPdf(bill),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    tooltip: 'Edit Bill',
                    onPressed: () => _editBill(bill),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    tooltip: 'Delete Bill',
                    onPressed: () => _confirmDelete(bill),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
