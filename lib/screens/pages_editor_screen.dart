import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image_picker/image_picker.dart';

import '../services/perspective_transform.dart';
import '../utils/document_pipeline.dart' show runDocumentPipelineNoDeskew;
import '../widgets/quad_crop_screen.dart';

const _bgColor = Color(0xFF1A1A2E);
const _surfaceColor = Color(0xFF16213E);
const _accentBlue = Color(0xFF4361EE);
const _accentGrey = Color(0xFF2D2D44);
const _textPrimary = Color(0xFFEEEEEE);
const _textSecondary = Color(0xFF8A8AB0);

const int _maxPages = 20;

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

  Future<void> _editPage(int index) async {
    final corners = await Navigator.push<List<Offset>>(
      context,
      MaterialPageRoute(
        builder: (_) => QuadCropScreen(imagePath: _paths[index]),
      ),
    );
    if (corners == null || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Przetwarzanie...'),
        duration: Duration(minutes: 1),
      ),
    );

    final cornersList = <double>[
      corners[0].dx,
      corners[0].dy,
      corners[1].dx,
      corners[1].dy,
      corners[2].dx,
      corners[2].dy,
      corners[3].dx,
      corners[3].dy,
    ];

    final perspectivePath = await compute(
      applyPerspectiveTransformIsolate,
      {'path': _paths[index], 'corners': cornersList},
    );

    final resultPath =
        await compute(runDocumentPipelineNoDeskew, perspectivePath);
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
