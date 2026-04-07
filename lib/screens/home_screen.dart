import 'package:flutter/material.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'pages_editor_screen.dart';
import 'result_screen.dart';
import 'scans_screen.dart';

const _bgColor = Color(0xFF1A1A2E);
const _surfaceColor = Color(0xFF16213E);
const _accentBlue = Color(0xFF4361EE);
const _accentGrey = Color(0xFF2D2D44);
const _textPrimary = Color(0xFFEEEEEE);
const _textSecondary = Color(0xFF8A8AB0);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _scanWithDetection(BuildContext context) async {
    try {
      final scanner = DocumentScanner(
        options: DocumentScannerOptions(
          documentFormat: DocumentFormat.jpeg,
          mode: ScannerMode.full,
          isGalleryImport: false,
          pageLimit: 1,
        ),
      );
      final result = await scanner.scanDocument();
      debugPrint('ML Kit result: ${result.images}');
      await scanner.close();
      if (!context.mounted) return;
      if (result.images.isEmpty) return;
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (_, animation, __) =>
              ResultScreen(imagePath: result.images.first),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(
            opacity: animation,
            child: child,
          ),
          transitionDuration: const Duration(milliseconds: 300),
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('ML Kit ERROR: $e');
      debugPrint('StackTrace: $stackTrace');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Błąd skanera: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 10),
        ),
      );
    }
  }

  Future<void> _pickFromGallery(BuildContext context) async {
    try {
      final picker = ImagePicker();
      final files = await picker.pickMultiImage(imageQuality: 90);
      if (!context.mounted) return;
      if (files.isEmpty) return;
      final paths = files.map((f) => f.path).toList();
      final edited = await Navigator.push<List<String>>(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => PagesEditorScreen(imagePaths: paths),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
      if (!context.mounted) return;
      if (edited == null || edited.isEmpty) return;
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (_, animation, __) => edited.length == 1
              ? ResultScreen(imagePath: edited.first)
              : ResultScreen(imagePath: edited.first, imagePaths: edited),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(
            opacity: animation,
            child: child,
          ),
          transitionDuration: const Duration(milliseconds: 300),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Błąd galerii: ${e.toString()}'),
          backgroundColor: const Color(0xFFB00020),
        ),
      );
    }
  }

  Future<void> _scanMultiPage(BuildContext context) async {
    try {
      final scanner = DocumentScanner(
        options: DocumentScannerOptions(
          documentFormat: DocumentFormat.jpeg,
          mode: ScannerMode.full,
          isGalleryImport: false,
          pageLimit: 20,
        ),
      );
      final result = await scanner.scanDocument();
      await scanner.close();
      if (!context.mounted) return;
      if (result.images.isEmpty) return;
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (_, animation, __) => ResultScreen(
            imagePath: result.images.first,
            imagePaths: result.images,
          ),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(
            opacity: animation,
            child: child,
          ),
          transitionDuration: const Duration(milliseconds: 300),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Błąd skanera: ${e.toString()}'),
          backgroundColor: const Color(0xFFB00020),
        ),
      );
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
        title: const Text(
          'SortVision Scanner',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_rounded),
            tooltip: 'Zapisane skany',
            onPressed: () => Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (_, animation, __) => const ScansScreen(),
                transitionsBuilder: (_, animation, __, child) =>
                    FadeTransition(opacity: animation, child: child),
                transitionDuration: const Duration(milliseconds: 300),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 32),
                  _buildLogo(),
                  const SizedBox(height: 16),
                  _buildHeader(),
                  const SizedBox(height: 40),
                  _buildActionButton(
                    label: 'Skanuj dokument',
                    description: 'Użyj aparatu do natychmiastowego skanu',
                    icon: Icons.document_scanner_rounded,
                    backgroundColor: _accentBlue,
                    iconColor: Colors.white,
                    textColor: Colors.white,
                    onPressed: () => _scanWithDetection(context),
                  ),
                  const SizedBox(height: 16),
                  _buildActionButton(
                    label: 'Skanuj wielostronicowy',
                    description: 'Zeskanuj do 20 stron jako jeden PDF',
                    icon: Icons.picture_as_pdf_rounded,
                    backgroundColor: _accentGrey,
                    iconColor: _textSecondary,
                    textColor: _textPrimary,
                    onPressed: () => _scanMultiPage(context),
                  ),
                  const SizedBox(height: 16),
                  _buildActionButton(
                    label: 'Wybierz z galerii',
                    description: 'Importuj jedno lub więcej zdjęć z galerii',
                    icon: Icons.photo_library_rounded,
                    backgroundColor: _accentGrey,
                    iconColor: _textSecondary,
                    textColor: _textPrimary,
                    onPressed: () => _pickFromGallery(context),
                  ),
                  const Spacer(),
                  _buildFooter(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: _accentBlue.withAlpha(80), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _accentBlue.withAlpha(60),
            blurRadius: 32,
            spreadRadius: 2,
          ),
        ],
      ),
      child: const Icon(
        Icons.document_scanner,
        size: 80,
        color: _accentBlue,
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        const Text(
          'SortVision Scanner',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Skanuj i klasyfikuj dokumenty AI',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: _textSecondary,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required String description,
    required IconData icon,
    required Color backgroundColor,
    required Color iconColor,
    required Color textColor,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        splashColor: Colors.white.withAlpha(20),
        highlightColor: Colors.white.withAlpha(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: iconColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 26),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12,
                        color: textColor.withAlpha(150),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: textColor.withAlpha(120),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.auto_awesome, size: 13, color: _accentBlue.withAlpha(180)),
        const SizedBox(width: 6),
        Text(
          'Powered by SortVision AI',
          style: TextStyle(
            fontSize: 12,
            color: _textSecondary.withAlpha(180),
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}
