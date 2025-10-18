// lib/services/invoice_service.dart
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class InvoiceService {
  // ✅ UPDATED: Accepts new, more descriptive parameters for a professional invoice.
  Future<Uint8List> buildPdf({
    String companyName = 'YADAV PASHU AAHAR',
    String? logoAssetPath = 'assets/images/logo.png',
    required String customerName,
    required String invoiceNo,
    required DateTime date,
    required List<Map<String, dynamic>> items,
    required double billTotal,
    required double paidForThisBill,
    required double previousBalance,
    required double currentBalance,
  }) async {
    final pdf = pw.Document();
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    // Load fonts
    final ttf = await pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    final ttfBold = await pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));

    // Load logo
    pw.ImageProvider? logoImage;
    if (logoAssetPath != null) {
      try {
        final bd = await rootBundle.load(logoAssetPath);
        logoImage = pw.MemoryImage(bd.buffer.asUint8List());
      } catch (e) {
        print("Could not load logo: $e");
        logoImage = null;
      }
    }

    pdf.addPage(
      pw.Page(
        pageTheme: pw.PageTheme(
          margin: const pw.EdgeInsets.all(36),
          theme: pw.ThemeData.withFont(base: ttf, bold: ttfBold),
        ),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // 1. Header
              _buildHeader(companyName, logoImage, invoiceNo, date),
              pw.SizedBox(height: 30),

              // 2. Customer Info
              _buildCustomerInfo(customerName),
              pw.SizedBox(height: 20),

              // 3. Items Table
              _buildItemsTable(items, currency),
              pw.SizedBox(height: 20),

              // 4. Totals Section (Right Aligned)
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 2,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Thank you for your business!', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontStyle: pw.FontStyle.italic)),
                        pw.SizedBox(height: 5),
                        pw.Text('Terms & Conditions: Payments are due within 15 days.', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 20),
                  pw.Expanded(
                    flex: 3,
                    child: _buildTotals(currency, billTotal, paidForThisBill, previousBalance, currentBalance),
                  ),
                ],
              ),
              pw.Spacer(),

              // 5. Footer
              _buildFooter(),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  // --- WIDGET BUILDER HELPERS ---

  pw.Widget _buildHeader(String companyName, pw.ImageProvider? logoImage, String invoiceNo, DateTime date) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Row(
          children: [
            if (logoImage != null) pw.Image(logoImage, width: 60, height: 60),
            if (logoImage != null) pw.SizedBox(width: 10),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(companyName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 20)),
                pw.Text('Phone: 9509496506', style: const pw.TextStyle(fontSize: 10)),
              ],
            ),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('INVOICE', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 24, color: PdfColors.grey700)),
            pw.Text('No: $invoiceNo', style: const pw.TextStyle(fontSize: 10)),
            pw.Text('Date: ${DateFormat('dd MMM yyyy').format(date)}', style: const pw.TextStyle(fontSize: 10)),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildCustomerInfo(String customerName) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('BILL TO:', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
        pw.Text(customerName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
      ],
    );
  }

  pw.Widget _buildItemsTable(List<Map<String, dynamic>> items, NumberFormat currency) {
    final headers = ['DESCRIPTION', 'QTY', 'UNIT PRICE', 'TOTAL'];

    final data = items.map((item) {
      final qty = (item['qty'] as num).toDouble();
      final price = (item['price'] as num).toDouble();
      final total = qty * price;
      return [
        item['name'],
        qty.toStringAsFixed(qty.truncateToDouble() == qty ? 0 : 2),
        currency.format(price),
        currency.format(total),
      ];
    }).toList();

    return pw.Table.fromTextArray(
      headers: headers,
      data: data,
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
      cellStyle: const pw.TextStyle(fontSize: 10),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerRight,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
      },
      columnWidths: {
        0: const pw.FlexColumnWidth(4),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(2),
        3: const pw.FlexColumnWidth(2),
      },
    );
  }

  // ✅ UPDATED: This now uses the new parameters to create a clear summary.
  pw.Widget _buildTotals(NumberFormat currency, double billTotal, double paidForThisBill, double previousBalance, double currentBalance) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        _totalsRow('This Bill Total', currency.format(billTotal)),
        _totalsRow('Previous Balance', currency.format(previousBalance)),
        pw.Divider(color: PdfColors.grey400, height: 10),
        _totalsRow('Total Amount Due', currency.format(previousBalance + billTotal), bold: true),
        pw.SizedBox(height: 10),
        _totalsRow('Payment Received (This Bill)', currency.format(paidForThisBill), color: PdfColors.green),
        pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: const pw.BoxDecoration(
            color: PdfColors.grey200,
          ),
          child: _totalsRow(
            'NEW OUTSTANDING BALANCE',
            currency.format(currentBalance),
            bold: true,
            size: 14,
          ),
        ),
      ],
    );
  }

  pw.Widget _totalsRow(String label, String value, {bool bold = false, double size = 12, PdfColor color = PdfColors.black}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, fontSize: size)),
        pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: size, color: color)),
      ],
    );
  }

  pw.Widget _buildFooter() {
    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey, width: 1)),
      ),
      padding: const pw.EdgeInsets.only(top: 10),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            'YADAV PASHU AAHAR - Computer Generated Invoice',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
          ),
        ],
      ),
    );
  }
}