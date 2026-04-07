import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

const _bgColor = Color(0xFF1A1A2E);
const _surfaceColor = Color(0xFF16213E);
const _accentBlue = Color(0xFF4361EE);
const _accentGrey = Color(0xFF2D2D44);
const _textPrimary = Color(0xFFEEEEEE);
const _textSecondary = Color(0xFF8A8AB0);

const int _maxPages = 20;

// ─── Document filter pipeline (runs in isolate via compute) ──────────

/// Horizontal projection variance – measures how well text lines align.
double _projectionVariance(img.Image gray, double angle) {
  final rotated = img.copyRotate(gray, angle: angle);
  final h = rotated.height;
  final w = rotated.width;
  // Central 80 % to avoid rotation-fill artifacts
  final yStart = (h * 0.1).round();
  final yEnd = (h * 0.9).round();
  final xStart = (w * 0.1).round();
  final xEnd = (w * 0.9).round();
  final rows = yEnd - yStart;
  if (rows <= 0) return 0;

  final projection = List<int>.filled(rows, 0);
  for (int y = yStart; y < yEnd; y++) {
    for (int x = xStart; x < xEnd; x++) {
      if (rotated.getPixel(x, y).r.toInt() < 128) {
        projection[y - yStart]++;
      }
    }
  }

  double mean = 0;
  for (final v in projection) {
    mean += v;
  }
  mean /= rows;

  double variance = 0;
  for (final v in projection) {
    final d = v - mean;
    variance += d * d;
  }
  return variance / rows;
}

/// 1. DESKEW – detect skew angle via projection profile, max ±15°.
img.Image _deskew(img.Image src) {
  final small = img.copyResize(src, width: (src.width * 0.25).round());
  final gray = img.grayscale(small);

  double bestAngle = 0;
  double bestScore = -1;

  // Coarse search: step 2°
  for (double a = -15; a <= 15; a += 2) {
    final s = _projectionVariance(gray, a);
    if (s > bestScore) {
      bestScore = s;
      bestAngle = a;
    }
  }

  // Fine search: ±2° around best, step 0.5°
  final coarse = bestAngle;
  for (double a = coarse - 2; a <= coarse + 2; a += 0.5) {
    final s = _projectionVariance(gray, a);
    if (s > bestScore) {
      bestScore = s;
      bestAngle = a;
    }
  }

  if (bestAngle.abs() < 0.5) return src; // negligible skew
  return img.copyRotate(src, angle: bestAngle);
}

/// 2. FORMAT A4 – resize with aspect ratio, letterbox on white canvas.
img.Image _formatA4(img.Image src) {
  const a4W = 2480;
  const a4H = 3508;

  final scaleX = a4W / src.width;
  final scaleY = a4H / src.height;
  final scale = math.min(scaleX, scaleY);

  final newW = (src.width * scale).round();
  final newH = (src.height * scale).round();
  final resized = img.copyResize(src, width: newW, height: newH);

  final canvas = img.Image(width: a4W, height: a4H);
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));

  final offsetX = (a4W - newW) ~/ 2;
  final offsetY = (a4H - newH) ~/ 2;
  img.compositeImage(canvas, resized, dstX: offsetX, dstY: offsetY);
  return canvas;
}

/// 3. THRESHOLD – adaptive 32×32 blocks, > mean*0.85 → white, rest stays dark.
img.Image _adaptiveThreshold(img.Image src) {
  final gray = img.grayscale(src);
  final w = gray.width;
  final h = gray.height;
  const blockSize = 32;

  final result = img.Image(width: w, height: h);

  for (int by = 0; by < h; by += blockSize) {
    for (int bx = 0; bx < w; bx += blockSize) {
      final bw = math.min(blockSize, w - bx);
      final bh = math.min(blockSize, h - by);

      int sum = 0;
      int count = 0;
      for (int y = by; y < by + bh; y++) {
        for (int x = bx; x < bx + bw; x++) {
          sum += gray.getPixel(x, y).r.toInt();
          count++;
        }
      }
      final double mean = sum / count;
      final int threshold = (mean * 0.85).round();

      for (int y = by; y < by + bh; y++) {
        for (int x = bx; x < bx + bw; x++) {
          final lum = gray.getPixel(x, y).r.toInt();
          if (lum > threshold) {
            result.setPixelRgb(x, y, 255, 255, 255);
          } else {
            result.setPixelRgb(x, y, lum, lum, lum);
          }
        }
      }
    }
  }
  return result;
}

