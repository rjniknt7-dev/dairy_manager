// lib/screens/pdf_export_screen.dart
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../services/invoice_service.dart';

class PdfExportScreen extends StatefulWidget {
  final String customerName;
  final String invoiceNo;
  final DateTime date;
  final List<Map<String, dynamic>> items;
  final double receivedAmount;
  final double? ledgerRemaining;

  const PdfExportScreen({
    super.key,
    required this.customerName,
    required this.invoiceNo,
    required this.date,
    required this.items,
    required this.receivedAmount,
    this.ledgerRemaining,
  });

  @override
  State<PdfExportScreen> createState() => _PdfExportScreenState();
}

class _PdfExportScreenState extends State<PdfExportScreen> {
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _generateAndOpenPdf();
  }

  Future<void> _generateAndOpenPdf() async {
    try {
      final pdfData = await InvoiceService().buildPdf(
        customerName: widget.customerName,
        invoiceNo: widget.invoiceNo,
        date: widget.date,
        items: widget.items,
        receivedAmount: widget.receivedAmount,
        ledgerRemaining: widget.ledgerRemaining,
      );

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/invoice_${widget.invoiceNo}.pdf');
      await file.writeAsBytes(pdfData);

      await OpenFilex.open(file.path);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating PDF: $e')),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invoice PDF')),
      body: Center(
        child: isLoading
            ? Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Generating PDF...'),
          ],
        )
            : const Icon(Icons.check_circle, color: Colors.green, size: 80),
      ),
    );
  }
}
