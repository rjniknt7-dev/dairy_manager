// lib/services/pdf_service.dart
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PDFService {
  // Your existing method
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

  // NEW METHOD: Demand Analysis with Cost Report
  static Future<Uint8List> buildDemandAnalysisPdf({
    required DateTime startDate,
    required DateTime endDate,
    required List<Map<String, dynamic>> productSummary,
    required double totalCost,
    required double totalQuantity,
  }) async {
    final pdf = pw.Document();

    // Calculate totals
    double totalRevenue = 0;
    double totalProfit = 0;
    for (var product in productSummary) {
      totalRevenue += (product['totalRevenue'] as num).toDouble();
      totalProfit += (product['profit'] as num).toDouble();
    }

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          margin: const pw.EdgeInsets.all(32),
          theme: pw.ThemeData.withFont(
            base: pw.Font.helvetica(),
            bold: pw.Font.helveticaBold(),
          ),
        ),
        build: (context) => [
          // Company Header
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
              pw.Divider(thickness: 2),
            ],
          ),

          pw.SizedBox(height: 15),

          // Report Title
          pw.Text(
            'DEMAND ANALYSIS REPORT',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue900,
            ),
          ),

          pw.SizedBox(height: 8),

          // Period
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.blue50,
              borderRadius: pw.BorderRadius.circular(5),
            ),
            child: pw.Text(
              'Period: ${DateFormat('dd/MM/yyyy').format(startDate)} - ${DateFormat('dd/MM/yyyy').format(endDate)}',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),

          pw.SizedBox(height: 20),

          // Summary Boxes
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _buildSummaryBox('Total Products', productSummary.length.toString()),
              _buildSummaryBox('Total Quantity', totalQuantity.toStringAsFixed(1)),
              _buildSummaryBox('Total Cost', '₹${totalCost.toStringAsFixed(2)}'),
            ],
          ),

          pw.SizedBox(height: 20),

          // Main Table
          pw.Text(
            'Product-wise Cost Analysis',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),

          pw.SizedBox(height: 10),

          pw.Table.fromTextArray(
            headers: ['Product', 'Qty', 'C.P.', 'Cost', 'S.P.', 'Revenue', 'Profit'],
            headerStyle: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.blue800,
            ),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellHeight: 25,
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
              6: pw.Alignment.centerRight,
            },
            data: [
              ...productSummary.map((product) => [
                product['productName'] ?? '',
                product['totalQuantity'].toStringAsFixed(1),
                '₹${product['costPrice'].toStringAsFixed(2)}',
                '₹${product['totalCost'].toStringAsFixed(2)}',
                '₹${product['sellingPrice'].toStringAsFixed(2)}',
                '₹${product['totalRevenue'].toStringAsFixed(2)}',
                '₹${product['profit'].toStringAsFixed(2)}',
              ]).toList(),
              // Total Row
              [
                'TOTAL',
                totalQuantity.toStringAsFixed(1),
                '',
                '₹${totalCost.toStringAsFixed(2)}',
                '',
                '₹${totalRevenue.toStringAsFixed(2)}',
                '₹${totalProfit.toStringAsFixed(2)}',
              ],
            ],
            rowDecoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.5, color: PdfColors.grey300)),
            ),
          ),

          pw.SizedBox(height: 20),

          // Profit Summary
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: totalProfit >= 0 ? PdfColors.green50 : PdfColors.red50,
              borderRadius: pw.BorderRadius.circular(5),
              border: pw.Border.all(
                color: totalProfit >= 0 ? PdfColors.green : PdfColors.red,
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Total Profit/Loss:',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  '₹${totalProfit.toStringAsFixed(2)}',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: totalProfit >= 0 ? PdfColors.green900 : PdfColors.red900,
                  ),
                ),
              ],
            ),
          ),

          pw.Spacer(),

          // Footer
          pw.Divider(),
          pw.SizedBox(height: 5),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Generated on ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey),
              ),
              pw.Text(
                'Page ${context.pageNumber}',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey),
              ),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  // Helper method for summary boxes
  static pw.Widget _buildSummaryBox(String label, String value) {
    return pw.Container(
      width: 150,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(5),
        border: pw.Border.all(color: PdfColors.grey400),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey700,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue900,
            ),
          ),
        ],
      ),
    );
  }
}