/// 4. BLACKENING – darken pixels < 128 by subtracting 40.
img.Image _blacken(img.Image src) {
  for (int y = 0; y < src.height; y++) {
    for (int x = 0; x < src.width; x++) {
      final r = src.getPixel(x, y).r.toInt();
      if (r < 128) {
        final v = math.max(0, r - 40);
        src.setPixelRgb(x, y, v, v, v);
      }
    }
  }
  return src;
}

/// Full pipeline entry-point – called via [compute] in a separate isolate.
String _runDocumentPipeline(String path) {
  final bytes = File(path).readAsBytesSync();
  var image = img.decodeImage(bytes);
  if (image == null) return path;

  image = _deskew(image);
  image = _formatA4(image);
  image = _adaptiveThreshold(image);
  image = _blacken(image);

  final dir = File(path).parent.path;
  final ts = DateTime.now().millisecondsSinceEpoch;
  final outPath = '$dir/filtered_$ts.jpg';
  File(outPath).writeAsBytesSync(img.encodeJpg(image, quality: 95));
  return outPath;
}

class PagesEditorScreen extends StatefulWidget {
  final List<String> imagePaths;

  const PagesEditorScreen({super.key, required this.imagePaths});

  @override
  State<PagesEditorScreen> createState() => _PagesEditorScreenState();
}

class _PagesEditorScreenState extends State<PagesEditorScreen> {
  late final List<String> _paths;

  @override
  void initState() {
    super.initState();
    _paths = List<String>.from(widget.imagePaths);
  }

  // ─── Zarządzanie stronami ───────────────────────────────────────────────

