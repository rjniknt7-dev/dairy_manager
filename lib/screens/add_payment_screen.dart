// lib/screens/add_payment_screen.dart - v2.1 (FIXED)
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/database_helper.dart';
import '../services/firebase_sync_service.dart';
import '../models/client.dart';
import '../models/ledger_entry.dart';

class AddPaymentScreen extends StatefulWidget {
  // ✅ ADD THIS: Allows passing a client ID to pre-select them.
  final int? preselectedClientId;

  // ✅ UPDATED CONSTRUCTOR: Accepts the optional client ID.
  const AddPaymentScreen({super.key, this.preselectedClientId});

  @override
  State<AddPaymentScreen> createState() => _AddPaymentScreenState();
}

class _AddPaymentScreenState extends State<AddPaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final db = DatabaseHelper();
  final _syncService = FirebaseSyncService();

  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _clientCtrl = TextEditingController();
  final _amountFocusNode = FocusNode();

  List<Client> _clients = [];
  Client? _selectedClient;
  bool _saving = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  Future<void> _loadClients() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final c = await db.getClients();
    if (mounted) {
      setState(() {
        _clients = c;
        // ✅ NEW LOGIC: If a client ID was passed, find and select that client.
        if (widget.preselectedClientId != null) {
          try {
            _selectedClient = _clients.firstWhere((client) => client.id == widget.preselectedClientId);
            _clientCtrl.text = _selectedClient?.name ?? '';
            // Automatically move focus to the amount field for faster entry
            WidgetsBinding.instance.addPostFrameCallback((_) {
              FocusScope.of(context).requestFocus(_amountFocusNode);
            });
          } catch (e) {
            // Client with that ID wasn't found, so we do nothing.
            debugPrint("Pre-selected client with ID ${widget.preselectedClientId} not found.");
          }
        }
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _saving = true);

    final entry = LedgerEntry(
      clientId: _selectedClient!.id!,
      type: 'payment',
      amount: double.parse(_amountCtrl.text.trim()),
      date: DateTime.now(),
      note: _noteCtrl.text.trim().isEmpty ? 'Cash Payment Received' : _noteCtrl.text.trim(),
    );

    try {
      await db.insertLedgerEntry(entry);
      _showSnack('Payment saved locally. Syncing...', isSuccess: true);

      _syncService.syncLedger().then((result) {
        if (mounted) _showSnack(result.message, isSuccess: result.success);
      });

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) _showSnack('Error saving payment: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _clientCtrl.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Payment'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _clients.isEmpty
          ? _buildEmptyState()
          : _buildPaymentForm(),
    );
  }

  Widget _buildPaymentForm() {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Client', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            // Autocomplete for clients
            Autocomplete<Client>(
              displayStringForOption: (Client option) => option.name,
              // Use initialValue to set the text if a client is pre-selected
              initialValue: TextEditingValue(text: _selectedClient?.name ?? ''),
              optionsBuilder: (TextEditingValue textEditingValue) {
                if (textEditingValue.text.isEmpty) {
                  return const Iterable<Client>.empty();
                }
                return _clients.where((Client option) {
                  final query = textEditingValue.text.toLowerCase();
                  return option.name.toLowerCase().contains(query) || (option.phone?.toLowerCase().contains(query) ?? false);
                });
              },
              onSelected: (Client selection) {
                setState(() => _selectedClient = selection);
                FocusScope.of(context).requestFocus(_amountFocusNode);
              },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                // Keep our local controller in sync with the Autocomplete's controller
                _clientCtrl.value = controller.value;
                return TextFormField(
                  controller: _clientCtrl,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    hintText: 'Search for a client...',
                    prefixIcon: const Icon(Icons.person_search),
                    border: const OutlineInputBorder(),
                    suffixIcon: _clientCtrl.text.isNotEmpty
                        ? IconButton(icon: const Icon(Icons.clear), onPressed: () {
                      controller.clear();
                      setState(() => _selectedClient = null);
                    })
                        : null,
                  ),
                  validator: (_) {
                    if (_selectedClient == null) return 'Please select a valid client';
                    return null;
                  },
                );
              },
            ),
            const SizedBox(height: 24),
            const Text('Payment Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _amountCtrl,
              focusNode: _amountFocusNode,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '₹ ',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Please enter an amount';
                final n = double.tryParse(v);
                if (n == null || n <= 0) return 'Enter an amount greater than 0';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Note (Optional)',
                hintText: 'e.g., Cash Received, Online Transfer',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save),
                label: Text(_saving ? 'SAVING...' : 'Save Payment', style: const TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.people_outline, size: 80, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('No Clients Found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Please add a client before recording a payment.', style: TextStyle(color: Colors.grey.shade600), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  void _showSnack(String msg, {bool isError = false, bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade700 : (isSuccess ? Colors.green.shade700 : Colors.black87),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}