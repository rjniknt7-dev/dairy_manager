import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../models/client.dart';
import '../models/ledger_entry.dart';
import '../services/backup_service.dart';

class AddPaymentScreen extends StatefulWidget {
  const AddPaymentScreen({super.key});

  @override
  State<AddPaymentScreen> createState() => _AddPaymentScreenState();
}

class _AddPaymentScreenState extends State<AddPaymentScreen> {
  final db = DatabaseHelper();
  final _backup = BackupService();

  final amountCtrl = TextEditingController();
  final noteCtrl = TextEditingController();

  List<Client> clients = [];
  Client? selectedClient;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  Future<void> _loadClients() async {
    final c = await db.getClients();
    if (mounted) setState(() => clients = c);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus(); // close keyboard
    final amt = double.tryParse(amountCtrl.text.trim()) ?? 0;

    if (selectedClient == null || selectedClient?.id == null || amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a client and enter a valid amount')),
      );
      return;
    }

    setState(() => _saving = true);

    final entry = LedgerEntry(
      clientId: selectedClient!.id!,
      type: 'payment',
      amount: amt,
      date: DateTime.now(),
      note: noteCtrl.text.trim().isEmpty ? 'Cash Payment' : noteCtrl.text.trim(),
    );

    try {
      // 1️⃣ Save locally (SQLite)
      await db.insertLedgerEntry(entry);

      // 2️⃣ Attempt Firestore backup (will silently skip if offline)
      await _backup.backupLedger(entry);

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving payment: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    amountCtrl.dispose();
    noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Cash Payment')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            DropdownButtonFormField<Client>(
              value: selectedClient,
              items: clients
                  .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                  .toList(),
              onChanged: (v) => setState(() => selectedClient = v),
              decoration: const InputDecoration(labelText: 'Select Client'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Text('Save Payment'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
