import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

const _bgColor = Color(0xFF1A1A2E);
const _accentBlue = Color(0xFF4361EE);
const _textPrimary = Color(0xFFEEEEEE);

class QuadCropScreen extends StatefulWidget {
  final String imagePath;

  const QuadCropScreen({super.key, required this.imagePath});

  @override
  State<QuadCropScreen> createState() => _QuadCropScreenState();
}

class _QuadCropScreenState extends State<QuadCropScreen> {
  ui.Image? _image;
  final List<Offset> _corners = List.filled(4, Offset.zero);
  int? _activeCorner;

  // Layout: image rect inside the widget area
  Rect _imageRect = Rect.zero;
  Size _imageSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final bytes = await File(widget.imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() {
      _image = frame.image;
      _imageSize = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
    });
  }

  void _initCorners(Size widgetSize) {
    if (_image == null) return;

    // Fit image into widget area preserving aspect ratio
    final imgAspect = _imageSize.width / _imageSize.height;
    final areaAspect = widgetSize.width / widgetSize.height;

    double drawW, drawH, offsetX, offsetY;
    if (imgAspect > areaAspect) {
      drawW = widgetSize.width;
      drawH = widgetSize.width / imgAspect;
      offsetX = 0;
      offsetY = (widgetSize.height - drawH) / 2;
    } else {
      drawH = widgetSize.height;
      drawW = widgetSize.height * imgAspect;
      offsetX = (widgetSize.width - drawW) / 2;
      offsetY = 0;
    }

    _imageRect = Rect.fromLTWH(offsetX, offsetY, drawW, drawH);

    // 10% margin inside image rect
    final mx = drawW * 0.10;
    final my = drawH * 0.10;
    _corners[0] = Offset(offsetX + mx, offsetY + my); // topLeft
    _corners[1] = Offset(offsetX + drawW - mx, offsetY + my); // topRight
    _corners[2] =
        Offset(offsetX + drawW - mx, offsetY + drawH - my); // bottomRight
    _corners[3] = Offset(offsetX + mx, offsetY + drawH - my); // bottomLeft
  }

  Offset _screenToImage(Offset screen) {
    final scaleX = _imageSize.width / _imageRect.width;
    final scaleY = _imageSize.height / _imageRect.height;
    return Offset(
      (screen.dx - _imageRect.left) * scaleX,
      (screen.dy - _imageRect.top) * scaleY,
    );
  }

  int? _hitTest(Offset pos) {
    const hitRadius = 28.0;
    for (int i = 0; i < 4; i++) {
      if ((pos - _corners[i]).distance <= hitRadius) return i;
    }
    return null;
  }

  Offset _clamp(Offset pos) {
    return Offset(
      pos.dx.clamp(_imageRect.left, _imageRect.right),
      pos.dy.clamp(_imageRect.top, _imageRect.bottom),
    );
  }

  void _accept() {
    final result = [
      _screenToImage(_corners[0]),
      _screenToImage(_corners[1]),
      _screenToImage(_corners[2]),
      _screenToImage(_corners[3]),
    ];
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        foregroundColor: _textPrimary,
        elevation: 0,
        title: const Text(
          'Dopasuj narożniki',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.check_rounded),
            tooltip: 'Akceptuj',
            onPressed: _image != null ? _accept : null,
          ),
        ],
      ),
      body: _image == null
          ? const Center(
              child: CircularProgressIndicator(color: _accentBlue),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final widgetSize = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );

                // Init corners once when image is loaded
                if (_imageRect == Rect.zero) {
                  _initCorners(widgetSize);
                }

                return GestureDetector(
                  onPanStart: (d) {
                    _activeCorner = _hitTest(d.localPosition);
                  },
                  onPanUpdate: (d) {
                    if (_activeCorner != null) {
                      setState(() {
                        _corners[_activeCorner!] = _clamp(d.localPosition);
                      });
                    }
                  },
                  onPanEnd: (_) => _activeCorner = null,
                  child: CustomPaint(
                    size: widgetSize,
                    painter: _QuadPainter(
                      image: _image!,
                      imageRect: _imageRect,
                      corners: _corners,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _QuadPainter extends CustomPainter {
  final ui.Image image;
  final Rect imageRect;
  final List<Offset> corners;

  _QuadPainter({
    required this.image,
    required this.imageRect,
    required this.corners,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw image fitted into imageRect
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    canvas.drawImageRect(image, src, imageRect, Paint());

    // Semi-transparent overlay outside quad
    final quadPath = Path()
      ..moveTo(corners[0].dx, corners[0].dy)
      ..lineTo(corners[1].dx, corners[1].dy)
      ..lineTo(corners[2].dx, corners[2].dy)
      ..lineTo(corners[3].dx, corners[3].dy)
      ..close();

    final fullPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final overlayPath =
        Path.combine(PathOperation.difference, fullPath, quadPath);
    canvas.drawPath(
      overlayPath,
      Paint()..color = const Color(0x80000000),
    );

    // Quad lines
    final linePaint = Paint()
      ..color = _accentBlue.withAlpha(180)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawPath(quadPath, linePaint);

    // Corner circles
    final fillPaint = Paint()
      ..color = _accentBlue
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (final c in corners) {
      canvas.drawCircle(c, 14, fillPaint);
      canvas.drawCircle(c, 14, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _QuadPainter old) => true;
}
