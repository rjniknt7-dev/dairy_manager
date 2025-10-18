// lib/screens/invoice_preview_page.dart
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../services/invoice_service.dart';

class InvoicePreviewPage extends StatelessWidget {
  // ✅ UPDATED to accept all required data for a professional invoice
  final String customerName;
  final String invoiceNo; // Changed to String for consistency (e.g., 'INV-123')
  final DateTime date;
  final List<Map<String, dynamic>> items;
  final double billTotal;
  final double paidForThisBill;
  final double previousBalance;
  final double currentBalance;

  const InvoicePreviewPage({
    super.key,
    required this.customerName,
    required this.invoiceNo,
    required this.date,
    required this.items,
    required this.billTotal,
    required this.paidForThisBill,
    required this.previousBalance,
    required this.currentBalance,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Invoice Preview: $invoiceNo')),
      body: PdfPreview(
        // ✅ UPDATED to pass all new parameters to the buildPdf method
        build: (format) => InvoiceService().buildPdf(
          companyName: 'YADAV PASHU AAHAR', // You can centralize this
          customerName: customerName,
          invoiceNo: invoiceNo,
          date: date,
          items: items,
          billTotal: billTotal,
          paidForThisBill: paidForThisBill,
          previousBalance: previousBalance,
          currentBalance: currentBalance,
        ),
        // Optional: Add some nice preview actions
        allowSharing: true,
        allowPrinting: true,
        canChangePageFormat: false,
        canChangeOrientation: false,
        actions: [
          PdfPreviewAction(
            icon: const Icon(Icons.save_alt),
            onPressed: (context, build, pageFormat) {
              // You can add save logic here if you want, similar to PdfExportScreen
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Save functionality can be added here!')),
              );
            },
          ),
        ],
      ),
    );
  }
}