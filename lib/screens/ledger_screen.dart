import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // ✅ for nice date formatting
import '../services/database_helper.dart';
import '../services/backup_service.dart';
import '../models/client.dart';
import '../models/ledger_entry.dart';
import 'bill_details_screen.dart';

class LedgerScreen extends StatefulWidget {
  final Client client;
  const LedgerScreen({super.key, required this.client});

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  final db = DatabaseHelper();
  final BackupService _backup = BackupService();

  List<LedgerEntry> entries = [];
  bool _loading = true;
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

      // 🔄 Back up all entries in parallel, ignore failures to keep UI fast
      await Future.wait(list.map((e) async {
        try {
          await _backup.backupLedgerEntry(e);
        } catch (_) {
          // Log or ignore individual backup errors
        }
      }));

      if (mounted) setState(() => entries = list);
    } catch (e) {
      _showSnack('Failed to load ledger: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
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
    final controller = TextEditingController();
    final noteController = TextEditingController();

    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Cash Payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount'),
            ),
            TextField(
              controller: noteController,
              decoration:
              const InputDecoration(labelText: 'Note (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final amt = double.tryParse(controller.text) ?? 0;
              if (amt <= 0) return;
              final entry = LedgerEntry(
                clientId: widget.client.id!,
                type: 'payment',
                amount: amt,
                date: DateTime.now(),
                note: noteController.text.isEmpty
                    ? 'Cash Payment'
                    : noteController.text,
              );
              await db.insertLedgerEntry(entry);
              try {
                await _backup.backupLedgerEntry(entry);
              } catch (_) {
                // backup failure shouldn't block UI
              }
              controller.clear();
              noteController.clear();
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (res == true) _load();
  }

  void _showPaymentDetails(LedgerEntry e) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Payment Details"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("📅 Date: ${_dateFmt.format(e.date.toLocal())}"),
            const SizedBox(height: 6),
            Text("💰 Amount: ₹${e.amount.toStringAsFixed(2)}"),
            const SizedBox(height: 6),
            if (e.note != null && e.note!.isNotEmpty)
              Text("📝 Note: ${e.note}"),
            const SizedBox(height: 6),
            const Text("💳 Type: Payment received"),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final bal = _runningBalance();
    return Scaffold(
      appBar: AppBar(title: Text('Ledger - ${widget.client.name}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _load,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              color: bal >= 0 ? Colors.green[50] : Colors.red[50],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Final Balance:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(
                    '₹${bal.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: bal >= 0 ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add Cash Payment'),
                onPressed: _addPaymentDialog,
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? const Center(child: Text('No transactions'))
                  : ListView.builder(
                itemCount: entries.length,
                itemBuilder: (ctx, i) {
                  final e = entries[i];
                  final isBill = e.type == 'bill';
                  return ListTile(
                    leading: Icon(
                      isBill
                          ? Icons.receipt_long
                          : Icons.payments,
                      color: isBill ? Colors.red : Colors.green,
                    ),
                    title: Text(isBill ? 'Bill' : 'Payment'),
                    subtitle: Text(
                      '${_dateFmt.format(e.date.toLocal())}\n${e.note ?? ''}',
                    ),
                    trailing: Text(
                      (isBill ? '+ ' : '- ') +
                          '₹${e.amount.toStringAsFixed(2)}',
                      style: TextStyle(
                        color:
                        isBill ? Colors.red : Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    isThreeLine: true,
                    onTap: () {
                      if (isBill) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BillDetailsScreen(
                                billId: e.billId!),
                          ),
                        );
                      } else {
                        _showPaymentDetails(e);
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
