import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// One measured dimension of a reference-vs-generated comparison.
class SimilarityMetric {
  const SimilarityMetric(
      this.key, this.label, this.detail, this.similarity, this.weight);
  final String key;
  final String label;
  final String detail;

  /// 0..1 (1 = identical on this dimension).
  final double similarity;
  final double weight;
}

/// Verdict buckets for the overall similarity.
enum OriginalityVerdict { original, inspired, review, tooSimilar }

/// Local (pixel) analysis of how close a generated image is to its
/// reference. Calibrated so unrelated pictures land around 10-30 %
/// similarity and near copies above 80 %.
class SimilarityReport {
  SimilarityReport({
    required this.metrics,
    required this.paletteA,
    required this.paletteB,
    required this.sizeA,
    required this.sizeB,
  });
  final List<SimilarityMetric> metrics;

  /// Dominant colours (ARGB) of the reference and of the new image.
  final List<int> paletteA;
  final List<int> paletteB;
  final (int, int) sizeA;
  final (int, int) sizeB;

  /// Weighted similarity 0..100.
  double get similarity {
    var sum = 0.0, w = 0.0;
    for (final m in metrics) {
      sum += m.similarity * m.weight;
      w += m.weight;
    }
    return w == 0 ? 0 : (sum / w * 100).clamp(0, 100).toDouble();
  }

  /// 100 - similarity: how much the new image moved away.
  double get creativity => 100 - similarity;

  static OriginalityVerdict verdictFor(double similarity) {
    if (similarity >= 70) return OriginalityVerdict.tooSimilar;
    if (similarity >= 52) return OriginalityVerdict.review;
    if (similarity >= 35) return OriginalityVerdict.inspired;
    return OriginalityVerdict.original;
  }

  OriginalityVerdict get verdict => verdictFor(similarity);
}

/// Runs [compareImages] in a background isolate.
Future<SimilarityReport?> compareImagesInBackground(
        Uint8List reference, Uint8List generated) =>
    Isolate.run(() => compareImages(reference, generated));

double _clamp01(double v) => v.isNaN ? 0 : v.clamp(0.0, 1.0).toDouble();

/// Maps a raw score where [base] is "typical for unrelated pictures" to 0
/// and 1 stays 1.
double _norm(double raw, double base) => _clamp01((raw - base) / (1 - base));

SimilarityReport? compareImages(Uint8List reference, Uint8List generated) {
  final a0 = img.decodeImage(reference);
  final b0 = img.decodeImage(generated);
  if (a0 == null || b0 == null) return null;
  // Same framing for both: centre-crop the wider picture to the narrower
  // aspect (a 9:16 wallpaper vs a 2:3 pin compares the shared centre).
  final ar = math.min(a0.width / a0.height, b0.width / b0.height);
  final a = _cropTo(a0, ar), b = _cropTo(b0, ar);
  // Mirrored copies are still copies: shape metrics take the better of
  // the straight and the horizontally flipped comparison.
  final bf = img.flipHorizontal(b.clone());

  final ga = _gray(a, 64, 64);
  final gb = _gray(b, 64, 64), gbf = _gray(bf, 64, 64);
  final eb = _edges(_gray(b, 34, 34), 34), ebf = _edges(_gray(bf, 34, 34), 34);
  final pb = _pHash(b), db = _dHash(b), pbf = _pHash(bf), dbf = _dHash(bf);
  var structure = 0.0, layout = 0.0, edge = 0.0;
  // Zoomed / cropped copies: also try centre crops of the reference.
  for (final scale in const [1.0, 0.82, 0.66]) {
    final ac = scale == 1.0
        ? a
        : img.copyCrop(a,
            x: (a.width * (1 - scale) / 2).round(),
            y: (a.height * (1 - scale) / 2).round(),
            width: (a.width * scale).round(),
            height: (a.height * scale).round());
    final pa = _pHash(ac), da = _dHash(ac);
    double st(List<bool> p, List<bool> d) =>
        _clamp01((2 - _hamming(pa, p) / 32.0 - _hamming(da, d) / 32.0) / 2);
    // 1. Structure fingerprint: perceptual + difference hash.
    structure = math.max(structure, math.max(st(pb, db), st(pbf, dbf)));
    // 2. Layout: SSIM on 64x64 luminance.
    final gac = scale == 1.0 ? ga : _gray(ac, 64, 64);
    layout = math.max(
        layout,
        math.max(_norm(_ssim(gac, gb, 64, 64), 0.12),
            _norm(_ssim(gac, gbf, 64, 64), 0.12)));
    // 3. Edges / shapes: correlation of the Sobel edge maps.
    final eac = _edges(_gray(ac, 34, 34), 34);
    edge = math.max(edge,
        math.max(_norm(_corr(eac, eb), 0.05), _norm(_corr(eac, ebf), 0.05)));
  }
  // 4. Colour palette: HSV histogram intersection.
  // Hue families (weighted by how colourful a pixel is, soft-binned so
  // violet vs purple is not "0 % shared") + a coarse value histogram, so
  // a bright and a dark version of the same palette still match.
  final (hueA, valA) = _colourHists(a);
  final (hueB, valB) = _colourHists(b);
  final colour = _norm(
      0.75 * _histIntersect(hueA, hueB) + 0.25 * _histIntersect(valA, valB),
      0.30);
  // 5. Tone: luminance histogram.
  final tone = _norm(_histIntersect(_lumHist(ga), _lumHist(gb)), 0.45);

  return SimilarityReport(
    metrics: [
      SimilarityMetric('structure', 'Structure fingerprint',
          'Perceptual hash of the overall shapes', structure, 0.30),
      SimilarityMetric('layout', 'Composition & layout',
          'Where light, dark and masses sit in the frame', layout, 0.25),
      SimilarityMetric('edges', 'Shapes & outlines',
          'Edge map - silhouettes, lines and contours', edge, 0.20),
      SimilarityMetric('colour', 'Colour palette',
          'Hue, saturation and value distribution', colour, 0.15),
      SimilarityMetric('tone', 'Tone & exposure',
          'Brightness distribution and contrast', tone, 0.10),
    ],
    paletteA: _palette(a),
    paletteB: _palette(b),
    sizeA: (a0.width, a0.height),
    sizeB: (b0.width, b0.height),
  );
}

