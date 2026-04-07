import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Rozwiązuje układ 8 równań liniowych metodą eliminacji Gaussa
/// z częściowym pivotingiem.
/// [mat] — macierz rozszerzona 8×9 (8 równań, 8 niewiadomych + kolumna wyrazów wolnych).
/// Zwraca listę 8 rozwiązań lub null jeśli macierz jest zdegenerowana.
List<double>? solveHomography8x8(List<List<double>> mat) {
  for (int col = 0; col < 8; col++) {
    // Partial pivoting
    int maxRow = col;
    double maxVal = mat[col][col].abs();
    for (int row = col + 1; row < 8; row++) {
      if (mat[row][col].abs() > maxVal) {
        maxVal = mat[row][col].abs();
        maxRow = row;
      }
    }
    if (maxRow != col) {
      final tmp = mat[col];
      mat[col] = mat[maxRow];
      mat[maxRow] = tmp;
    }
    final pivot = mat[col][col];
    if (pivot.abs() < 1e-10) return null;
    for (int j = col; j < 9; j++) {
      mat[col][j] /= pivot;
    }
    for (int row = 0; row < 8; row++) {
      if (row == col) continue;
      final factor = mat[row][col];
      for (int j = col; j < 9; j++) {
        mat[row][j] -= factor * mat[col][j];
      }
    }
  }
  return List<double>.generate(8, (i) => mat[i][8]);
}

/// Stosuje transformację perspektywiczną na obrazie.
///
/// [imagePath] — ścieżka do obrazu źródłowego.
/// [corners] — 8 wartości [x1,y1, x2,y2, x3,y3, x4,y4] — współrzędne
///   4 narożników źródłowych w pikselach obrazu:
///   topLeft, topRight, bottomRight, bottomLeft.
///
/// Zwraca ścieżkę do nowego pliku JPG z wyprostowanym dokumentem.
/// Funkcja przeznaczona do wywołania przez `compute()` w izolacie.
String applyPerspectiveTransform(String imagePath, List<double> corners) {
  assert(corners.length == 8);

  final tlX = corners[0], tlY = corners[1];
  final trX = corners[2], trY = corners[3];
  final brX = corners[4], brY = corners[5];
  final blX = corners[6], blY = corners[7];

  // Wczytaj obraz źródłowy
  final bytes = File(imagePath).readAsBytesSync();
  final src = img.decodeImage(bytes);
  if (src == null) return imagePath;

  // Oblicz rozmiar docelowy na podstawie odległości między narożnikami
  double dist(double x1, double y1, double x2, double y2) =>
      math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1));

  var destW =
      math.max(dist(tlX, tlY, trX, trY), dist(blX, blY, brX, brY)).round();
  var destH =
      math.max(dist(tlX, tlY, blX, blY), dist(trX, trY, brX, brY)).round();
  destW = destW.clamp(200, 3508);
  destH = destH.clamp(200, 3508);

  // Punkty źródłowe i docelowe
  final srcPts = [tlX, tlY, trX, trY, brX, brY, blX, blY];
  final dstPts = [
    0.0,
    0.0,
    destW.toDouble(),
    0.0,
    destW.toDouble(),
    destH.toDouble(),
    0.0,
    destH.toDouble(),
  ];

  // Buduj macierz rozszerzoną 8×9 dla homografii
  // src = H * dst  →  dla każdej pary (sx,sy) ↔ (dx,dy):
  //   sx = (h0*dx + h1*dy + h2) / (h6*dx + h7*dy + 1)
  //   sy = (h3*dx + h4*dy + h5) / (h6*dx + h7*dy + 1)
  final mat = List.generate(8, (_) => List<double>.filled(9, 0.0));
  for (int i = 0; i < 4; i++) {
    final sx = srcPts[i * 2];
    final sy = srcPts[i * 2 + 1];
    final dx = dstPts[i * 2];
    final dy = dstPts[i * 2 + 1];
    final r1 = i * 2;
    final r2 = i * 2 + 1;
    mat[r1][0] = dx;
    mat[r1][1] = dy;
    mat[r1][2] = 1;
    mat[r1][6] = -sx * dx;
    mat[r1][7] = -sx * dy;
    mat[r1][8] = sx;
    mat[r2][3] = dx;
    mat[r2][4] = dy;
    mat[r2][5] = 1;
    mat[r2][6] = -sy * dx;
    mat[r2][7] = -sy * dy;
    mat[r2][8] = sy;
  }

  // Rozwiąż układ równań — eliminacja Gaussa
  final h = solveHomography8x8(mat);
  if (h == null) return imagePath;

  // Inverse mapping z interpolacją bilinearną
  final dest = img.Image(width: destW, height: destH);
  img.fill(dest, color: img.ColorRgb8(255, 255, 255));

  final srcW = src.width;
  final srcH = src.height;

  for (int dy = 0; dy < destH; dy++) {
    for (int dx = 0; dx < destW; dx++) {
      final denom = h[6] * dx + h[7] * dy + 1.0;
      if (denom.abs() < 1e-10) continue;
      final sx = (h[0] * dx + h[1] * dy + h[2]) / denom;
      final sy = (h[3] * dx + h[4] * dy + h[5]) / denom;

      if (sx < 0 || sy < 0 || sx >= srcW - 1 || sy >= srcH - 1) continue;

      // Interpolacja bilinearna
      final x0 = sx.floor();
      final y0 = sy.floor();
      final x1 = x0 + 1;
      final y1 = y0 + 1;
      final fx = sx - x0;
      final fy = sy - y0;

      final p00 = src.getPixel(x0, y0);
      final p10 = src.getPixel(x1, y0);
      final p01 = src.getPixel(x0, y1);
      final p11 = src.getPixel(x1, y1);

      final r = ((p00.r * (1 - fx) * (1 - fy)) +
              (p10.r * fx * (1 - fy)) +
              (p01.r * (1 - fx) * fy) +
              (p11.r * fx * fy))
          .round()
          .clamp(0, 255);
      final g = ((p00.g * (1 - fx) * (1 - fy)) +
              (p10.g * fx * (1 - fy)) +
              (p01.g * (1 - fx) * fy) +
              (p11.g * fx * fy))
          .round()
          .clamp(0, 255);
      final b = ((p00.b * (1 - fx) * (1 - fy)) +
              (p10.b * fx * (1 - fy)) +
              (p01.b * (1 - fx) * fy) +
              (p11.b * fx * fy))
          .round()
          .clamp(0, 255);

      dest.setPixelRgb(dx, dy, r, g, b);
    }
  }

  // Zapisz wynik
  final dir = File(imagePath).parent.path;
  final ts = DateTime.now().millisecondsSinceEpoch;
  final outPath = '$dir/perspective_$ts.jpg';
  File(outPath).writeAsBytesSync(img.encodeJpg(dest, quality: 95));
  return outPath;
}

/// Wrapper dla compute() — przyjmuje Map z kluczami 'path' i 'corners'.
String applyPerspectiveTransformIsolate(Map<String, dynamic> args) {
  return applyPerspectiveTransform(
    args['path'] as String,
    (args['corners'] as List).cast<double>(),
  );
}
