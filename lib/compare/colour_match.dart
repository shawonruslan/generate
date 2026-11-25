import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Measurable look of a reference picture, written into the
/// image_to_image prompt so the model aims at the same colours/exposure.
class ReferenceLook {
  const ReferenceLook(this.paletteHex, this.tone);
  final List<String> paletteHex;
  final String tone;
}

Future<ReferenceLook?> referenceLookInBackground(Uint8List bytes) =>
    Isolate.run(() => referenceLook(bytes));

ReferenceLook? referenceLook(Uint8List bytes) {
  final im = img.decodeImage(bytes);
  if (im == null) return null;
  final s = img.copyResize(im, width: 48, height: 48);
  final counts = <int, int>{};
  final sums = <int, List<int>>{};
  var lum = 0.0, lum2 = 0.0, n = 0;
  for (final p in s) {
    final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
    final y = 0.299 * r + 0.587 * g + 0.114 * b;
    lum += y;
    lum2 += y * y;
    n++;
    final k = (r >> 5) << 6 | (g >> 5) << 3 | (b >> 5);
    counts[k] = (counts[k] ?? 0) + 1;
    final acc = sums.putIfAbsent(k, () => [0, 0, 0]);
    acc[0] += r;
    acc[1] += g;
    acc[2] += b;
  }
  final keys = counts.keys.toList()
    ..sort((x, y) => counts[y]!.compareTo(counts[x]!));
  final out = <List<int>>[];
  for (final k in keys) {
    final c = counts[k]!, a = sums[k]!;
    final rgb = [a[0] ~/ c, a[1] ~/ c, a[2] ~/ c];
    final dup = out.any((o) =>
        (o[0] - rgb[0]).abs() + (o[1] - rgb[1]).abs() + (o[2] - rgb[2]).abs() <
        60);
    if (!dup) out.add(rgb);
    if (out.length == 5) break;
  }
  final mean = lum / n;
  final sd = math.sqrt(math.max(0, lum2 / n - mean * mean));
  final key = mean < 70
      ? 'dark low-key exposure'
      : mean > 170
          ? 'bright high-key exposure'
          : 'mid-key exposure';
  final contrast = sd > 70
      ? 'high contrast'
      : sd < 35
          ? 'soft low contrast'
          : 'medium contrast';
  String hex(List<int> c) =>
      '#${c.map((v) => v.toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';
  return ReferenceLook([for (final c in out) hex(c)], '$key, $contrast');
}

/// How strongly the colours/tone of the reference are transferred for a
/// similarity target: 90 % -> 0.9, 60 % -> 0.45, <= 30 % -> 0.
double colourAmountFor(int target) =>
    ((target - 30) / 60).clamp(0.0, 1.0) * 0.9;

/// Reinhard colour transfer in Lab: moves the mean/spread of every Lab
/// channel of [generated] towards [reference] by [amount] (0..1).
/// Returns a JPEG, or null when nothing was changed.
Future<Uint8List?> matchColoursInBackground(
        Uint8List generated, Uint8List reference, double amount) =>
    Isolate.run(() => matchColours(generated, reference, amount));

Uint8List? matchColours(Uint8List generated, Uint8List reference, double amount) {
  if (amount <= 0.02) return null;
  final g = img.decodeImage(generated), r = img.decodeImage(reference);
  if (g == null || r == null) return null;
  List<List<double>> stats(img.Image im) {
    final s = img.copyResize(im, width: 96, height: 96 * im.height ~/ im.width);
    final sum = [0.0, 0.0, 0.0], sq = [0.0, 0.0, 0.0];
    var n = 0;
    for (final p in s) {
      final lab = _lab(p.r.toDouble(), p.g.toDouble(), p.b.toDouble());
      for (var i = 0; i < 3; i++) {
        sum[i] += lab[i];
        sq[i] += lab[i] * lab[i];
      }
      n++;
    }
    final m = [for (var i = 0; i < 3; i++) sum[i] / n];
    final sd = [
      for (var i = 0; i < 3; i++)
        math.sqrt(math.max(1e-6, sq[i] / n - m[i] * m[i]))
    ];
    return [m, sd];
  }

  final sg = stats(g), sr = stats(r);
  final a = amount.clamp(0.0, 1.0);
  final out = img.Image(width: g.width, height: g.height);
  for (final p in g) {
    final lab = _lab(p.r.toDouble(), p.g.toDouble(), p.b.toDouble());
    for (var i = 0; i < 3; i++) {
      // Spread ratio is capped so flat references do not crush detail.
      final k = (sr[1][i] / sg[1][i]).clamp(0.5, 2.0);
      final t = (lab[i] - sg[0][i]) * k + sr[0][i];
      lab[i] = lab[i] + (t - lab[i]) * a;
    }
    final rgb = _rgb(lab[0], lab[1], lab[2]);
    out.setPixelRgb(p.x, p.y, rgb[0], rgb[1], rgb[2]);
  }
  return Uint8List.fromList(img.encodeJpg(out, quality: 94));
}

double _lin(double c) {
  c /= 255;
  return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

int _gam(double c) {
  final v = c <= 0.0031308 ? 12.92 * c : 1.055 * math.pow(c, 1 / 2.4) - 0.055;
  return (v * 255).round().clamp(0, 255);
}

double _f(double t) =>
    t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;

double _fi(double t) => t * t * t > 0.008856 ? t * t * t : (t - 16 / 116) / 7.787;

List<double> _lab(double r, double g, double b) {
  final lr = _lin(r), lg = _lin(g), lb = _lin(b);
  final x = (lr * 0.4124 + lg * 0.3576 + lb * 0.1805) / 0.95047;
  final y = lr * 0.2126 + lg * 0.7152 + lb * 0.0722;
  final z = (lr * 0.0193 + lg * 0.1192 + lb * 0.9505) / 1.08883;
  final fx = _f(x), fy = _f(y), fz = _f(z);
  return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)];
}

List<int> _rgb(double l, double a, double bb) {
  final fy = (l + 16) / 116, fx = fy + a / 500, fz = fy - bb / 200;
  final x = _fi(fx) * 0.95047, y = _fi(fy), z = _fi(fz) * 1.08883;
  final r = x * 3.2406 - y * 1.5372 - z * 0.4986;
  final g = -x * 0.9689 + y * 1.8758 + z * 0.0415;
  final b = x * 0.0557 - y * 0.2040 + z * 1.0570;
  return [_gam(r), _gam(g), _gam(b)];
}
