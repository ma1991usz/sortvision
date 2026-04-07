import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../services/api_service.dart';
import 'ocr_screen.dart';
import 'pages_editor_screen.dart';
import 'scans_screen.dart';

const _bgColor = Color(0xFF1A1A2E);
const _surfaceColor = Color(0xFF16213E);
const _accentBlue = Color(0xFF4361EE);
const _accentGrey = Color(0xFF2D2D44);
const _textPrimary = Color(0xFFEEEEEE);
const _textSecondary = Color(0xFF8A8AB0);
const _accentGreen = Color(0xFF2ECC71);

class ResultScreen extends StatefulWidget {
  final String imagePath;
  final List<String>? imagePaths;

  const ResultScreen({
    super.key,
    required this.imagePath,
    this.imagePaths,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final _apiService = ApiService();
  bool _isLoading = false;
  bool _isOcrLoading = false;
  String _loadingStage = '';
  String? _analysisResult;
  String? _ocrResult;
  String? _error;
  List<String>? _imagePaths;

  @override
  void initState() {
    super.initState();
    _imagePaths = widget.imagePaths != null
        ? List<String>.from(widget.imagePaths!)
        : null;
  }

  Future<void> _openPagesEditor() async {
    if (_imagePaths == null) return;
    final result = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => PagesEditorScreen(imagePaths: _imagePaths!),
      ),
    );
    if (result != null && mounted) {
      setState(() => _imagePaths = result);
    }
  }

