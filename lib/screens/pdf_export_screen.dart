// lib/screens/pdf_export_screen.dart - v2.0 (Smart & Robust)
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import '../services/invoice_service.dart';

class PdfExportScreen extends StatefulWidget {
  // ✅ UPDATED: New, professional parameters
  final String customerName;
  final String invoiceNo;
  final DateTime date;
  final List<Map<String, dynamic>> items;
  final double billTotal;
  final double paidForThisBill;
  final double previousBalance;
  final double currentBalance;

  const PdfExportScreen({
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
  State<PdfExportScreen> createState() => _PdfExportScreenState();
}

class _PdfExportScreenState extends State<PdfExportScreen> with SingleTickerProviderStateMixin {
  // State
  bool _isGenerating = true;
  bool _isSuccess = false;
  String? _errorMessage;
  Uint8List? _pdfData;
  String? _filePath;

  // Animation
  late final AnimationController _animationController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    );
    _generatePdf();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _generatePdf() async {
    try {
      if (!mounted) return;
      setState(() {
        _isGenerating = true;
        _errorMessage = null;
      });

      // ✅ UPDATED: Pass all the new parameters to the invoice service
      final pdfData = await InvoiceService().buildPdf(
        customerName: widget.customerName,
        invoiceNo: widget.invoiceNo,
        date: widget.date,
        items: widget.items,
        billTotal: widget.billTotal,
        paidForThisBill: widget.paidForThisBill,
        previousBalance: widget.previousBalance,
        currentBalance: widget.currentBalance,
      );

      final tempDir = await getTemporaryDirectory();
      final fileName = 'invoice_${widget.invoiceNo}.pdf';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(pdfData);

      if (!mounted) return;
      setState(() {
        _pdfData = pdfData;
        _filePath = file.path;
        _isGenerating = false;
        _isSuccess = true;
      });

      _animationController.forward(from: 0.0);

    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _isSuccess = false;
        _errorMessage = "Failed to generate PDF. Please try again.\nError: ${e.toString()}";
      });
      _showErrorSnackbar(_errorMessage!);
    }
  }

  Future<void> _openPdf() async {
    if (_filePath == null) return;
    final result = await OpenFilex.open(_filePath!);
    if (result.type != ResultType.done) {
      _showMessage('Could not find an app to open PDF files.');
    }
  }

  Future<void> _sharePdf() async {
    if (_filePath == null) return;
    await Share.shareXFiles(
      [XFile(_filePath!)],
      text: 'Invoice ${widget.invoiceNo} for ${widget.customerName}',
    );
  }

  Future<void> _printPdf() async {
    if (_pdfData == null) return;
    await Printing.layoutPdf(
      onLayout: (format) async => _pdfData!,
      name: 'Invoice_${widget.invoiceNo}',
    );
  }

  Future<void> _saveToDownloads() async {
    if (_pdfData == null) return;
    try {
      Directory? downloadsDir;
      if (Platform.isAndroid) {
        downloadsDir = Directory('/storage/emulated/0/Download');
        if (!await downloadsDir.exists()) downloadsDir = await getExternalStorageDirectory();
      } else {
        downloadsDir = await getApplicationDocumentsDirectory();
      }

      if (downloadsDir == null) {
        _showMessage('Could not access downloads folder.');
        return;
      }

      final appDirName = 'DairyManagerInvoices';
      final appDir = Directory('${downloadsDir.path}/$appDirName');
      if (!await appDir.exists()) await appDir.create(recursive: true);

      final fileName = 'Invoice_${widget.invoiceNo}_${widget.customerName.replaceAll(' ', '_')}.pdf';
      final file = File('${appDir.path}/$fileName');
      await file.writeAsBytes(_pdfData!);

      _showMessage('Saved to Downloads/$appDirName', isSuccess: true);
    } catch (e) {
      _showMessage('Error saving PDF: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Invoice Export'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
        centerTitle: true,
      ),
      body: Center(child: _buildContent()),
    );
  }

  Widget _buildContent() {
    if (_isGenerating) {
      return _buildGeneratingView();
    } else if (_isSuccess) {
      return _buildSuccessView();
    } else {
      return _buildErrorView();
    }
  }

  Widget _buildGeneratingView() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 24),
        Text('Generating Invoice...', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        SizedBox(height: 8),
        Text('Please wait a moment', style: TextStyle(fontSize: 14, color: Colors.grey)),
      ],
    );
  }

  Widget _buildSuccessView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ScaleTransition(
            scale: _scaleAnimation,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.green.shade100, shape: BoxShape.circle),
              child: Icon(Icons.check_circle, size: 60, color: Colors.green.shade800),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Invoice Generated!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(widget.customerName, style: TextStyle(fontSize: 16, color: Colors.grey.shade700)),
          const SizedBox(height: 32),
          // Actions
          _buildActionButton(icon: Icons.open_in_new, label: 'Open PDF', onTap: _openPdf, color: Theme.of(context).primaryColor),
          const SizedBox(height: 12),
          _buildActionButton(icon: Icons.share, label: 'Share', onTap: _sharePdf, color: Colors.blue),
          const SizedBox(height: 12),
          _buildActionButton(icon: Icons.print, label: 'Print', onTap: _printPdf, color: Colors.orange),
          const SizedBox(height: 12),
          _buildActionButton(icon: Icons.download, label: 'Save to Device', onTap: _saveToDownloads, color: Colors.purple),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.red.shade100, shape: BoxShape.circle),
            child: Icon(Icons.error_outline, size: 60, color: Colors.red.shade800),
          ),
          const SizedBox(height: 24),
          const Text('Generation Failed', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? 'An unexpected error occurred.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _generatePdf,
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({required IconData icon, required String label, required VoidCallback onTap, required Color color}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: color),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          foregroundColor: color,
          backgroundColor: color.withOpacity(0.1),
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  void _showMessage(String message, {bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isSuccess ? Colors.green : Colors.black87,
    ));
  }

  void _showErrorSnackbar(String error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Error: $error'),
      backgroundColor: Colors.red,
      action: SnackBarAction(label: 'Retry', onPressed: _generatePdf),
    ));
  }
}