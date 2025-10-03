import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/database_helper.dart';
import '../services/firebase_sync_service.dart';
import '../models/client.dart';
import 'ledger_screen.dart';
// import 'add_client_screen.dart'; // if you have an AddClientScreen

class LedgerBookScreen extends StatefulWidget {
  const LedgerBookScreen({super.key});

  @override
  State<LedgerBookScreen> createState() => _LedgerBookScreenState();
}

class _LedgerBookScreenState extends State<LedgerBookScreen> {
  final db = DatabaseHelper();
  final _syncService = FirebaseSyncService();

  List<Client> _clients = [];
  List<Client> _filtered = [];
  bool _loading = true;
  bool _isSyncing = false;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  Future<void> _loadClients() async {
    setState(() => _loading = true);
    try {
      final list = await db.getClients();
      if (mounted) {
        _clients = list;
        _applyFilter();
      }
    } catch (e) {
      _showSnack('Failed to load clients: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    final q = _search.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _clients
          : _clients
          .where((c) =>
      c.name.toLowerCase().contains(q) ||
          c.phone.toLowerCase().contains(q))
          .toList();
    });
  }

  Future<void> _syncLedgerData() async {
    if (FirebaseAuth.instance.currentUser == null) {
      _showSnack('Login to sync data', Colors.orange);
      return;
    }
    setState(() => _isSyncing = true);
    final result = await _syncService.syncAllData();
    if (mounted) setState(() => _isSyncing = false);

    _showSnack(result.message,
        result.success ? Colors.green : Colors.red);
    if (result.success) await _loadClients();
  }

  void _showSnack(String message, [Color? color]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = FirebaseAuth.instance.currentUser != null;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Ledger Book'),
        backgroundColor: Colors.redAccent,
        actions: [
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
                : const Icon(Icons.sync),
            tooltip: 'Sync Data',
            onPressed: _isSyncing ? null : _syncLedgerData,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by name or phone…',
                filled: true,
                fillColor: Colors.white,
                prefixIcon: const Icon(Icons.search),
                contentPadding:
                const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) {
                _search = v;
                _applyFilter();
              },
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.redAccent,
        icon: const Icon(Icons.person_add),
        label: const Text('Add Client'),
        onPressed: () {
          // Navigator.push(context,
          //   MaterialPageRoute(builder: (_) => const AddClientScreen()))
          //     .then((_) => _loadClients());
        },
      ),
      body: Column(
        children: [
          if (!isLoggedIn)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Colors.orange.shade100,
              child: Row(
                children: [
                  Icon(Icons.cloud_off, size: 18, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  const Text(
                    'Offline mode – Login to sync data',
                    style: TextStyle(fontSize: 13, color: Colors.orange),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
              onRefresh: _loadClients,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                itemCount: _filtered.length,
                itemBuilder: (ctx, i) {
                  final client = _filtered[i];
                  final needsSync =
                      !client.isSynced && isLoggedIn;
                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.redAccent,
                        child: Text(
                          client.name.isNotEmpty
                              ? client.name[0].toUpperCase()
                              : '?',
                          style:
                          const TextStyle(color: Colors.white),
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              client.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (needsSync)
                            Icon(Icons.sync_problem,
                                size: 18,
                                color: Colors.orange.shade600),
                        ],
                      ),
                      subtitle: Text(client.phone),
                      trailing: const Icon(Icons.arrow_forward_ios,
                          size: 16, color: Colors.redAccent),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                LedgerScreen(client: client),
                          ),
                        );
                      },
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
}
