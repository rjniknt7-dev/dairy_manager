import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';      // for PdfPreview
import '../services/invoice_service.dart';    // your existing service

class PdfExportScreen extends StatefulWidget {
  const PdfExportScreen({Key? key}) : super(key: key);

  @override
  State<PdfExportScreen> createState() => _PdfExportScreenState();
}

class _PdfExportScreenState extends State<PdfExportScreen> {
  late Future<Uint8List> _pdfFuture;

  @override
  void initState() {
    super.initState();

    // TODO: Replace demo data with real values from SQLite/Firestore.
    final demoItems = [
      {'name': 'Cattle Feed', 'qty': 5.0, 'price': 320.0, 'gst': '5%'},
      {'name': 'Mineral Mix', 'qty': 2.0, 'price': 450.0, 'gst': '12%'},
    ];

    _pdfFuture = InvoiceService().buildPdf(
      companyName: 'YADAV PASHU AAHAR',
      customerName: 'Demo Customer',
      invoiceNo: 'INV-1001',
      date: DateTime.now(),
      items: demoItems,
      receivedAmount: 1000.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invoice Preview')),
      body: FutureBuilder<Uint8List>(
        future: _pdfFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final pdfBytes = snapshot.data!;
          return PdfPreview(
            build: (format) async => pdfBytes,
            allowPrinting: true,
            allowSharing: true,
            canChangePageFormat: false,
            pdfFileName: 'invoice_${DateTime.now().millisecondsSinceEpoch}.pdf',
          );
        },
      ),
    );
  }
}
