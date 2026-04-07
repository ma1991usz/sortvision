import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'scan_detail_screen.dart';

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

class ScansScreen extends StatefulWidget {
  const ScansScreen({super.key});

  @override
  State<ScansScreen> createState() => _ScansScreenState();
}

class _ScansScreenState extends State<ScansScreen> {
  List<File> _scans = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadScans();
  }

  Future<void> _loadScans() async {
    setState(() => _loading = true);
    try {
      final baseDir = await getApplicationDocumentsDirectory();
      final scanDir = Directory('${baseDir.path}/SortVision');
      if (await scanDir.exists()) {
        final files = await scanDir
            .list()
            .where((e) => e is File && e.path.endsWith('.pdf'))
            .cast<File>()
            .toList();
        files.sort(
            (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
        setState(() {
          _scans = files;
          _loading = false;
        });
      } else {
        setState(() {
          _scans = [];
          _loading = false;
        });
      }
    } catch (_) {
      setState(() {
        _scans = [];
        _loading = false;
      });
    }
  }

  // ─── Pomocnicze ─────────────────────────────────────────────────────────

  File _txtFor(File pdfFile) => File(pdfFile.path.replaceAll('.pdf', '.txt'));

  String _readDescription(File pdfFile) {
    try {
      final txt = _txtFor(pdfFile);
      if (!txt.existsSync()) return '';
      return txt.readAsStringSync().trim();
    } catch (_) {
      return '';
    }
  }

  // ─── Akcje ────────────────────────────────────────────────────────────────

  Future<void> _delete(File file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceColor,
        title: const Text('Usuń skan', style: TextStyle(color: _textPrimary)),
        content: Text(
          'Czy na pewno chcesz usunąć "${file.uri.pathSegments.last}"?',
          style: const TextStyle(color: _textSecondary),
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
      await file.delete();
      final txt = _txtFor(file);
      if (await txt.exists()) await txt.delete();
      await _loadScans();
    }
  }

  Future<void> _share(File file) async {
    await Share.shareXFiles([XFile(file.path)]);
  }

  void _openPdf(File file) async {
    final deleted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ScanDetailScreen(filePath: file.path),
      ),
    );
    if (deleted == true) _loadScans();
  }

  void _showOptions(File file) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _accentGrey,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text(
                file.uri.pathSegments.last,
                style: const TextStyle(
                  color: _textSecondary,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ListTile(
              leading:
                  const Icon(Icons.open_in_new_rounded, color: _accentBlue),
              title:
                  const Text('Otwórz', style: TextStyle(color: _textPrimary)),
              onTap: () {
                Navigator.pop(context);
                _openPdf(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_rounded, color: _accentBlue),
              title: const Text('Udostępnij',
                  style: TextStyle(color: _textPrimary)),
              onTap: () {
                Navigator.pop(context);
                _share(file);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_rounded, color: Color(0xFFEF9A9A)),
              title: const Text('Usuń',
                  style: TextStyle(color: Color(0xFFEF9A9A))),
              onTap: () {
                Navigator.pop(context);
                _delete(file);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _formatSize(File file) {
    final bytes = file.lengthSync();
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  String _formatDate(File file) {
    final dt = file.lastModifiedSync();
    final month = _polishMonths[dt.month - 1];
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} $month ${dt.year}, $h:$min';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        foregroundColor: _textPrimary,
        elevation: 0,
        title: const Text('Zapisane skany'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Odśwież',
            onPressed: _loadScans,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _accentBlue),
            )
          : _scans.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  color: _accentBlue,
                  backgroundColor: _surfaceColor,
                  onRefresh: _loadScans,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: _scans.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _buildScanTile(_scans[i]),
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open_rounded,
              size: 72, color: _accentGrey.withAlpha(180)),
          const SizedBox(height: 16),
          const Text(
            'Brak zapisanych skanów',
            style: TextStyle(color: _textSecondary, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            'Przeanalizuj dokument i użyj przycisku\n„Zapisz" aby go tu zapisać.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _textSecondary, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildScanTile(File file) {
    final description = _readDescription(file);
    final hasDesc = description.isNotEmpty;

    return GestureDetector(
      onTap: () => _openPdf(file),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _surfaceColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _accentBlue.withAlpha(50), width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Lewa: miniaturka PDF ────────────────────────────────────
            _PdfThumbnail(filePath: file.path),
            const SizedBox(width: 12),

            // ── Prawa: treść (2/3 szerokości) ─────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatDate(file),
                              style: const TextStyle(
                                color: _textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _formatSize(file),
                              style: const TextStyle(
                                color: _textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _showOptions(file),
                        behavior: HitTestBehavior.opaque,
                        child: const Padding(
                          padding: EdgeInsets.only(left: 8, top: 2),
                          child: Icon(Icons.more_vert_rounded,
                              color: _textSecondary, size: 20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    hasDesc ? description : 'Brak opisu AI',
                    style: TextStyle(
                      color: hasDesc
                          ? _textSecondary
                          : _textSecondary.withAlpha(130),
                      fontSize: 13,
                      height: 1.5,
                      fontStyle: hasDesc ? FontStyle.normal : FontStyle.italic,
                    ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
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

// ─── Miniaturka PDF ───────────────────────────────────────────────────────────

class _PdfThumbnail extends StatefulWidget {
  final String filePath;
  const _PdfThumbnail({required this.filePath});

  @override
  State<_PdfThumbnail> createState() => _PdfThumbnailState();
}

class _PdfThumbnailState extends State<_PdfThumbnail> {
  bool _hasError = false;
  bool _ready = false;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 64,
        height: 80,
        child: _hasError
            ? _iconFallback()
            : Stack(
                fit: StackFit.expand,
                children: [
                  IgnorePointer(
                    child: PDFView(
                      filePath: widget.filePath,
                      autoSpacing: false,
                      enableSwipe: false,
                      pageSnap: false,
                      backgroundColor: const Color(0xFF0D1B2E),
                      onRender: (_) {
                        if (mounted) setState(() => _ready = true);
                      },
                      onError: (_) {
                        if (mounted) setState(() => _hasError = true);
                      },
                    ),
                  ),
                  if (!_ready) _iconFallback(),
                ],
              ),
      ),
    );
  }

  Widget _iconFallback() {
    return Container(
      color: _accentBlue.withAlpha(25),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.picture_as_pdf_rounded, color: _accentBlue, size: 30),
          SizedBox(height: 4),
          Text(
            'PDF',
            style: TextStyle(
              color: _accentBlue,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
