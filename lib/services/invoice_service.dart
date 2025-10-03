// lib/services/invoice_service.dart
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class InvoiceService {
  Future<Uint8List> buildPdf({
    String companyName = 'YADAV PASHU AAHAR',
    String? logoAssetPath = 'assets/images/logo.png',
    required String customerName,
    required String invoiceNo,
    required DateTime date,
    required List<Map<String, dynamic>> items,
    required double receivedAmount,
    double? ledgerRemaining,
  }) async {
    final pdf = pw.Document();
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    // Load fonts
    final ttf = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
    );
    final ttfBold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
    );

    // Load logo
    Uint8List? logoBytes;
    try {
      if (logoAssetPath != null) {
        final bd = await rootBundle.load(logoAssetPath);
        logoBytes = bd.buffer.asUint8List();
      }
    } catch (_) {
      logoBytes = null;
    }
    final pw.ImageProvider? logoImage = logoBytes != null
        ? pw.MemoryImage(logoBytes)
        : null;

    double subtotal = 0;
    for (final i in items) {
      final q = (i['qty'] as num).toDouble();
      final p = (i['price'] as num).toDouble();
      subtotal += q * p;
    }
    final balance = subtotal - receivedAmount + (ledgerRemaining ?? 0);

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          margin: const pw.EdgeInsets.all(24),
          theme: pw.ThemeData.withFont(base: ttf, bold: ttfBold),
        ),
        build: (context) => [
          // Watermark
          pw.Stack(
            children: [
              pw.Positioned.fill(
                child: pw.Opacity(
                  opacity: 0.05,
                  child: pw.Transform.rotate(
                    angle: -0.4, // diagonal
                    child: pw.Center(
                      child: pw.Text(
                        'YADAV PASHU AAHAR',
                        style: pw.TextStyle(
                          fontSize: 80,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              pw.Column(
                children: [
                  // Header
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Row(
                        children: [
                          if (logoImage != null)
                            pw.Container(
                              width: 60,
                              height: 60,
                              child: pw.Image(logoImage),
                            ),
                          pw.SizedBox(width: 10),
                          pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                companyName,
                                style: pw.TextStyle(
                                  fontSize: 20,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.SizedBox(height: 2),
                              pw.Text(
                                'Phone: 9509496506',
                                style: pw.TextStyle(
                                  fontSize: 10,
                                  color: PdfColors.grey,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            'Tax Invoice',
                            style: pw.TextStyle(
                              fontSize: 16,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.SizedBox(height: 6),
                          pw.Text(
                            'Invoice No: $invoiceNo',
                            style: pw.TextStyle(fontSize: 10),
                          ),
                          pw.Text(
                            'Date: ${DateFormat('dd MMM yyyy').format(date)}',
                            style: pw.TextStyle(fontSize: 10),
                          ),
                        ],
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 16),

                  // Customer info
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Bill To:',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(customerName),
                        ],
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 16),

                  // Items table
                  pw.Container(
                    decoration: pw.BoxDecoration(
                      borderRadius: pw.BorderRadius.circular(8),
                      border: pw.Border.all(
                        color: PdfColors.grey300,
                        width: 0.5,
                      ),
                      color: PdfColors.white,
                    ),
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Table(
                      border: pw.TableBorder.symmetric(
                        inside: pw.BorderSide(
                          width: 0.3,
                          color: PdfColors.grey300,
                        ),
                      ),
                      columnWidths: {
                        0: const pw.FlexColumnWidth(4),
                        1: const pw.FixedColumnWidth(60),
                        2: const pw.FixedColumnWidth(80),
                        3: const pw.FixedColumnWidth(80),
                      },
                      children: [
                        // header
                        pw.TableRow(
                          decoration: pw.BoxDecoration(
                            color: PdfColors.grey300,
                          ),
                          children: [
                            _cell('Item', isHeader: true),
                            _cell('Qty', isHeader: true),
                            _cell('Price/Unit', isHeader: true),
                            _cell('Amount', isHeader: true),
                          ],
                        ),
                        // items
                        ...items.map((it) {
                          final qty = (it['qty'] as num).toDouble();
                          final price = (it['price'] as num).toDouble();
                          final total = qty * price;
                          return pw.TableRow(
                            children: [
                              _cell(it['name']),
                              _cell(
                                '${qty.toStringAsFixed(qty.truncateToDouble() == qty ? 0 : 2)}',
                              ),
                              _cell(currency.format(price)),
                              _cell(currency.format(total)),
                            ],
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 12),

                  // Totals
                  pw.Container(
                    width: double.infinity,
                    alignment: pw.Alignment.centerRight,
                    child: pw.Container(
                      width: 300,
                      decoration: pw.BoxDecoration(
                        borderRadius: pw.BorderRadius.circular(8),
                        border: pw.Border.all(
                          color: PdfColors.grey300,
                          width: 0.5,
                        ),
                        color: PdfColors.white,
                      ),
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Column(
                        children: [
                          _totalsRow('Sub Total', currency.format(subtotal)),
                          if (ledgerRemaining != null)
                            _totalsRow(
                              'Ledger Remaining',
                              currency.format(ledgerRemaining),
                            ),
                          _totalsRow(
                            'Received Amount',
                            currency.format(receivedAmount),
                          ),
                          _totalsRow(
                            'Balance',
                            currency.format(balance),
                            bold: true,
                            highlight: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 16),

                  // Footer
                  pw.Text(
                    'Terms & Conditions: Thank you for doing business with us.',
                    style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  pw.Widget _cell(String text, {bool isHeader = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 10 : 9,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  pw.Widget _totalsRow(
    String label,
    String value, {
    bool bold = false,
    bool highlight = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: highlight ? PdfColors.blue : PdfColors.black,
            ),
          ),
        ],
      ),
    );
  }
}