img.Image _cropTo(img.Image im, double ar) {
  final r = im.width / im.height;
  if ((r - ar).abs() < 0.01) return im;
  if (r > ar) {
    final w = (im.height * ar).round();
    return img.copyCrop(im,
        x: (im.width - w) ~/ 2, y: 0, width: w, height: im.height);
  }
  final h = (im.width / ar).round();
  return img.copyCrop(im,
      x: 0, y: (im.height - h) ~/ 2, width: im.width, height: h);
}

Float64List _gray(img.Image im, int w, int h) {
  final s = img.copyResize(im,
      width: w, height: h, interpolation: img.Interpolation.average);
  final out = Float64List(w * h);
  var i = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = s.getPixel(x, y);
      out[i++] = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
    }
  }
  return out;
}

int _hamming(List<bool> a, List<bool> b) {
  var d = 0;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) d++;
  }
  return d;
}

List<bool> _dHash(img.Image im) {
  final g = _gray(im, 9, 8);
  return [
    for (var y = 0; y < 8; y++)
      for (var x = 0; x < 8; x++) g[y * 9 + x] > g[y * 9 + x + 1]
  ];
}

List<bool> _pHash(img.Image im) {
  const n = 32;
  final g = _gray(im, n, n);
  final dct = List.filled(64, 0.0);
  for (var u = 0; u < 8; u++) {
    for (var v = 0; v < 8; v++) {
      var s = 0.0;
      for (var y = 0; y < n; y++) {
        final cy = math.cos((2 * y + 1) * v * math.pi / (2 * n));
        for (var x = 0; x < n; x++) {
          s +=
              g[y * n + x] * math.cos((2 * x + 1) * u * math.pi / (2 * n)) * cy;
        }
      }
      dct[v * 8 + u] = s;
    }
  }
  final ac = dct.sublist(1)..sort();
  final median = ac[ac.length ~/ 2];
  return [for (var i = 0; i < 64; i++) dct[i] > median];
}

double _ssim(Float64List a, Float64List b, int w, int h) {
  const win = 8;
  const c1 = 6.5025, c2 = 58.5225; // (0.01*255)^2, (0.03*255)^2
  var total = 0.0;
  var count = 0;
  for (var y = 0; y + win <= h; y += win ~/ 2) {
    for (var x = 0; x + win <= w; x += win ~/ 2) {
      var ma = 0.0, mb = 0.0;
      for (var j = 0; j < win; j++) {
        for (var i = 0; i < win; i++) {
          ma += a[(y + j) * w + x + i];
          mb += b[(y + j) * w + x + i];
        }
      }
      ma /= win * win;
      mb /= win * win;
      var va = 0.0, vb = 0.0, cov = 0.0;
      for (var j = 0; j < win; j++) {
        for (var i = 0; i < win; i++) {
          final da = a[(y + j) * w + x + i] - ma;
          final db = b[(y + j) * w + x + i] - mb;
          va += da * da;
          vb += db * db;
          cov += da * db;
        }
      }
      const nn = win * win - 1;
      va /= nn;
      vb /= nn;
      cov /= nn;
      total += ((2 * ma * mb + c1) * (2 * cov + c2)) /
          ((ma * ma + mb * mb + c1) * (va + vb + c2));
      count++;
    }
  }
  return count == 0 ? 0 : total / count;
}

