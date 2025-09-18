import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'home_screen.dart';                // adjust path if needed
import '../services/database_helper.dart'; // your local SQLite helper
import '../services/firestore_service.dart'; // your Firestore sync helper
import '../models/client.dart';            // example model to sync
import 'package:connectivity_plus/connectivity_plus.dart';




class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _mobileController = TextEditingController();
  final _passwordController = TextEditingController();
  final _auth = FirebaseAuth.instance;

  bool _loading = false;
  String? _error;

  String _mobileToEmail(String mobile) =>
      '${mobile.trim()}@dairymanager.com';

  Future<void> _login() async {
    if (_mobileController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      setState(() => _error = 'Enter mobile number and password');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _auth.signInWithEmailAndPassword(
        email: _mobileToEmail(_mobileController.text),
        password: _passwordController.text.trim(),
      );

      // ✅ After login, try syncing local data to Firestore
      await _syncIfOnline();

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message ?? 'Login failed');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    if (_mobileController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      setState(() => _error = 'Enter mobile number and password');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _auth.createUserWithEmailAndPassword(
        email: _mobileToEmail(_mobileController.text),
        password: _passwordController.text.trim(),
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message ?? 'Registration failed');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 🔁 Check connectivity and sync local SQLite data to Firestore
  Future<void> _syncIfOnline() async {
    final conn = await Connectivity().checkConnectivity();
    if (conn == ConnectivityResult.none) return;

    final db = DatabaseHelper();
    final fs = FirestoreService();

    // Example: sync all clients. Add similar blocks for products/bills/etc.
    final localClients = await db.getClients();
    if (localClients.isNotEmpty) {
      await fs.saveMultipleClients(localClients);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Login", style: TextStyle(fontSize: 32)),
              TextField(
                controller: _mobileController,
                decoration: const InputDecoration(labelText: "Mobile Number"),
                keyboardType: TextInputType.phone,
              ),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: "Password"),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              _loading
                  ? const CircularProgressIndicator()
                  : Column(
                children: [
                  ElevatedButton(
                    onPressed: _login,
                    child: const Text("Login"),
                  ),
                  TextButton(
                    onPressed: _register,
                    child: const Text("Register New Account"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