  void _deletePage(int index) {
    if (_paths.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Dokument musi mieć co najmniej 1 stronę')),
      );
      return;
    }
    setState(() => _paths.removeAt(index));
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _paths.removeAt(oldIndex);
      _paths.insert(newIndex, item);
    });
  }

  // ─── Dodawanie stron ────────────────────────────────────────────────────

  Future<void> _addFromScanner() async {
    Navigator.pop(context); // zamknij bottom sheet
    if (_paths.length >= _maxPages) {
      _showMaxPagesSnackBar();
      return;
    }
    try {
      final remaining = _maxPages - _paths.length;
      final scanner = DocumentScanner(
        options: DocumentScannerOptions(
          documentFormat: DocumentFormat.jpeg,
          mode: ScannerMode.full,
          isGalleryImport: false,
          pageLimit: remaining,
        ),
      );
      final result = await scanner.scanDocument();
      if (!mounted) return;
      if (result.images.isEmpty) return;
      setState(() {
        for (final p in result.images) {
          if (_paths.length < _maxPages) _paths.add(p);
        }
      });
      await scanner.close();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Błąd skanera: $e')),
      );
    }
  }

  Future<void> _addFromGallery() async {
    Navigator.pop(context); // zamknij bottom sheet
    if (_paths.length >= _maxPages) {
      _showMaxPagesSnackBar();
      return;
    }
    try {
      final files = await ImagePicker().pickMultiImage(imageQuality: 90);
      if (!mounted) return;
      if (files.isEmpty) return;
      setState(() {
        for (final f in files) {
          if (_paths.length < _maxPages) _paths.add(f.path);
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Błąd galerii: $e')),
      );
    }
  }

  void _showMaxPagesSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Osiągnięto limit 20 stron')),
    );
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: _accentGrey,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.document_scanner_rounded,
                    color: _accentBlue),
                title: const Text('Skanuj kolejną stronę',
                    style: TextStyle(color: _textPrimary)),
                subtitle: const Text('Wykrywanie krawędzi dokumentu',
                    style: TextStyle(color: _textSecondary, fontSize: 12)),
                onTap: _addFromScanner,
              ),
              ListTile(
                leading:
                    const Icon(Icons.photo_library_rounded, color: _accentBlue),
                title: const Text('Dodaj z galerii',
                    style: TextStyle(color: _textPrimary)),
                subtitle: const Text('Wybierz jedno lub więcej zdjęć',
                    style: TextStyle(color: _textSecondary, fontSize: 12)),
                onTap: _addFromGallery,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<String> _applyDocumentFilter(String path) async {
    return compute(_runDocumentPipeline, path);
  }

  Future<void> _editPage(int index) async {
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: _paths[index],
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Edytuj stronę ${index + 1}',
          toolbarColor: const Color(0xFF1A1A2E),
          toolbarWidgetColor: Colors.white,
          statusBarColor: const Color(0xFF1A1A2E),
          backgroundColor: const Color(0xFF0F0F23),
          dimmedLayerColor: const Color(0xFF0F0F23),
          cropFrameColor: _accentBlue,
          cropGridColor: _accentBlue,
          activeControlsWidgetColor: _accentBlue,
          showCropGrid: true,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
          hideBottomControls: false,
          aspectRatioPresets: [
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.ratio4x3,
            CropAspectRatioPreset.square,
          ],
        ),
      ],
    );
    if (croppedFile == null || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Przetwarzanie...'),
        duration: Duration(minutes: 1),
      ),
    );

    final resultPath = await _applyDocumentFilter(croppedFile.path);
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      setState(() => _paths[index] = resultPath);
    }
  }

  // ─── UI ─────────────────────────────────────────────────────────────────

  Widget _buildPageCard(BuildContext context, String path, int index) {
    return Card(
      key: ValueKey(path + index.toString()),
      color: _surfaceColor,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: _accentBlue.withAlpha(40), width: 1),
      ),
      child: SizedBox(
        height: 100,
        child: Row(
          children: [
            // Miniaturka
            Tooltip(
              message: 'Dotknij aby poprawić skan',
              child: InkWell(
                onTap: () => _editPage(index),
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(12),
                  ),
                  child: SizedBox(
                    width: 80,
                    height: 100,
                    child: Image.file(
                      File(path),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: _accentGrey,
                        child: const Icon(Icons.broken_image_rounded,
                            color: _textSecondary, size: 32),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Numer strony
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Strona ${index + 1}',
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    path.split('/').last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            // Przycisk usuń
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Color(0xFFEF9A9A), size: 22),
              tooltip: 'Usuń stronę',
              onPressed: () => _deletePage(index),
            ),
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ReorderableDragStartListener(
                index: index,
                child: const Icon(Icons.drag_handle_rounded,
                    color: _textSecondary, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = _paths.length;
    return SafeArea(
      child: Scaffold(
        backgroundColor: _bgColor,
        appBar: AppBar(
          backgroundColor: _bgColor,
          foregroundColor: _textPrimary,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          title: Text(
            'Edytuj strony ($count/$_maxPages)',
            style: const TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton.icon(
              onPressed: () =>
                  Navigator.pop(context, List<String>.from(_paths)),
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Gotowe'),
              style: TextButton.styleFrom(
                foregroundColor: _accentBlue,
                textStyle:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: count == 0
            ? const Center(
                child: Text(
                  'Brak stron. Dodaj stronę przyciskiem +',
                  style: TextStyle(color: _textSecondary, fontSize: 14),
                ),
              )
            : ReorderableListView.builder(
                padding: const EdgeInsets.only(top: 8, bottom: 100),
                buildDefaultDragHandles: false,
                itemCount: count,
                onReorder: _reorder,
                proxyDecorator: (child, index, animation) => Material(
                  color: _bgColor,
                  elevation: 8,
                  borderRadius: BorderRadius.circular(12),
                  child: child,
                ),
                itemBuilder: (ctx, i) => _buildPageCard(ctx, _paths[i], i),
              ),
        floatingActionButton: _paths.length < _maxPages
            ? FloatingActionButton(
                backgroundColor: _accentBlue,
                foregroundColor: Colors.white,
                tooltip: 'Dodaj stronę',
                onPressed: _showAddOptions,
                child: const Icon(Icons.add_rounded),
              )
            : null,
      ),
    );
  }
}
