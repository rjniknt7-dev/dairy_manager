// lib/screens/edit_client_screen.dart
import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/backup_service.dart';   // ✅ for Firestore sync
import '../models/client.dart';

class EditClientScreen extends StatefulWidget {
  final Client client;
  const EditClientScreen({Key? key, required this.client}) : super(key: key);

  @override
  State<EditClientScreen> createState() => _EditClientScreenState();
}

class _EditClientScreenState extends State<EditClientScreen> {
  final _formKey = GlobalKey<FormState>();
  final _db = DatabaseHelper();
  final _backup = BackupService(); // ✅

  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController    = TextEditingController(text: widget.client.name);
    _phoneController   = TextEditingController(text: widget.client.phone);
    _addressController = TextEditingController(text: widget.client.address);
  }

  Future<void> _updateClient() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final updated = Client(
      id: widget.client.id,
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      address: _addressController.text.trim(),
    );

    try {
      // 1️⃣ Update in local SQLite
      await _db.updateClientWithModel(updated);

      // 2️⃣ Try to push to Firestore (will queue / retry internally if offline)
      await _backup.upsertClient(updated);

      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Client updated successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Client')),
      body: _saving
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Client Name'),
                validator: (v) =>
                v == null || v.trim().isEmpty ? 'Enter a name' : null,
              ),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Phone Number'),
                keyboardType: TextInputType.phone,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Enter a phone number';
                  }
                  final digits = v.replaceAll(RegExp(r'\D'), '');
                  return digits.length < 10
                      ? 'Enter a valid phone number'
                      : null;
                },
              ),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(labelText: 'Address'),
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('Save Changes'),
                onPressed: _updateClient,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
