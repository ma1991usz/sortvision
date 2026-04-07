import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:share_plus/share_plus.dart';

const _bgColor = Color(0xFF1A1A2E);
const _surfaceColor = Color(0xFF16213E);
const _accentBlue = Color(0xFF4361EE);
const _accentGrey = Color(0xFF2D2D44);
const _textPrimary = Color(0xFFEEEEEE);
const _textSecondary = Color(0xFF8A8AB0);

const _polishMonths = [
  'sty',
  'lut',
  'mar',
  'kwi',
  'maj',
  'cze',
  'lip',
  'sie',
  'wrz',
  'paź',
  'lis',
  'gru',
];

class ScanDetailScreen extends StatefulWidget {
  final String filePath;
  const ScanDetailScreen({super.key, required this.filePath});

  @override
  State<ScanDetailScreen> createState() => _ScanDetailScreenState();
}

class _ScanDetailScreenState extends State<ScanDetailScreen>
    with SingleTickerProviderStateMixin {
  int _totalPages = 0;
  int _currentPage = 0;
  bool _pdfReady = false;
  bool _mounted = false;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) setState(() => _mounted = true);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _readDescription() {
    try {
      final txt = File(widget.filePath.replaceAll('.pdf', '.txt'));
      if (!txt.existsSync()) return '';
      return txt.readAsStringSync().trim();
    } catch (_) {
      return '';
    }
  }

  String _readOcr() {
    try {
      final ocrFile = File(widget.filePath.replaceAll('.pdf', '_ocr.txt'));
      if (!ocrFile.existsSync()) return '';
      return ocrFile.readAsStringSync().trim();
    } catch (_) {
      return '';
    }
  }

  String _formatTitle() {
    final dt = File(widget.filePath).lastModifiedSync();
    final month = _polishMonths[dt.month - 1];
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} $month ${dt.year}, $h:$min';
  }

  Future<void> _share() async {
    await Share.shareXFiles([XFile(widget.filePath)]);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceColor,
        title: const Text('Usuń skan', style: TextStyle(color: _textPrimary)),
        content: const Text(
          'Czy na pewno chcesz usunąć ten skan?',
          style: TextStyle(color: _textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Anuluj', style: TextStyle(color: _textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Usuń', style: TextStyle(color: Color(0xFFEF9A9A))),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await File(widget.filePath).delete();
      final txt = File(widget.filePath.replaceAll('.pdf', '.txt'));
      if (await txt.exists()) await txt.delete();
      final ocr = File(widget.filePath.replaceAll('.pdf', '_ocr.txt'));
      if (await ocr.exists()) await ocr.delete();
      if (mounted) Navigator.pop(context, true);
    }
  }

  Widget _buildAiTab(String description) {
    if (description.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  color: _textSecondary, size: 40),
              const SizedBox(height: 16),
              const Text(
                'Brak opisu AI',
                style: TextStyle(
                    color: _textSecondary,
                    fontSize: 16,
                    fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Przejdź do analizy'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accentBlue,
                  side: const BorderSide(color: _accentBlue),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        description,
        style: const TextStyle(
          color: _textPrimary,
          fontSize: 14,
          height: 1.65,
        ),
      ),
    );
  }

  Widget _buildOcrTab(String ocrText) {
    if (ocrText.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.text_fields_rounded,
                  color: _textSecondary, size: 40),
              const SizedBox(height: 16),
              const Text(
                'Brak tekstu OCR',
                style: TextStyle(
                    color: _textSecondary,
                    fontSize: 16,
                    fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 8),
              const Text(
                'OCR można wykonać podczas\nskanowania dokumentu',
                textAlign: TextAlign.center,
                style: TextStyle(color: _textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Kopiuj'),
              style: TextButton.styleFrom(
                foregroundColor: _accentBlue,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: ocrText));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Skopiowano tekst OCR'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _accentGrey,
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(
              ocrText,
              style: const TextStyle(
                color: _textPrimary,
                fontFamily: 'monospace',
                fontSize: 15,
                height: 1.7,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final description = _readDescription();
    final ocrText = _readOcr();

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        foregroundColor: _textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        title: Text(_formatTitle(), style: const TextStyle(fontSize: 15)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Udostępnij',
            onPressed: _share,
          ),
          IconButton(
            icon: const Icon(Icons.delete_rounded, color: Color(0xFFEF9A9A)),
            tooltip: 'Usuń',
            onPressed: _delete,
          ),
        ],
      ),
      body: Column(
        children: [
          // PDF - 45% ekranu
          ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: 200,
              maxHeight: MediaQuery.of(context).size.height * 0.45,
            ),
            child: Container(
              color: _bgColor,
              height: MediaQuery.of(context).size.height * 0.45,
              child: Stack(
                children: [
                  if (_mounted)
                    PDFView(
                      key: Key(widget.filePath),
                      filePath: widget.filePath,
                      enableSwipe: true,
                      swipeHorizontal: false,
                      autoSpacing: true,
                      pageFling: true,
                      fitPolicy: FitPolicy.BOTH,
                      fitEachPage: true,
                      pageSnap: true,
                      backgroundColor: _bgColor,
                      onRender: (pages) => setState(() {
                        _totalPages = pages ?? 0;
                        if (_currentPage == 0) _currentPage = 1;
                        _pdfReady = true;
                      }),
                      onPageChanged: (page, _) =>
                          setState(() => _currentPage = (page ?? 0) + 1),
                    ),
                  if (!_pdfReady)
                    const Center(
                      child: CircularProgressIndicator(color: _accentBlue),
                    ),
                  if (_pdfReady && _totalPages > 1)
                    Positioned(
                      bottom: 12,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: _surfaceColor.withAlpha(220),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '$_currentPage / $_totalPages',
                            style: const TextStyle(
                                color: _textPrimary, fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // TabBar - nie scrolluje sie
          Container(
            color: _surfaceColor,
            child: TabBar(
              controller: _tabController,
              indicatorColor: _accentBlue,
              indicatorWeight: 2.5,
              labelColor: _accentBlue,
              unselectedLabelColor: _textSecondary,
              labelStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 13),
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(
                  icon: Icon(Icons.auto_awesome_rounded, size: 18),
                  text: 'Opis AI',
                  iconMargin: EdgeInsets.only(bottom: 2),
                ),
                Tab(
                  icon: Icon(Icons.text_fields_rounded, size: 18),
                  text: 'Tekst OCR',
                  iconMargin: EdgeInsets.only(bottom: 2),
                ),
              ],
            ),
          ),
          // TabBarView - zajmuje reszte ekranu
          Expanded(
            child: SafeArea(
              top: false,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildAiTab(description),
                  _buildOcrTab(ocrText),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
