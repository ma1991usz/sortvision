import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

const String kLocalRouter = 'https://ai.e-worldmc.pl';
const String kOcrGateway = 'https://ocr.e-worldmc.pl';

/// Callback do raportowania etapu przetwarzania.
typedef StageCallback = void Function(String stage);

/// Top-level function do uruchomienia w osobnym isolate via compute().
Future<String> _preprocessIsolate(String imagePath) async {
  final bytes = await File(imagePath).readAsBytes();
  var decoded = img.decodeImage(bytes);
  if (decoded == null) return base64Encode(bytes);

  final maxSide =
      decoded.width > decoded.height ? decoded.width : decoded.height;
  if (maxSide > 1600) {
    final scale = 1600 / maxSide;
    decoded = img.copyResize(
      decoded,
      width: (decoded.width * scale).round(),
      height: (decoded.height * scale).round(),
      interpolation: img.Interpolation.cubic,
    );
  }

  final jpeg = img.encodeJpg(decoded, quality: 85);
  return base64Encode(jpeg);
}

/// Preprocessing z wymiarami — zwraca JSON {base64, width, height}.
Future<String> _preprocessWithDimsIsolate(String imagePath) async {
  final bytes = await File(imagePath).readAsBytes();
  var decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return jsonEncode({'base64': base64Encode(bytes), 'width': 0, 'height': 0});
  }

  final maxSide =
      decoded.width > decoded.height ? decoded.width : decoded.height;
  if (maxSide > 1600) {
    final scale = 1600 / maxSide;
    decoded = img.copyResize(
      decoded,
      width: (decoded.width * scale).round(),
      height: (decoded.height * scale).round(),
      interpolation: img.Interpolation.cubic,
    );
  }

  final jpeg = img.encodeJpg(decoded, quality: 85);
  return jsonEncode({
    'base64': base64Encode(jpeg),
    'width': decoded.width,
    'height': decoded.height,
  });
}

class ApiService {
  /// On-device preprocessing w osobnym isolate.
  /// Fallback na surowy base64 z pliku.
  Future<String> _preprocessOnDevice(String imagePath) async {
    try {
      return await compute(_preprocessIsolate, imagePath);
    } catch (_) {
      try {
        return base64Encode(await File(imagePath).readAsBytes());
      } catch (_) {
        rethrow;
      }
    }
  }

