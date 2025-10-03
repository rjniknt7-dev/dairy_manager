import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/database_helper.dart';
import '../services/firebase_sync_service.dart';
import '../models/client.dart';
import '../models/ledger_entry.dart';

class AddPaymentScreen extends StatefulWidget {
  const AddPaymentScreen({super.key});

  @override
  State<AddPaymentScreen> createState() => _AddPaymentScreenState();
}

class _AddPaymentScreenState extends State<AddPaymentScreen> {
  final db = DatabaseHelper();
  final _syncService = FirebaseSyncService();

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
    FocusScope.of(context).unfocus();
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
      isSynced: false, // Mark as needing sync
    );

    try {
      // Save locally first
      await db.insertLedgerEntry(entry);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment saved locally')),
      );

      // Auto-sync if logged in
      if (FirebaseAuth.instance.currentUser != null) {
        final result = await _syncService.syncAllData();
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment synced to cloud'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Will sync when connection improves'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving payment: $e'),
            backgroundColor: Colors.red,
          ),
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
    final isLoggedIn = FirebaseAuth.instance.currentUser != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Cash Payment'),
        backgroundColor: Colors.indigo.shade700,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Offline notice
            if (!isLoggedIn)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.orange.shade200, Colors.orange.shade100],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.cloud_off, size: 16, color: Colors.orange.shade900),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Offline mode - Login to sync data',
                        style: TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 3,
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            // Client dropdown
                            DropdownButtonFormField<Client>(
                              value: selectedClient,
                              items: clients
                                  .map((c) => DropdownMenuItem(
                                value: c,
                                child: Text(c.name),
                              ))
                                  .toList(),
                              onChanged: (v) => setState(() => selectedClient = v),
                              decoration: InputDecoration(
                                labelText: 'Select Client',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Amount
                            TextField(
                              controller: amountCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Amount',
                                prefixText: '₹ ',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Note
                            TextField(
                              controller: noteCtrl,
                              decoration: InputDecoration(
                                labelText: 'Note (optional)',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Save Button
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.indigo.shade700,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: _saving ? null : _save,
                                child: _saving
                                    ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                                    : const Text(
                                  'Save Payment',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
