import 'dart:typed_data';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';

class PDFService {
  /// Takes a date string and a list of {productName, totalQty} maps
  static Future<Uint8List> buildPurchaseOrderPdf({
    required String date,
    required List<Map<String, dynamic>> totals,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Center(
            child: pw.Text(
              'Daily Purchase Order',
              style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text('Date: $date', style: const pw.TextStyle(fontSize: 14)),
          pw.SizedBox(height: 20),
          pw.Table.fromTextArray(
            headers: ['Product', 'Quantity'],
            data: totals
                .map((row) => [row['productName'], row['totalQty'].toString()])
                .toList(),
            headerStyle: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
            cellStyle: const pw.TextStyle(fontSize: 12),
            border: null,
          ),
        ],
      ),
    );

    return pdf.save();
  }
}
