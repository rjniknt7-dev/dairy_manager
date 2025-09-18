import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/backup_service.dart';
import '../models/client.dart';
import 'ledger_screen.dart';

class LedgerBookScreen extends StatefulWidget {
  const LedgerBookScreen({super.key});

  @override
  State<LedgerBookScreen> createState() => _LedgerBookScreenState();
}

class _LedgerBookScreenState extends State<LedgerBookScreen> {
  final db = DatabaseHelper();
  final BackupService _backup = BackupService();

  List<Client> _clients = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  Future<void> _loadClients() async {
    setState(() => _loading = true);
    try {
      final list = await db.getClients();

      // 🔄 Backup all clients in parallel but don't block UI on failure
      await Future.wait(list.map((c) async {
        try {
          await _backup.backupClient(c);
        } catch (_) {
          // ignore individual backup errors to keep UI responsive
        }
      }));

      if (mounted) setState(() => _clients = list);
    } catch (e) {
      // Show data even if backup fails
      if (mounted) {
        setState(() {
          _clients = [];
        });
        _showSnack('Failed to load clients: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ledger Book'),
        backgroundColor: Colors.redAccent, // keep your accent if desired
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _clients.isEmpty
          ? const Center(child: Text('No clients found'))
          : RefreshIndicator(
        onRefresh: _loadClients,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: _clients.length,
          itemBuilder: (ctx, i) {
            final client = _clients[i];
            return Card(
              margin: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.redAccent,
                  child: Text(
                    client.name.isNotEmpty
                        ? client.name[0].toUpperCase()
                        : '?',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                title: Text(
                  client.name,
                  style:
                  const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(client.phone),
                trailing: const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.redAccent,
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LedgerScreen(client: client),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