  Future<void> _analyzeDocument() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _analysisResult = null;
    });

    try {
      void onStage(String stage) {
        if (mounted) setState(() => _loadingStage = stage);
      }

      final paths = _imagePaths;
      final raw = (paths != null && paths.length > 1)
          ? await _apiService.analyzeMultiPage(paths, onStage: onStage)
          : await _apiService.analyzeDocument(widget.imagePath,
              onStage: onStage);
      if (mounted) {
        setState(() {
          _analysisResult = raw.trim();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _runOcr() async {
    setState(() {
      _isOcrLoading = true;
      _loadingStage = '';
    });
    try {
      final paths = _imagePaths;
      final result = (paths != null && paths.length > 1)
          ? await _apiService.analyzeMultiPageOCR(paths, onStage: (stage) {
              if (mounted) setState(() => _loadingStage = stage);
            })
          : await _apiService.analyzeDocumentOCR(widget.imagePath,
              onStage: (stage) {
              if (mounted) setState(() => _loadingStage = stage);
            });
      if (mounted) {
        setState(() {
          _isOcrLoading = false;
          _ocrResult = result.trim();
        });
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OcrScreen(text: result.trim()),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isOcrLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Błąd OCR: $e')),
        );
      }
    }
  }

  void _copyToClipboard() {
    if (_analysisResult == null) return;
    Clipboard.setData(ClipboardData(text: _analysisResult!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Skopiowano opis do schowka'),
        backgroundColor: _accentBlue,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _saveDocument() async {
    try {
      // Wczytaj czcionkę Noto Sans (potrzebna dla stopki z polskimi znakami)
      final regularData =
          await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
      final regularFont = pw.Font.ttf(regularData);

      // Przygotuj strony PDF
      final hasAnalysis = _analysisResult != null;
      final paths = _imagePaths ?? [widget.imagePath];

      final doc = pw.Document();
      for (int i = 0; i < paths.length; i++) {
        final imgBytes = await File(paths[i]).readAsBytes();
        final img = pw.MemoryImage(imgBytes);
        final isFirst = i == 0;
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.zero,
            build: (pw.Context ctx) => pw.Stack(
              children: [
                pw.Positioned.fill(
                  child: pw.Image(img, fit: pw.BoxFit.contain),
                ),
                if (hasAnalysis && isFirst)
                  pw.Positioned(
                    bottom: 8,
                    left: 0,
                    right: 0,
                    child: pw.Text(
                      'Przeanalizowano przez SortVision AI',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        font: regularFont,
                        fontSize: 8,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }

      // Zapisz do Documents/SortVision/
      final baseDir = await getApplicationDocumentsDirectory();
      final scanDir = Directory('${baseDir.path}/SortVision');
      if (!await scanDir.exists()) await scanDir.create(recursive: true);

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '')
          .replaceAll('-', '')
          .replaceAll('.', '')
          .substring(0, 15);
      final filePath = '${scanDir.path}/scan_$timestamp.pdf';
      await File(filePath).writeAsBytes(await doc.save());

      // Zapisz opis AI do pliku .txt (pusty string jeśli brak analizy)
      final txtPath = '${scanDir.path}/scan_$timestamp.txt';
      await File(txtPath).writeAsString(_analysisResult ?? '');

      // Zapisz OCR do pliku _ocr.txt jeśli wykonano OCR
      if (_ocrResult != null) {
        final ocrPath = '${scanDir.path}/scan_${timestamp}_ocr.txt';
        await File(ocrPath).writeAsString(_ocrResult!);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Zapisano: scan_$timestamp.pdf'),
          backgroundColor: _accentGreen,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Otwórz skany',
            textColor: Colors.white,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ScansScreen()),
              );
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Błąd zapisu: ${e.toString()}'),
          backgroundColor: const Color(0xFFB00020),
        ),
      );
    }
  }

  // ─── Result area ──────────────────────────────────────────────────────────

  Widget _buildResultArea() {
    if (_isLoading) {
      return SizedBox(
        key: const ValueKey('loading'),
        height: 120,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: _accentBlue),
              const SizedBox(height: 14),
              Text(
                _loadingStage.isNotEmpty
                    ? _loadingStage
                    : 'Analizowanie dokumentu...',
                style: const TextStyle(color: _textSecondary, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Container(
        key: const ValueKey('error'),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0x33B00020),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFB00020), width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Color(0xFFEF9A9A), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFFEF9A9A), fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    if (_analysisResult != null) {
      return Container(
        key: const ValueKey('result'),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: _surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _accentBlue.withAlpha(60), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded,
                    color: _accentBlue, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Opis dokumentu',
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy_rounded,
                      color: _textSecondary, size: 18),
                  tooltip: 'Kopiuj opis',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _copyToClipboard,
                ),
              ],
            ),
            const Divider(color: _accentGrey, height: 20),
            SelectableText(
              _analysisResult!,
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 15,
                height: 1.65,
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink(key: ValueKey('empty'));
  }

  @override
  Widget build(BuildContext context) {
    final analysisComplete = _analysisResult != null && !_isLoading;
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        foregroundColor: _textPrimary,
        elevation: 0,
        title: const Text('Podgląd dokumentu'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Przewijalna część – zdjęcie + wynik analizy
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  children: [
                    // Podgląd zdjęcia
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        height: 240,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: _surfaceColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _accentBlue.withAlpha(60),
                            width: 1.5,
                          ),
                        ),
                        child: widget.imagePath.isNotEmpty
                            ? Image.file(
                                File(widget.imagePath),
                                fit: BoxFit.contain,
                              )
                            : const Center(
                                child: Icon(
                                  Icons.broken_image_rounded,
                                  color: _textSecondary,
                                  size: 64,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_imagePaths != null && _imagePaths!.length > 1) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: _accentBlue.withAlpha(30),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: _accentBlue.withAlpha(80), width: 1),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.picture_as_pdf_rounded,
                                color: _accentBlue, size: 18),
                            const SizedBox(width: 10),
                            Text(
                              'PDF będzie zawierał ${_imagePaths!.length} stron',
                              style: const TextStyle(
                                  color: _accentBlue,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _accentBlue,
                            side:
                                const BorderSide(color: _accentBlue, width: 1),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: const Icon(Icons.edit_rounded, size: 15),
                          label: const Text('Edytuj strony',
                              style: TextStyle(fontSize: 13)),
                          onPressed: _openPagesEditor,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    // Wynik analizy z animacją
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SizeTransition(
                          sizeFactor: animation,
                          axisAlignment: -1,
                          child: child,
                        ),
                      ),
                      child: _buildResultArea(),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            // Przyciski – zawsze na dole
            Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 12, 20, MediaQuery.of(context).padding.bottom + 16),
              child: Column(
                children: [
                  // Przycisk Analizuj dokument / napis potwierdzenia + OCR
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 350),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                          child: analysisComplete
                              ? Container(
                                  key: const ValueKey('success-badge'),
                                  width: double.infinity,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color: _accentGreen.withAlpha(30),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: _accentGreen.withAlpha(120),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.check_circle_rounded,
                                          color: _accentGreen, size: 22),
                                      SizedBox(width: 10),
                                      Text(
                                        '✓ Analiza zakończona',
                                        style: TextStyle(
                                          color: _accentGreen,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : SizedBox(
                                  key: const ValueKey('analyze-btn'),
                                  width: double.infinity,
                                  height: 52,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _accentBlue,
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor:
                                          _accentBlue.withAlpha(120),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      elevation: 0,
                                    ),
                                    onPressed:
                                        _isLoading ? null : _analyzeDocument,
                                    icon: _isLoading
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.document_scanner_rounded),
                                    label: Text(
                                      _isLoading
                                          ? 'Analizowanie...'
                                          : 'Analizuj dokument',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 52,
                        height: 52,
                        child: Tooltip(
                          message: 'Pełny tekst OCR',
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _accentGreen,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor:
                                  _accentGreen.withAlpha(120),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              padding: EdgeInsets.zero,
                              elevation: 0,
                            ),
                            onPressed:
                                (_isLoading || _isOcrLoading) ? null : _runOcr,
                            child: _isOcrLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2),
                                  )
                                : const Icon(Icons.text_fields_rounded,
                                    color: Colors.white, size: 22),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Przyciski Zrób ponownie i Zapisz
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _textPrimary,
                              side: const BorderSide(
                                color: _accentGrey,
                                width: 1.5,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: _isLoading
                                ? null
                                : () => Navigator.pop(context),
                            icon: const Icon(Icons.refresh_rounded, size: 20),
                            label: const Text('Zrób ponownie'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _accentBlue,
                              side: const BorderSide(
                                color: _accentBlue,
                                width: 1.5,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: _isLoading ? null : _saveDocument,
                            icon: const Icon(Icons.save_rounded, size: 20),
                            label: const Text('Zapisz'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
