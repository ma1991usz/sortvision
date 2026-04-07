import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

// ─── Document filter pipeline (runs in isolate via compute) ──────────

/// Horizontal projection variance – measures how well text lines align.
double projectionVariance(img.Image gray, double angle) {
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
img.Image deskew(img.Image src) {
  final small = img.copyResize(src, width: (src.width * 0.25).round());
  final gray = img.grayscale(small);

  double bestAngle = 0;
  double bestScore = -1;

  // Coarse search: step 2°
  for (double a = -15; a <= 15; a += 2) {
    final s = projectionVariance(gray, a);
    if (s > bestScore) {
      bestScore = s;
      bestAngle = a;
    }
  }

  // Fine search: ±2° around best, step 0.5°
  final coarse = bestAngle;
  for (double a = coarse - 2; a <= coarse + 2; a += 0.5) {
    final s = projectionVariance(gray, a);
    if (s > bestScore) {
      bestScore = s;
      bestAngle = a;
    }
  }

  if (bestAngle.abs() < 0.5) return src; // negligible skew
  return img.copyRotate(src, angle: bestAngle);
}

/// 2. FORMAT A4 – resize with aspect ratio, letterbox on white canvas.
img.Image formatA4(img.Image src) {
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
img.Image adaptiveThreshold(img.Image src) {
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
img.Image blacken(img.Image src) {
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
String runDocumentPipeline(String path) {
  final bytes = File(path).readAsBytesSync();
  var image = img.decodeImage(bytes);
  if (image == null) return path;

  image = deskew(image);
  image = formatA4(image);
  image = adaptiveThreshold(image);
  image = blacken(image);

  final dir = File(path).parent.path;
  final ts = DateTime.now().millisecondsSinceEpoch;
  final outPath = '$dir/filtered_$ts.jpg';
  File(outPath).writeAsBytesSync(img.encodeJpg(image, quality: 95));
  return outPath;
}

/// Pipeline BEZ deskew — używany po ręcznej korekcji perspektywy.
String runDocumentPipelineNoDeskew(String path) {
  final bytes = File(path).readAsBytesSync();
  var image = img.decodeImage(bytes);
  if (image == null) return path;

  image = formatA4(image);
  image = adaptiveThreshold(image);
  image = blacken(image);

  final dir = File(path).parent.path;
  final ts = DateTime.now().millisecondsSinceEpoch;
  final outPath = '$dir/filtered_$ts.jpg';
  File(outPath).writeAsBytesSync(img.encodeJpg(image, quality: 95));
  return outPath;
}

/// Perspective transform — accepts JSON string, returns path to transformed image.
/// JSON: {"path": "...", "topLeft": {"x":...,"y":...}, "topRight":{...}, "bottomRight":{...}, "bottomLeft":{...}}
/// Coordinates are in pixels of the original image.
String perspectiveTransform(String jsonArgs) {
  final args = jsonDecode(jsonArgs) as Map<String, dynamic>;
  final path = args['path'] as String;
  final tl = args['topLeft'] as Map<String, dynamic>;
  final tr = args['topRight'] as Map<String, dynamic>;
  final br = args['bottomRight'] as Map<String, dynamic>;
  final bl = args['bottomLeft'] as Map<String, dynamic>;

  final tlX = (tl['x'] as num).toDouble();
  final tlY = (tl['y'] as num).toDouble();
  final trX = (tr['x'] as num).toDouble();
  final trY = (tr['y'] as num).toDouble();
  final brX = (br['x'] as num).toDouble();
  final brY = (br['y'] as num).toDouble();
  final blX = (bl['x'] as num).toDouble();
  final blY = (bl['y'] as num).toDouble();

  // Load source image
  final bytes = File(path).readAsBytesSync();
  final src = img.decodeImage(bytes);
  if (src == null) return path;

  // Destination size from corner distances
  double dist(double x1, double y1, double x2, double y2) =>
      math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1));

  var destW =
      math.max(dist(tlX, tlY, trX, trY), dist(blX, blY, brX, brY)).round();
  var destH =
      math.max(dist(tlX, tlY, blX, blY), dist(trX, trY, brX, brY)).round();
  destW = destW.clamp(200, 3508);
  destH = destH.clamp(200, 3508);

  // Solve 3x3 homography: src = H * dst
  // 8 equations, 8 unknowns (h0..h7, h8=1)
  // For each point pair (sx,sy) ↔ (dx,dy):
  //   sx = (h0*dx + h1*dy + h2) / (h6*dx + h7*dy + 1)
  //   sy = (h3*dx + h4*dy + h5) / (h6*dx + h7*dy + 1)
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

  // Build 8x9 augmented matrix
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
    mat[r1][3] = 0;
    mat[r1][4] = 0;
    mat[r1][5] = 0;
    mat[r1][6] = -sx * dx;
    mat[r1][7] = -sx * dy;
    mat[r1][8] = sx;
    mat[r2][0] = 0;
    mat[r2][1] = 0;
    mat[r2][2] = 0;
    mat[r2][3] = dx;
    mat[r2][4] = dy;
    mat[r2][5] = 1;
    mat[r2][6] = -sy * dx;
    mat[r2][7] = -sy * dy;
    mat[r2][8] = sy;
  }

  // Gaussian elimination with partial pivoting
  for (int col = 0; col < 8; col++) {
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
    if (pivot.abs() < 1e-10) return path; // degenerate
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

  // H coefficients: h0..h7, h8=1
  final h = List<double>.generate(8, (i) => mat[i][8]);

  // Warp with bilinear interpolation
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

      // Bilinear interpolation
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

  final dir = File(path).parent.path;
  final ts = DateTime.now().millisecondsSinceEpoch;
  final outPath = '$dir/perspective_$ts.jpg';
  File(outPath).writeAsBytesSync(img.encodeJpg(dest, quality: 95));
  return outPath;
}
