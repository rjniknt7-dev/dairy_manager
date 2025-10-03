// lib/screens/ledger_screen.dart
import 'package:flutter/material.dart' as fl;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/database_helper.dart';
import '../services/firebase_sync_service.dart';
import '../models/client.dart';
import '../models/ledger_entry.dart';
import 'bill_details_screen.dart';

class LedgerScreen extends fl.StatefulWidget {
  final Client client;
  const LedgerScreen({super.key, required this.client});

  @override
  fl.State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends fl.State<LedgerScreen> {
  final db = DatabaseHelper();
  final _syncService = FirebaseSyncService();

  List<LedgerEntry> entries = [];
  bool _loading = true;
  bool _isSyncing = false;
  final _dateFmt = DateFormat('dd-MM-yyyy  HH:mm');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await db.getLedgerEntriesByClient(widget.client.id!);
      if (mounted) setState(() => entries = list);
    } catch (e) {
      _showSnack('Failed to load ledger: $e', fl.Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _syncLedgerData() async {
    if (FirebaseAuth.instance.currentUser == null) {
      fl.ScaffoldMessenger.of(context).showSnackBar(
        fl.SnackBar(
          content: const fl.Text('Login to sync data'),
          action: fl.SnackBarAction(
            label: 'LOGIN',
            onPressed: () => fl.Navigator.pushNamed(context, '/login'),
          ),
          backgroundColor: fl.Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSyncing = true);

    final result = await _syncService.syncAllData();

    setState(() => _isSyncing = false);

    fl.ScaffoldMessenger.of(context).showSnackBar(
      fl.SnackBar(
        content: fl.Text(result.message),
        backgroundColor: result.success ? fl.Colors.green : fl.Colors.red,
      ),
    );

    if (result.success) {
      await _load();
    }
  }

  double _runningBalance() {
    double bal = 0;
    for (var e in entries) {
      if (e.type == 'bill') {
        bal += e.amount;
      } else if (e.type == 'payment') {
        bal -= e.amount;
      }
    }
    return bal;
  }

  Future<void> _addPaymentDialog() async {
    final controller = fl.TextEditingController();
    final noteController = fl.TextEditingController();

    final res = await fl.showDialog<bool>(
      context: context,
      builder: (ctx) => fl.AlertDialog(
        title: const fl.Text('Add Cash Payment'),
        content: fl.Column(
          mainAxisSize: fl.MainAxisSize.min,
          children: [
            fl.TextField(
              controller: controller,
              keyboardType: const fl.TextInputType.numberWithOptions(decimal: true),
              decoration: const fl.InputDecoration(
                labelText: 'Amount',
                border: fl.OutlineInputBorder(),
              ),
            ),
            const fl.SizedBox(height: 16),
            fl.TextField(
              controller: noteController,
              decoration: const fl.InputDecoration(
                labelText: 'Note (optional)',
                border: fl.OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          fl.TextButton(
            onPressed: () => fl.Navigator.pop(ctx, false),
            child: const fl.Text('Cancel'),
          ),
          fl.ElevatedButton(
            onPressed: () async {
              final amt = double.tryParse(controller.text) ?? 0;
              if (amt <= 0) {
                fl.ScaffoldMessenger.of(context).showSnackBar(
                  const fl.SnackBar(content: fl.Text('Enter a valid amount')),
                );
                return;
              }

              final entry = LedgerEntry(
                clientId: widget.client.id!,
                type: 'payment',
                amount: amt,
                date: DateTime.now(),
                note: noteController.text.isEmpty
                    ? 'Cash Payment'
                    : noteController.text,
                isSynced: false,
              );

              try {
                await db.insertLedgerEntry(entry);
                _showSnack('Payment added locally');

                if (FirebaseAuth.instance.currentUser != null) {
                  final result = await _syncService.syncAllData();
                  if (result.success) {
                    _showSnack('Payment synced to cloud', fl.Colors.green);
                  } else {
                    _showSnack('Will sync when connection improves', fl.Colors.orange);
                  }
                }

                controller.clear();
                noteController.clear();
                if (ctx.mounted) fl.Navigator.pop(ctx, true);
              } catch (e) {
                _showSnack('Failed to add payment: $e', fl.Colors.red);
              }
            },
            child: const fl.Text('Save'),
          ),
        ],
      ),
    );

    if (res == true) _load();
  }

  void _showPaymentDetails(LedgerEntry e) {
    fl.showDialog(
      context: context,
      builder: (ctx) => fl.AlertDialog(
        title: const fl.Text("Payment Details"),
        content: fl.Column(
          mainAxisSize: fl.MainAxisSize.min,
          crossAxisAlignment: fl.CrossAxisAlignment.start,
          children: [
            fl.ListTile(
              leading: const fl.Icon(fl.Icons.calendar_today),
              title: const fl.Text("Date"),
              subtitle: fl.Text(_dateFmt.format(e.date.toLocal())),
            ),
            fl.ListTile(
              leading: const fl.Icon(fl.Icons.payments),
              title: const fl.Text("Amount"),
              subtitle: fl.Text('₹${e.amount.toStringAsFixed(2)}'),
            ),
            if (e.note != null && e.note!.isNotEmpty)
              fl.ListTile(
                leading: const fl.Icon(fl.Icons.note),
                title: const fl.Text("Note"),
                subtitle: fl.Text(e.note!),
              ),
            fl.ListTile(
              leading: const fl.Icon(fl.Icons.category),
              title: const fl.Text("Type"),
              subtitle: const fl.Text("Payment received"),
            ),
          ],
        ),
        actions: [
          fl.TextButton(
            onPressed: () => fl.Navigator.pop(ctx),
            child: const fl.Text("Close"),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg, [fl.Color? backgroundColor]) {
    if (!mounted) return;
    fl.ScaffoldMessenger.of(context).showSnackBar(
      fl.SnackBar(content: fl.Text(msg), backgroundColor: backgroundColor),
    );
  }

  @override
  fl.Widget build(fl.BuildContext context) {
    final bal = _runningBalance();
    final isLoggedIn = FirebaseAuth.instance.currentUser != null;

    return fl.Scaffold(
      appBar: fl.AppBar(
        title: fl.Text('Ledger - ${widget.client.name}'),
        actions: [
          fl.IconButton(
            icon: _isSyncing
                ? const fl.SizedBox(
              width: 20,
              height: 20,
              child: fl.CircularProgressIndicator(
                strokeWidth: 2,
                color: fl.Colors.white,
              ),
            )
                : const fl.Icon(fl.Icons.sync),
            onPressed: _isSyncing ? null : _syncLedgerData,
            tooltip: 'Sync Data',
          ),
        ],
      ),
      body: fl.Column(
        children: [
          if (!isLoggedIn)
            fl.Container(
              width: double.infinity,
              padding: const fl.EdgeInsets.all(8),
              color: fl.Colors.orange.shade100,
              child: fl.Row(
                children: [
                  fl.Icon(fl.Icons.cloud_off, size: 16, color: fl.Colors.orange.shade700),
                  const fl.SizedBox(width: 8),
                  const fl.Text(
                    'Offline mode - Login to sync data',
                    style: fl.TextStyle(fontSize: 12, color: fl.Colors.orange),
                  ),
                ],
              ),
            ),
          fl.Expanded(
            child: _loading
                ? const fl.Center(child: fl.CircularProgressIndicator())
                : fl.RefreshIndicator(
              onRefresh: _load,
              child: fl.Column(
                children: [
                  fl.Card(
                    margin: const fl.EdgeInsets.all(12),
                    color: bal >= 0 ? fl.Colors.green.shade50 : fl.Colors.red.shade50,
                    child: fl.Padding(
                      padding: const fl.EdgeInsets.all(16),
                      child: fl.Row(
                        mainAxisAlignment: fl.MainAxisAlignment.spaceBetween,
                        children: [
                          fl.Column(
                            crossAxisAlignment: fl.CrossAxisAlignment.start,
                            children: [
                              const fl.Text(
                                'Final Balance',
                                style: fl.TextStyle(fontWeight: fl.FontWeight.bold),
                              ),
                              fl.Text(
                                bal >= 0 ? 'Amount Due' : 'Credit Balance',
                                style: const fl.TextStyle(fontSize: 12, color: fl.Colors.grey),
                              ),
                            ],
                          ),
                          fl.Text(
                            '₹${bal.abs().toStringAsFixed(2)}',
                            style: fl.TextStyle(
                              fontSize: 24,
                              fontWeight: fl.FontWeight.bold,
                              color: bal >= 0 ? fl.Colors.red : fl.Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  fl.Padding(
                    padding: const fl.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: fl.SizedBox(
                      width: double.infinity,
                      child: fl.ElevatedButton.icon(
                        icon: const fl.Icon(fl.Icons.add),
                        label: const fl.Text('Add Cash Payment'),
                        onPressed: _addPaymentDialog,
                        style: fl.ElevatedButton.styleFrom(
                          backgroundColor: fl.Colors.green,
                          foregroundColor: fl.Colors.white,
                        ),
                      ),
                    ),
                  ),
                  fl.Expanded(
                    child: entries.isEmpty
                        ? const fl.Center(
                      child: fl.Column(
                        mainAxisAlignment: fl.MainAxisAlignment.center,
                        children: [
                          fl.Icon(fl.Icons.receipt_long, size: 64, color: fl.Colors.grey),
                          fl.SizedBox(height: 16),
                          fl.Text(
                            'No transactions',
                            style: fl.TextStyle(fontSize: 18, color: fl.Colors.grey),
                          ),
                          fl.Text(
                            'Bills and payments will appear here',
                            style: fl.TextStyle(color: fl.Colors.grey),
                          ),
                        ],
                      ),
                    )
                        : fl.ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (ctx, i) {
                        final e = entries[i];
                        final isBill = e.type == 'bill';
                        final needsSync = !e.isSynced && isLoggedIn;

                        return fl.Card(
                          margin: const fl.EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: fl.ListTile(
                            leading: fl.CircleAvatar(
                              backgroundColor: isBill ? fl.Colors.red : fl.Colors.green,
                              child: fl.Icon(
                                isBill ? fl.Icons.receipt_long : fl.Icons.payments,
                                color: fl.Colors.white,
                                size: 20,
                              ),
                            ),
                            title: fl.Row(
                              children: [
                                fl.Expanded(child: fl.Text(isBill ? 'Bill' : 'Payment')),
                                if (needsSync)
                                  fl.Icon(
                                    fl.Icons.sync_problem,
                                    size: 16,
                                    color: fl.Colors.orange.shade600,
                                  ),
                              ],
                            ),
                            subtitle: fl.Column(
                              crossAxisAlignment: fl.CrossAxisAlignment.start,
                              children: [
                                fl.Text(_dateFmt.format(e.date.toLocal())),
                                if (e.note != null && e.note!.isNotEmpty)
                                  fl.Text(
                                    e.note!,
                                    style: const fl.TextStyle(fontSize: 12),
                                  ),
                                if (needsSync)
                                  fl.Text(
                                    'Pending sync',
                                    style: fl.TextStyle(
                                      color: fl.Colors.orange.shade600,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                            trailing: fl.Text(
                              (isBill ? '+ ' : '- ') + '₹${e.amount.toStringAsFixed(2)}',
                              style: fl.TextStyle(
                                color: isBill ? fl.Colors.red : fl.Colors.green,
                                fontWeight: fl.FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            isThreeLine: true,
                            onTap: () {
                              if (isBill && e.billId != null) {
                                fl.Navigator.push(
                                  context,
                                  fl.MaterialPageRoute(
                                    builder: (_) => BillDetailsScreen(billId: e.billId!),
                                  ),
                                );
                              } else {
                                _showPaymentDetails(e);
                              }
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
