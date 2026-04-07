import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'result_screen.dart';

const _bgColor = Color(0xFF1A1A2E);
const _accentBlue = Color(0xFF4361EE);
const _textPrimary = Color(0xFFEEEEEE);
const _textSecondary = Color(0xFF8A8AB0);

class CameraScreen extends StatefulWidget {
  final String source; // 'camera' lub 'gallery'

  const CameraScreen({super.key, required this.source});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  bool _isPicking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pickImage());
  }

  Future<void> _pickImage() async {
    if (_isPicking) return;
    setState(() => _isPicking = true);

    final picker = ImagePicker();
    final source =
        widget.source == 'camera' ? ImageSource.camera : ImageSource.gallery;

    try {
      final XFile? file = await picker.pickImage(
        source: source,
        imageQuality: 90,
      );

      if (!mounted) return;

      if (file == null) {
        Navigator.pop(context);
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(imagePath: file.path),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Błąd: ${e.toString()}')),
      );
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        foregroundColor: _textPrimary,
        elevation: 0,
        title: Text(widget.source == 'camera' ? 'Aparat' : 'Galeria'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.source == 'camera'
                  ? Icons.camera_alt_rounded
                  : Icons.photo_library_rounded,
              size: 80,
              color: _accentBlue,
            ),
            const SizedBox(height: 24),
            Text(
              widget.source == 'camera'
                  ? 'Otwieranie aparatu...'
                  : 'Otwieranie galerii...',
              style: const TextStyle(color: _textSecondary, fontSize: 16),
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(color: _accentBlue),
            const SizedBox(height: 48),
            TextButton(
              onPressed: _isPicking ? null : _pickImage,
              child: const Text(
                'Spróbuj ponownie',
                style: TextStyle(color: _accentBlue),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
