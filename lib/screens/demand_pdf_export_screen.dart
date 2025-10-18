// lib/screens/demand_pdf_export_screen.dart
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../services/pdf_service.dart';

class DemandPdfExportScreen extends StatefulWidget {
  final DateTime startDate;
  final DateTime endDate;
  final List<Map<String, dynamic>> productSummary;
  final double totalCost;
  final double totalQuantity;
  final bool isSingleDay;

  const DemandPdfExportScreen({
    super.key,
    required this.startDate,
    required this.endDate,
    required this.productSummary,
    required this.totalCost,
    required this.totalQuantity,
    this.isSingleDay = false,
  });

  @override
  State<DemandPdfExportScreen> createState() => _DemandPdfExportScreenState();
}

class _DemandPdfExportScreenState extends State<DemandPdfExportScreen>
    with SingleTickerProviderStateMixin {
  bool _isGenerating = true;
  bool _isSuccess = false;
  String? _errorMessage;
  Uint8List? _pdfData;
  File? _savedFile;

  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
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
      setState(() {
        _isGenerating = true;
        _errorMessage = null;
      });

      // Generate PDF using your PDFService
      final pdfData = await PDFService.buildDemandAnalysisPdf(
        startDate: widget.startDate,
        endDate: widget.endDate,
        productSummary: widget.productSummary,
        totalCost: widget.totalCost,
        totalQuantity: widget.totalQuantity,
      );

      // Save to temp directory
      final tempDir = await getTemporaryDirectory();
      final dateStr = DateFormat('yyyyMMdd').format(widget.startDate);
      final fileName = widget.isSingleDay
          ? 'demand_${dateStr}_${DateTime.now().millisecondsSinceEpoch}.pdf'
          : 'demand_analysis_${dateStr}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(pdfData);

      setState(() {
        _pdfData = pdfData;
        _savedFile = file;
        _isGenerating = false;
        _isSuccess = true;
      });

      _animationController.forward();

      // Auto-open after a short delay
      await Future.delayed(const Duration(milliseconds: 500));
      await _openPdf();
    } catch (e) {
      setState(() {
        _isGenerating = false;
        _isSuccess = false;
        _errorMessage = e.toString();
      });
      _showErrorSnackbar(e.toString());
    }
  }

  Future<void> _openPdf() async {
    if (_savedFile == null) return;

    try {
      final result = await OpenFilex.open(_savedFile!.path);
      if (result.type != ResultType.done) {
        _showMessage('Could not open PDF: ${result.message}');
      }
    } catch (e) {
      _showMessage('Error opening PDF: $e');
    }
  }

  Future<void> _sharePdf() async {
    if (_savedFile == null) return;

    try {
      final dateRange = widget.isSingleDay
          ? DateFormat('dd/MM/yyyy').format(widget.startDate)
          : '${DateFormat('dd/MM/yyyy').format(widget.startDate)} - ${DateFormat('dd/MM/yyyy').format(widget.endDate)}';

      await Share.shareXFiles(
        [XFile(_savedFile!.path)],
        text: 'Demand Analysis Report - $dateRange',
      );
    } catch (e) {
      _showMessage('Error sharing PDF: $e');
    }
  }

  Future<void> _printPdf() async {
    if (_pdfData == null) return;

    try {
      await Printing.layoutPdf(
        onLayout: (format) async => _pdfData!,
        name: 'Demand_Analysis_${DateFormat('yyyyMMdd').format(widget.startDate)}',
      );
    } catch (e) {
      _showMessage('Error printing PDF: $e');
    }
  }

  Future<void> _saveToDownloads() async {
    if (_pdfData == null) return;

    try {
      Directory? downloadsDir;
      if (Platform.isAndroid) {
        downloadsDir = Directory('/storage/emulated/0/Download');
        if (!await downloadsDir.exists()) {
          downloadsDir = await getExternalStorageDirectory();
        }
      } else {
        downloadsDir = await getApplicationDocumentsDirectory();
      }

      if (downloadsDir == null) {
        _showMessage('Could not access downloads folder');
        return;
      }

      final appDir = Directory('${downloadsDir.path}/DairyManager');
      if (!await appDir.exists()) {
        await appDir.create(recursive: true);
      }

      final dateStr = DateFormat('yyyyMMdd').format(widget.startDate);
      final fileName = widget.isSingleDay
          ? 'Demand_$dateStr.pdf'
          : 'Demand_Analysis_${dateStr}_${DateFormat('yyyyMMdd').format(widget.endDate)}.pdf';
      final file = File('${appDir.path}/$fileName');
      await file.writeAsBytes(_pdfData!);

      _showMessage('Saved to Downloads/DairyManager', isSuccess: true);
    } catch (e) {
      _showMessage('Error saving PDF: $e');
    }
  }

  void _showMessage(String message, {bool isSuccess = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isSuccess ? Icons.check_circle : Icons.info,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isSuccess ? Colors.green : Colors.grey.shade800,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(8),
      ),
    );
  }

  void _showErrorSnackbar(String error) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text('Error: $error')),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(8),
        action: SnackBarAction(
          label: 'Retry',
          textColor: Colors.white,
          onPressed: _generatePdf,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Demand Analysis Export',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            Text(
              widget.isSingleDay
                  ? DateFormat('dd/MM/yyyy').format(widget.startDate)
                  : '${DateFormat('dd/MM/yyyy').format(widget.startDate)} - ${DateFormat('dd/MM/yyyy').format(widget.endDate)}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: Center(
        child: _buildContent(),
      ),
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
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
              strokeWidth: 3,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Generating Report...',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Please wait a moment',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessView() {
    final totalProfit = widget.productSummary.fold<double>(
      0,
          (sum, p) => sum + (p['profit'] as num).toDouble(),
    );

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ScaleTransition(
            scale: _scaleAnimation,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle,
                size: 60,
                color: Colors.green.shade600,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Report Generated!',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              widget.isSingleDay
                  ? DateFormat('dd MMM yyyy').format(widget.startDate)
                  : '${DateFormat('dd MMM').format(widget.startDate)} - ${DateFormat('dd MMM yyyy').format(widget.endDate)}',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Analysis Details Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildDetailRow('Products:', '${widget.productSummary.length}'),
                const SizedBox(height: 8),
                _buildDetailRow('Total Quantity:', widget.totalQuantity.toStringAsFixed(1)),
                const SizedBox(height: 8),
                _buildDetailRow('Total Cost:', '₹${widget.totalCost.toStringAsFixed(2)}',
                    valueColor: Colors.orange),
                const SizedBox(height: 8),
                _buildDetailRow('Total Profit:', '₹${totalProfit.toStringAsFixed(2)}',
                    valueColor: totalProfit >= 0 ? Colors.green : Colors.red),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Action Buttons Grid
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: Icons.open_in_new,
                  label: 'Open',
                  onTap: _openPdf,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.share,
                  label: 'Share',
                  onTap: _sharePdf,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: Icons.print,
                  label: 'Print',
                  onTap: _printPdf,
                  color: Colors.purple,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.download,
                  label: 'Save',
                  onTap: _saveToDownloads,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
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
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.error_outline,
              size: 60,
              color: Colors.red.shade600,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Generation Failed',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? 'An unexpected error occurred',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _generatePdf,
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade600,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: valueColor ?? Colors.grey.shade800,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.green.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}