import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PDFService {
  static Future<Uint8List> buildPurchaseOrderPdf({
    required String date,
    required List<Map<String, dynamic>> totals,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          margin: const pw.EdgeInsets.all(32),
          theme: pw.ThemeData.withFont(
            // Use standard fonts that are already bundled with the pdf package
            base: pw.Font.helvetica(),
            bold: pw.Font.helveticaBold(),
          ),
        ),
        build: (context) => [
          // Company header
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'YADAV PASHU AAHAR',
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue800,
                ),
              ),
              pw.Text('Wholesaler: Arun Kumar Yadav (Owner)',
                  style: const pw.TextStyle(fontSize: 12)),
              pw.Text('Phone: 7250390636',
                  style: const pw.TextStyle(fontSize: 12)),
              pw.Text('Address: Katariya, Munger',
                  style: const pw.TextStyle(fontSize: 12)),
              pw.SizedBox(height: 12),
              pw.Divider(),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Text('Daily Purchase Order',
              style: pw.TextStyle(
                  fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.Text('Date: $date', style: const pw.TextStyle(fontSize: 14)),
          pw.SizedBox(height: 20),

          // Table of products/quantities
          pw.TableHelper.fromTextArray(
            headers: ['Product', 'Quantity'],
            data: totals
                .map((row) => [row['productName'], row['totalQty'].toString()])
                .toList(),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue100),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue900,
            ),
            rowDecoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
            ),
          ),

          pw.Spacer(),

          // Footer
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Generated on ${DateFormat.yMMMd().format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }
}
