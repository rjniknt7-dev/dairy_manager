// lib/screens/ledger_book_screen.dart - v2.0 (Intelligent & Polished)
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/database_helper.dart';
import '../services/firebase_sync_service.dart';
import '../models/client.dart';
import 'ledger_screen.dart';
// import 'add_client_screen.dart'; // Make sure this screen exists

class LedgerBookScreen extends StatefulWidget {
  const LedgerBookScreen({super.key});

  @override
  State<LedgerBookScreen> createState() => _LedgerBookScreenState();
}

class _LedgerBookScreenState extends State<LedgerBookScreen> {
  final db = DatabaseHelper();
  final _syncService = FirebaseSyncService();
  final _currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

  List<Map<String, dynamic>> _clientsWithBalance = [];
  List<Map<String, dynamic>> _filteredClients = [];
  bool _loading = true;
  bool _isSyncing = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadClientData();
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ✅ UPDATED: Fetches clients with their balances for a smart list
  Future<void> _loadClientData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final list = await db.getClientsWithBalances();
      if (mounted) {
        setState(() {
          _clientsWithBalance = list;
          _filteredClients = list;
          _loading = false;
        });
      }
    } catch (e) {
      _showSnack('Failed to load clients: $e', isError: true);
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredClients = query.isEmpty
          ? _clientsWithBalance
          : _clientsWithBalance.where((clientMap) {
        final client = Client.fromMap(clientMap);
        return client.name.toLowerCase().contains(query) || (client.phone?.toLowerCase().contains(query) ?? false);
      }).toList();
    });
  }

  Future<void> _syncData() async {
    if (FirebaseAuth.instance.currentUser == null) {
      _showSnack('Login required to sync data.', isError: true);
      return;
    }
    if (_isSyncing) return;

    setState(() => _isSyncing = true);
    final result = await _syncService.syncAllData();
    if (mounted) {
      setState(() => _isSyncing = false);
      _showSnack(result.message, isSuccess: result.success);
      if (result.success) _loadClientData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Client Ledgers'),
        actions: [
          IconButton(
            icon: _isSyncing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.sync),
            tooltip: 'Sync All Data',
            onPressed: _syncData,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name or phone…',
                filled: true,
                fillColor: Colors.white.withOpacity(0.9),
                prefixIcon: const Icon(Icons.search),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.person_add),
        onPressed: () {
          // TODO: Implement navigation to AddClientScreen
          // Navigator.push(context, MaterialPageRoute(builder: (_) => const AddClientScreen())).then((_) => _loadClientData());
          _showSnack("Navigate to 'Add Client' screen here.", isSuccess: true);
        },
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _filteredClients.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
        onRefresh: _loadClientData,
        child: ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: _filteredClients.length,
          itemBuilder: (ctx, i) {
            final clientMap = _filteredClients[i];
            final client = Client.fromMap(clientMap);
            final balance = (clientMap['balance'] as num?)?.toDouble() ?? 0.0;

            final hasDue = balance > 0;
            final isSynced = client.isSynced;

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              elevation: 2,
              shadowColor: (hasDue ? Colors.red : Colors.green).withOpacity(0.1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: (hasDue ? Colors.red.shade50 : Colors.green.shade50),
                  child: Text(
                    client.name.isNotEmpty ? client.name[0].toUpperCase() : '?',
                    style: TextStyle(fontWeight: FontWeight.bold, color: hasDue ? Colors.red.shade800 : Colors.green.shade800),
                  ),
                ),
                title: Text(client.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(client.phone ?? 'No phone number'),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _currencyFormat.format(balance.abs()),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: hasDue ? Colors.red : Colors.green,
                      ),
                    ),
                    Text(
                      hasDue ? 'Due' : 'Credit',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                    ),
                  ],
                ),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => LedgerScreen(client: client)))
                      .then((_) => _loadClientData()); // Reload balances when returning
                },
              ),
            );
          },
        ),
      ),
    );
  }





  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline,
                size: 90, color: Colors.redAccent.shade100),
            const SizedBox(height: 20),
            const Text(
              'No clients yet',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap “Add Client” to create your first ledger entry.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
  void _showSnack(String message, {bool isError = false, bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red.shade700 : (isSuccess ? Colors.green.shade700 : Colors.black87),
      behavior: SnackBarBehavior.floating,
    ));
  }
}
