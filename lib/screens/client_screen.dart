import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../models/client.dart';
import 'ledger_screen.dart';
import '../services/backup_service.dart';

class ClientScreen extends StatefulWidget {
  const ClientScreen({Key? key}) : super(key: key);

  @override
  State<ClientScreen> createState() => _ClientScreenState();
}

class _ClientScreenState extends State<ClientScreen> {
  final _searchController = TextEditingController();
  final DatabaseHelper db = DatabaseHelper();
  final BackupService _backup = BackupService();

  List<Client> _clients = [];
  List<Client> _filteredClients = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadClients();
    _searchController.addListener(_filterClients);
  }

  Future<void> _loadClients() async {
    final clients = await db.getClients();
    if (!mounted) return;
    setState(() {
      _clients = clients;
      _filteredClients = clients;
      _loading = false;
    });
  }

  void _filterClients() {
    final q = _searchController.text.toLowerCase();
    setState(() {
      _filteredClients = _clients
          .where((c) => c.name.toLowerCase().contains(q))
          .toList();
    });
  }

  Future<void> _deleteClient(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Client'),
        content: const Text(
            'Are you sure you want to permanently delete this client?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await db.deleteClient(id);
    await _backup.backupClients(); // keep Firestore in sync
    if (mounted) _loadClients();
  }

  /// Dialog to add or edit a client, with duplicate-name check
  Future<void> _showAddEditDialog({Client? client}) async {
    final nameCtrl = TextEditingController(text: client?.name ?? '');
    final phoneCtrl = TextEditingController(text: client?.phone ?? '');
    final addressCtrl = TextEditingController(text: client?.address ?? '');
    final formKey = GlobalKey<FormState>();
    final isEditing = client != null;

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isEditing ? 'Edit Client' : 'Add Client'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Enter name' : null,
                ),
                TextFormField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  keyboardType: TextInputType.phone,
                  validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Enter phone' : null,
                ),
                TextFormField(
                  controller: addressCtrl,
                  decoration: const InputDecoration(labelText: 'Address'),
                  validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Enter address' : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            child: Text(isEditing ? 'Update' : 'Add'),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              final newName = nameCtrl.text.trim();
              final nameExists = _clients.any((c) =>
              c.name.toLowerCase() == newName.toLowerCase() &&
                  c.id != client?.id);

              if (!isEditing && nameExists) {
                _showSnack('Client already exists');
                return;
              }

              final newClient = Client(
                id: client?.id,
                name: newName,
                phone: phoneCtrl.text.trim(),
                address: addressCtrl.text.trim(),
              );

              try {
                if (isEditing) {
                  await db.updateClient(newClient);
                } else {
                  await db.insertClient(newClient);
                }
              } on Exception catch (e) {
                // Handle SQLite unique constraint
                if (e.toString().contains('UNIQUE')) {
                  _showSnack('Client already exists');
                  return;
                }
                rethrow;
              }

              await _backup.backupClients(); // Firestore sync

              if (mounted) {
                Navigator.pop(context);
                _loadClients();
              }
            },
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registered Clients')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditDialog(),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search by name',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: _filteredClients.isEmpty
                ? const Center(child: Text('No clients found'))
                : ListView.builder(
              itemCount: _filteredClients.length,
              itemBuilder: (context, index) {
                final c = _filteredClients[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  child: ListTile(
                    title: Text(c.name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Phone: ${c.phone}'),
                        Text('Address: ${c.address}'),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.account_balance_wallet,
                            color: Colors.blue,
                          ),
                          tooltip: "Ledger",
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    LedgerScreen(client: c),
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete,
                              color: Colors.red),
                          onPressed: () => _deleteClient(c.id!),
                        ),
                      ],
                    ),
                    onTap: () => _showAddEditDialog(client: c),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
