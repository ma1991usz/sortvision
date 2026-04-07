import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const _bgColor = Color(0xFF1A1A2E);
const _surfaceColor = Color(0xFF16213E);
const _accentBlue = Color(0xFF4361EE);
const _accentGreen = Color(0xFF2ECC71);
const _textPrimary = Color(0xFFEEEEEE);
const _textSecondary = Color(0xFF8A8AB0);

class OcrScreen extends StatelessWidget {
  final String text;
  const OcrScreen({super.key, required this.text});

  Future<void> _copyAll(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Skopiowano tekst do schowka')),
      );
    }
  }

  Future<void> _saveTxt(BuildContext context) async {
    try {
      final baseDir = await getApplicationDocumentsDirectory();
      final folder = Directory('${baseDir.path}/SortVision');
      if (!await folder.exists()) await folder.create(recursive: true);
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final file = File('${folder.path}/ocr_$ts.txt');
      await file.writeAsString(text);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Zapisano: ${file.path}'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Błąd zapisu: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = text.trim().isEmpty;

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        foregroundColor: _textPrimary,
        elevation: 0,
        title: const Text('Pełny tekst OCR'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'Kopiuj wszystko',
            onPressed: isEmpty ? null : () => _copyAll(context),
          ),
          IconButton(
            icon: const Icon(Icons.save_alt_rounded),
            tooltip: 'Zapisz .txt',
            onPressed: isEmpty ? null : () => _saveTxt(context),
          ),
        ],
      ),
      body: isEmpty
          ? const Center(
              child: Text(
                '(Brak rozpoznanego tekstu)',
                style: TextStyle(color: _textSecondary, fontSize: 15),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _surfaceColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SelectableText(
                      text,
                      style: const TextStyle(
                        color: _textPrimary,
                        fontFamily: 'monospace',
                        fontSize: 13.5,
                        height: 1.7,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).padding.bottom + 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            label: const Text('Kopiuj wszystko'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _textPrimary,
                              side: const BorderSide(color: _accentBlue),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () => _copyAll(context),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.save_alt_rounded, size: 18),
                            label: const Text('Zapisz .txt'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _accentGreen,
                              side: const BorderSide(color: _accentGreen),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () => _saveTxt(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }
}