  /// Wysyła zdjęcie do lokalnego routera (/api/describe).
  /// Zwraca opis dokumentu jako String.
  Future<String> analyzeDocument(String imagePath,
      {StageCallback? onStage}) async {
    onStage?.call('Optymalizacja obrazu...');
    final processed = await _preprocessOnDevice(imagePath);

    onStage?.call('Analiza AI...');
    final body = jsonEncode({'image_base64': processed});

    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('$kLocalRouter/api/describe'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 95));
    } on TimeoutException {
      throw Exception('Przekroczono limit czasu');
    } on SocketException {
      throw Exception('Router niedostępny');
    } on http.ClientException {
      throw Exception('Router niedostępny');
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['result'] as String? ?? '';
    } else {
      throw Exception('Błąd API (${response.statusCode}): ${response.body}');
    }
  }

  /// Wysyła zdjęcie do OCR via async gateway (submit + poll).
  Future<String> analyzeDocumentOCR(String imagePath,
      {StageCallback? onStage}) async {
    onStage?.call('Optymalizacja obrazu...');
    final raw = await compute(_preprocessWithDimsIsolate, imagePath);
    final dims = jsonDecode(raw) as Map<String, dynamic>;
    final b64 = dims['base64'] as String;
    final width = dims['width'] as int;
    final height = dims['height'] as int;

    onStage?.call('Wysyłanie do OCR...');
    final submit = await _submitOcrJob(
      docBase64: b64,
      pages: 1,
      width: width,
      height: height,
    );

    return _pollOcrResult(
      submit['job_id'] as String,
      submit['timeout_seconds'] as int,
      submit['poll_interval'] as int,
      onStage: onStage,
    );
  }

  /// Wysyła pierwsze zdjęcie z wielostronicowego dokumentu do /api/describe.
  Future<String> analyzeMultiPage(List<String> imagePaths,
      {StageCallback? onStage}) async {
    if (imagePaths.isEmpty) throw Exception('Brak stron do analizy');

    onStage?.call('Optymalizacja obrazu...');
    final processed = await _preprocessOnDevice(imagePaths.first);

    onStage?.call('Analiza AI...');
    final body = jsonEncode({'image_base64': processed});

    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('$kLocalRouter/api/describe'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 95));
    } on TimeoutException {
      throw Exception('Przekroczono limit czasu');
    } on SocketException {
      throw Exception('Router niedostępny');
    } on http.ClientException {
      throw Exception('Router niedostępny');
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['result'] as String? ?? '';
    } else {
      throw Exception('Błąd API (${response.statusCode}): ${response.body}');
    }
  }

  /// Wysyła wszystkie strony naraz do OCR gateway (submit + poll).
  Future<String> analyzeMultiPageOCR(List<String> imagePaths,
      {StageCallback? onStage}) async {
    if (imagePaths.isEmpty) throw Exception('Brak stron do analizy');

    onStage?.call('Optymalizacja ${imagePaths.length} stron...');
    final allBase64 = <String>[];
    int maxWidth = 0;
    int maxHeight = 0;

    for (int i = 0; i < imagePaths.length; i++) {
      onStage?.call('Optymalizacja strony ${i + 1}/${imagePaths.length}...');
      final raw = await compute(_preprocessWithDimsIsolate, imagePaths[i]);
      final dims = jsonDecode(raw) as Map<String, dynamic>;
      allBase64.add(dims['base64'] as String);
      final w = dims['width'] as int;
      final h = dims['height'] as int;
      if (w > maxWidth) maxWidth = w;
      if (h > maxHeight) maxHeight = h;
    }

    onStage?.call('Wysyłanie ${imagePaths.length} stron do OCR...');
    final submit = await _submitOcrJob(
      docBase64: allBase64,
      pages: allBase64.length,
      width: maxWidth,
      height: maxHeight,
    );

    return _pollOcrResult(
      submit['job_id'] as String,
      submit['timeout_seconds'] as int,
      submit['poll_interval'] as int,
      onStage: onStage,
    );
  }

  // ── Async OCR gateway helpers ──

  Future<Map<String, dynamic>> _submitOcrJob({
    required Object docBase64,
    required int pages,
    required int width,
    required int height,
  }) async {
    final body = jsonEncode({
      'doc_base64': docBase64,
      'pages': pages,
      'width': width,
      'height': height,
    });

    const maxRetries = 5;
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      final http.Response response;
      try {
        response = await http
            .post(
              Uri.parse('$kOcrGateway/api/v1/ocr'),
              headers: {'Content-Type': 'application/json'},
              body: body,
            )
            .timeout(const Duration(seconds: 30));
      } on TimeoutException {
        throw Exception('Gateway OCR niedostępny (timeout)');
      } on SocketException {
        throw Exception('Gateway OCR niedostępny');
      } on http.ClientException {
        throw Exception('Gateway OCR niedostępny');
      }

      if (response.statusCode == 202) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      if (response.statusCode == 429) {
        final retryAfter = int.tryParse(
              response.headers['retry-after'] ?? '',
            ) ??
            5;
        if (attempt < maxRetries - 1) {
          await Future.delayed(Duration(seconds: retryAfter));
          continue;
        }
        throw Exception('Serwer OCR przeciążony — spróbuj ponownie za chwilę');
      }

      throw Exception(
          'Błąd submit OCR (${response.statusCode}): ${response.body}');
    }
    throw Exception('Serwer OCR przeciążony — przekroczono limit prób');
  }

  Future<String> _pollOcrResult(
      String jobId, int timeoutSeconds, int pollInterval,
      {StageCallback? onStage}) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSeconds + 30));

    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(Duration(seconds: pollInterval));

      final http.Response response;
      try {
        response = await http
            .get(Uri.parse('$kOcrGateway/api/v1/ocr/$jobId'))
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        continue;
      }

      if (response.statusCode != 200) continue;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['status'] as String;

      if (status == 'processing') {
        final progress = data['progress'] as String?;
        if (progress != null && progress.isNotEmpty) {
          onStage?.call('OCR $progress');
        } else {
          onStage?.call('Przetwarzanie OCR...');
        }
      } else if (status == 'completed' || status == 'fallback') {
        final source = data['source'] as String? ?? '?';
        final timeMs = data['processing_time_ms'] as int? ?? 0;
        onStage?.call('Gotowe ($source, ${timeMs}ms)');
        return data['text'] as String? ?? '';
      } else if (status == 'failed') {
        throw Exception('OCR failed: ${data['text'] ?? 'Nieznany błąd'}');
      }
    }

    throw Exception('OCR timeout — brak wyniku w ${timeoutSeconds}s');
  }
}
