// lib/screens/invoice_preview_page.dart
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../services/invoice_service.dart';

class InvoicePreviewPage extends StatelessWidget {
  final String customerName;
  final int invoiceNo;
  final DateTime date;
  final List<Map<String, dynamic>> items;
  final double receivedAmount;

  const InvoicePreviewPage({
    super.key,
    required this.customerName,
    required this.invoiceNo,
    required this.date,
    required this.items,
    required this.receivedAmount,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invoice Preview')),
      body: PdfPreview(
        build: (format) => InvoiceService().buildPdf(
          companyName: 'YADAV PASHU AAHAR',
          customerName: customerName,
          invoiceNo: invoiceNo.toString(),
          date: date,
          items: items,
          receivedAmount: receivedAmount,
        ),
      ),
    );
  }
}