Float64List _edges(Float64List g, int n) {
  final out = Float64List((n - 2) * (n - 2));
  var k = 0;
  for (var y = 1; y < n - 1; y++) {
    for (var x = 1; x < n - 1; x++) {
      double p(int dx, int dy) => g[(y + dy) * n + x + dx];
      final gx = -p(-1, -1) -
          2 * p(-1, 0) -
          p(-1, 1) +
          p(1, -1) +
          2 * p(1, 0) +
          p(1, 1);
      final gy = -p(-1, -1) -
          2 * p(0, -1) -
          p(1, -1) +
          p(-1, 1) +
          2 * p(0, 1) +
          p(1, 1);
      out[k++] = math.sqrt(gx * gx + gy * gy);
    }
  }
  return out;
}

double _corr(Float64List a, Float64List b) {
  var ma = 0.0, mb = 0.0;
  for (var i = 0; i < a.length; i++) {
    ma += a[i];
    mb += b[i];
  }
  ma /= a.length;
  mb /= b.length;
  var cov = 0.0, va = 0.0, vb = 0.0;
  for (var i = 0; i < a.length; i++) {
    final da = a[i] - ma, db = b[i] - mb;
    cov += da * db;
    va += da * da;
    vb += db * db;
  }
  if (va <= 0 || vb <= 0) return 0;
  return cov / math.sqrt(va * vb);
}

/// 12 soft hue bins weighted by saturation (+1 grey bin) and 4 value
/// bins.
(List<double>, List<double>) _colourHists(img.Image im) {
  final s = img.copyResize(im, width: 64, height: 64);
  final hue = List.filled(13, 0.0), val = List.filled(4, 0.0);
  for (final p in s) {
    final (hu, sa, va) = _hsv(p.r.toDouble(), p.g.toDouble(), p.b.toDouble());
    val[math.min(3, (va * 4).floor())] += 1;
    final w = (sa * math.min(1.0, va * 1.6)).clamp(0.0, 1.0);
    hue[12] += 1 - w;
    if (w > 0) {
      final pos = hu / 30 - 0.5;
      final i0 = pos.floor(), f = pos - i0;
      hue[i0 % 12] += w * (1 - f);
      hue[(i0 + 1) % 12] += w * f;
    }
  }
  List<double> n(List<double> h) {
    final t = h.fold<double>(0, (a, b) => a + b);
    return [for (final v in h) t == 0 ? 0 : v / t];
  }

  return (n(hue), n(val));
}

List<double> _lumHist(Float64List g) {
  final h = List.filled(16, 0.0);
  for (final v in g) {
    h[math.min(15, (v / 16).floor())] += 1;
  }
  return [for (final v in h) v / g.length];
}

double _histIntersect(List<double> a, List<double> b) {
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += math.min(a[i], b[i]);
  }
  return s;
}

(double, double, double) _hsv(double r, double g, double b) {
  r /= 255;
  g /= 255;
  b /= 255;
  final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
  final d = mx - mn;
  var h = 0.0;
  if (d > 0) {
    if (mx == r) {
      h = 60 * (((g - b) / d) % 6);
    } else if (mx == g) {
      h = 60 * ((b - r) / d + 2);
    } else {
      h = 60 * ((r - g) / d + 4);
    }
  }
  if (h < 0) h += 360;
  return (h, mx == 0 ? 0 : d / mx, mx);
}

/// Five dominant colours via a coarse 4-bit-per-channel histogram.
List<int> _palette(img.Image im) {
  final s = img.copyResize(im, width: 48, height: 48);
  final counts = <int, int>{};
  final sums = <int, List<int>>{};
  for (final p in s) {
    final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
    final k = (r >> 5) << 6 | (g >> 5) << 3 | (b >> 5);
    counts[k] = (counts[k] ?? 0) + 1;
    final acc = sums.putIfAbsent(k, () => [0, 0, 0]);
    acc[0] += r;
    acc[1] += g;
    acc[2] += b;
  }
  final keys = counts.keys.toList()
    ..sort((x, y) => counts[y]!.compareTo(counts[x]!));
  final out = <int>[];
  for (final k in keys) {
    final n = counts[k]!, acc = sums[k]!;
    final c =
        0xFF000000 | (acc[0] ~/ n) << 16 | (acc[1] ~/ n) << 8 | (acc[2] ~/ n);
    // Skip near-duplicates of an already chosen colour.
    final dup = out.any((o) =>
        ((o >> 16 & 255) - (c >> 16 & 255)).abs() +
            ((o >> 8 & 255) - (c >> 8 & 255)).abs() +
            ((o & 255) - (c & 255)).abs() <
        60);
    if (!dup) out.add(c);
    if (out.length == 5) break;
  }
  return out;
}
