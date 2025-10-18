// lib/screens/ledger_screen.dart - v2.0 (Intelligent & Polished)
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_helper.dart';
import '../models/client.dart';
import '../models/ledger_entry.dart';
import 'bill_details_screen.dart';
import 'add_payment_screen.dart'; // Import the new screen

class LedgerScreen extends StatefulWidget {
  final Client client;
  const LedgerScreen({super.key, required this.client});

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  final db = DatabaseHelper();
  List<LedgerEntry> _entries = [];
  List<Map<String, dynamic>> _ledgerWithBalance = [];
  bool _loading = true;
  double _finalBalance = 0.0;

  final _dateFmt = DateFormat('dd MMM yyyy, hh:mm a');
  final _currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    _loadLedger();
  }

  Future<void> _loadLedger() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final list = await db.getLedgerEntriesByClient(widget.client.id!);
      final balance = await db.getClientBalance(widget.client.id!);
      if (mounted) {
        setState(() {
          _entries = list;
          _finalBalance = balance;
          _calculateRunningBalances();
          _loading = false;
        });
      }
    } catch (e) {
      _showSnack('Failed to load ledger: $e', isError: true);
      if (mounted) setState(() => _loading = false);
    }
  }

  // ✅ NEW: Calculates running balance for each transaction
  void _calculateRunningBalances() {
    double runningBal = 0;
    List<Map<String, dynamic>> processedEntries = [];
    // Entries are sorted by date ASC from the DB, which is perfect for this calculation
    for (var entry in _entries) {
      if (entry.type == 'bill') {
        runningBal += entry.amount;
      } else { // 'payment', 'credit', 'adjustment'
        runningBal -= entry.amount;
      }
      processedEntries.add({'entry': entry, 'balance': runningBal});
    }
    // Reverse the list so the newest items are displayed at the top
    _ledgerWithBalance = processedEntries.reversed.toList();
  }

  Future<void> _navigateToAddPayment() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddPaymentScreen(preselectedClientId: widget.client.id),
      ),
    );
    if (result == true) {
      _loadLedger(); // Reload data if a payment was added
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(widget.client.name),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _loadLedger,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildBalanceCard()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'TRANSACTION HISTORY',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ),
            _buildLedgerList(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _navigateToAddPayment,
        label: const Text('Add Payment'),
        icon: const Icon(Icons.add),
        backgroundColor: Colors.green,
      ),
    );
  }

  Widget _buildBalanceCard() {
    bool hasDue = _finalBalance > 0;
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      shadowColor: (hasDue ? Colors.red : Colors.green).withOpacity(0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: hasDue
                ? [Colors.red.shade700, Colors.red.shade400]
                : [Colors.green.shade700, Colors.green.shade400],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasDue ? 'Total Amount Due' : 'Advance Credit',
              style: const TextStyle(fontSize: 14, color: Colors.white70),
            ),
            const SizedBox(height: 4),
            Text(
              _currencyFormat.format(_finalBalance.abs()),
              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLedgerList() {
    if (_entries.isEmpty) {
      return const SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.receipt_long, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text('No transactions found.', style: TextStyle(fontSize: 18, color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
            (context, index) {
          final item = _ledgerWithBalance[index];
          final LedgerEntry entry = item['entry'];
          final double balanceAfter = item['balance'];
          final isDebit = entry.type == 'bill';

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                backgroundColor: (isDebit ? Colors.red : Colors.green).withOpacity(0.1),
                child: Icon(
                  isDebit ? Icons.arrow_upward : Icons.arrow_downward,
                  color: isDebit ? Colors.red : Colors.green,
                  size: 20,
                ),
              ),
              title: Text(
                entry.note ?? (isDebit ? 'Bill Generated' : 'Payment Received'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _dateFmt.format(entry.date),
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isDebit ? '+' : '-'}${_currencyFormat.format(entry.amount)}',
                    style: TextStyle(color: isDebit ? Colors.red : Colors.green, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _currencyFormat.format(balanceAfter),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
              ),
              onTap: () {
                if (isDebit && entry.billId != null) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => BillDetailsScreen(billId: entry.billId!)));
                }
              },
            ),
          );
        },
        childCount: _ledgerWithBalance.length,
      ),
    );
  }
}