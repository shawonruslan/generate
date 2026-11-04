import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';

/// ===========================================================================
/// Diary book widgets — flat-design book look matching the web app's 3D diary.
/// Data formats mirror index-12.html exactly so web and mobile stay
/// interchangeable:
///  - 1000-unit page space for drawings & stickers (page width = 1000 units)
///  - mini-markup for formatted text: <c k="red"> <m k="yellow"> <u> <s>
///    <z k="sm|md|lg|xl">, HTML-escaped text, \n line breaks
///  - strokes: {t:'p|b|e|r|a', c:colorKey, d:[x,y,...]}
///  - stickers: {id,x,y,w,a,r,k} (signed 'u' URL stripped on save)
/// NO gradients, NO neon — flat solid colors only.
/// ===========================================================================

// ---------------- constants (mirror web DY_PEN / DY_MARK / DY_MOODS) --------

/// Default ink when no color key is set (web DY_DC['']).
const Color diaryDefaultInk = Color(0xFF1E2F6E);

const Map<String, Color> diaryPenColors = {
  '': diaryDefaultInk,
  'black': Color(0xFF1F2328),
  'red': Color(0xFFC0262D),
  'green': Color(0xFF15803D),
  'purple': Color(0xFF6D28D9),
  'brown': Color(0xFF92400E),
};
const List<String> diaryPenKeys = [
  '',
  'black',
  'red',
  'green',
  'purple',
  'brown'
];

const Map<String, Color> diaryMarkColors = {
  'yellow': Color(0xFFFFF27A),
  'green': Color(0xFFB9F5B0),
  'pink': Color(0xFFFFC2DC),
  'blue': Color(0xFFBDE3FF),
  'orange': Color(0xFFFFD59E),
};
const List<String> diaryMarkKeys = [
  'yellow',
  'green',
  'pink',
  'blue',
  'orange'
];

/// (key, label, emoji) — mirrors web DY_MOODS.
const List<(String, String, String)> diaryMoods = [
  ('happy', 'Happy', '😊'),
  ('calm', 'Calm', '😌'),
  ('love', 'Love', '😍'),
  ('excited', 'Excited', '🤩'),
  ('tired', 'Tired', '😴'),
  ('sad', 'Sad', '😢'),
  ('angry', 'Angry', '😠'),
];

String diaryMoodEmoji(String mood) {
  for (final m in diaryMoods) {
    if (m.$1 == mood) return m.$3;
  }
  return '';
}

/// Size keys (web <z k="sm|md|lg|xl">) → font scale.
const Map<String, double> diarySizeScale = {
  'sm': 0.8,
  'md': 1.0,
  'lg': 1.3,
  'xl': 1.6,
};

// Flat book palette.
const Color diaryPaper = Color(0xFFFBF5E6);
const Color diaryPaperLine = Color(0xFFB9CBE8); // light-blue ruled lines
const Color diaryPaperMargin = Color(0xFFE0A3A3);
const Color diaryDesk = Color(0xFF231709);
const Color diaryDeskBar = Color(0xFF2E1F10);
const Color diaryGold = Color(0xFFE7C27A);
const Color diaryLeather = Color(0xFF4A2112);
const Color diaryPeach = Color(0xFFF0A583); // active tool highlight
const Color diaryDateBrown = Color(0xFF7C2D12); // web .dy-num date brown
const Color diaryEntryBrown = Color(0xFF9A3412); // entries modal numeral brown
const Color diaryCoverBrown = Color(0xFF5A3A1C);
const Color diaryCoverDark = Color(0xFF412712);
const Color diaryCoverBand = Color(0xFF6B4A24);
const Color diaryRibbonRed = Color(0xFFB91C1C);
const Color diaryInkBrown = Color(0xFF5A3A1C);
const Color diaryMutedBrown = Color(0xFF8A6D4B);
const Color diaryPlaceholder = Color(0xFF9B9B9B);

// ---------------- mini-markup (<c>/<m>/<u>/<s>/<z>) -------------------------

/// One styled range: [start, end) over the plain text.
class DiaryFmt {
  String? color; // pen key
  String? mark; // marker key
  bool u;
  bool s;
  String? size; // sm|md|lg|xl
  DiaryFmt({this.color, this.mark, this.u = false, this.s = false, this.size});
  DiaryFmt clone() =>
      DiaryFmt(color: color, mark: mark, u: u, s: s, size: size);
  bool get isEmpty =>
      color == null && mark == null && !u && !s && size == null;
  bool sameAs(DiaryFmt o) =>
      color == o.color &&
      mark == o.mark &&
      u == o.u &&
      s == o.s &&
      size == o.size;
  void clearAttr(String attr) {
    switch (attr) {
      case 'c':
        color = null;
        break;
      case 'm':
        mark = null;
        break;
      case 'u':
        u = false;
        break;
      case 's':
        s = false;
        break;
      case 'z':
        size = null;
        break;
    }
  }

  void setAttr(String attr, String key) {
    switch (attr) {
      case 'c':
        color = key;
        break;
      case 'm':
        mark = key;
        break;
      case 'u':
        u = true;
        break;
      case 's':
        s = true;
        break;
      case 'z':
        size = key;
        break;
    }
  }
}

class DiarySpan {
  int start;
  int end;
  DiaryFmt fmt;
  DiarySpan(this.start, this.end, this.fmt);
}

class _OpenTag {
  final String tag;
  final String? key;
  final int start;
  _OpenTag(this.tag, this.key, this.start);
}

String _esc(String t) => t
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
String _unesc(String t) => t
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&');

void _applyTag(DiaryFmt f, String tag, String? key) {
  switch (tag) {
    case 'c':
      if (key != null && key.isNotEmpty) f.color = key;
      break;
    case 'm':
      if (key != null && key.isNotEmpty) f.mark = key;
      break;
    case 'u':
      f.u = true;
      break;
    case 's':
      f.s = true;
      break;
    case 'z':
      if (key != null && key.isNotEmpty) f.size = key;
      break;
  }
}

List<DiarySpan> _mergeSpans(List<DiarySpan> spans) {
  final clean = spans
      .where((s) => s.start < s.end && !s.fmt.isEmpty)
      .toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  final out = <DiarySpan>[];
  for (final s in clean) {
    if (out.isNotEmpty &&
        out.last.end == s.start &&
        out.last.fmt.sameAs(s.fmt)) {
      out.last.end = s.end;
    } else {
      out.add(DiarySpan(s.start, s.end, s.fmt.clone()));
    }
  }
  return out;
}

/// Parse web mini-markup → (plainText, spans). Mirrors dyParseMk.
(String, List<DiarySpan>) parseDiaryMarkup(String mk) {
  final text = StringBuffer();
  final spans = <DiarySpan>[];
  final stack = <_OpenTag>[];
  final re = RegExp(r'<(\/?)(c|m|u|s|z)(?: k="([a-z]+)")?>|([^<]+)|<');
  void closeFrom(int idx) {
    final removed = stack.sublist(idx);
    stack.removeRange(idx, stack.length);
    for (final o in removed) {
      if (text.length > o.start) {
        final f = DiaryFmt();
        _applyTag(f, o.tag, o.key);
        if (!f.isEmpty) spans.add(DiarySpan(o.start, text.length, f));
      }
    }
  }

  for (final m in re.allMatches(mk)) {
    final txt = m.group(4);
    if (txt != null) {
      text.write(_unesc(txt));
      continue;
    }
    final tag = m.group(2);
    if (tag == null) {
      text.write('<');
      continue;
    }
    if (m.group(1) == '/') {
      var idx = -1;
      for (var i = stack.length - 1; i >= 0; i--) {
        if (stack[i].tag == tag) {
          idx = i;
          break;
        }
      }
      if (idx >= 0) closeFrom(idx);
    } else {
      stack.add(_OpenTag(tag, m.group(3), text.length));
    }
  }
  if (stack.isNotEmpty) closeFrom(0);
  return (text.toString(), _mergeSpans(spans));
}

/// Serialize plain text + spans → web mini-markup. Mirrors dySer.
String serializeDiaryMarkup(String text, List<DiarySpan> spans) {
  final clean = _mergeSpans(spans)
      .map((s) => DiarySpan(s.start.clamp(0, text.length),
          s.end.clamp(0, text.length), s.fmt))
      .where((s) => s.start < s.end)
      .toList();
  final bounds = <int>{0, text.length};
  for (final s in clean) {
    bounds.add(s.start);
    bounds.add(s.end);
  }
  final bs = bounds.toList()..sort();

  List<(String, String?)> tagsOf(DiaryFmt f) {
    final t = <(String, String?)>[];
    if (f.color != null) t.add(('c', f.color));
    if (f.mark != null) t.add(('m', f.mark));
    if (f.u) t.add(('u', null));
    if (f.s) t.add(('s', null));
    if (f.size != null) t.add(('z', f.size));
    return t;
  }

  DiaryFmt mergedAt(int a, int b) {
    final f = DiaryFmt();
    for (final sp in clean.where((sp) => sp.start <= a && sp.end >= b)) {
      if (sp.fmt.color != null) f.color = sp.fmt.color;
      if (sp.fmt.mark != null) f.mark = sp.fmt.mark;
      if (sp.fmt.u) f.u = true;
      if (sp.fmt.s) f.s = true;
      if (sp.fmt.size != null) f.size = sp.fmt.size;
    }
    return f;
  }

  final buf = StringBuffer();
  var prev = <(String, String?)>[];
  for (var i = 0; i < bs.length - 1; i++) {
    final a = bs[i], b = bs[i + 1];
    if (a >= b) continue;
    final cur = tagsOf(mergedAt(a, b));
    var common = 0;
    while (common < prev.length &&
        common < cur.length &&
        prev[common] == cur[common]) {
      common++;
    }
    for (var j = prev.length - 1; j >= common; j--) {
      buf.write('</${prev[j].$1}>');
    }
    for (var j = common; j < cur.length; j++) {
      final tag = cur[j].$1, key = cur[j].$2;
      buf.write(key != null ? '<$tag k="$key">' : '<$tag>');
    }
    buf.write(_esc(text.substring(a, b)));
    prev = cur;
  }
  for (var j = prev.length - 1; j >= 0; j--) {
    buf.write('</${prev[j].$1}>');
  }
  return buf.toString().replaceAll(RegExp(r'\n+$'), '');
}

/// Set attribute [attr] ('c','m','u','s','z') to [key] over [s,e).
/// Empty key clears the attribute. Mirrors web dyFmt over a selection.
List<DiarySpan> diarySetAttr(
    List<DiarySpan> spans, int s, int e, String attr, String key) {
  if (s >= e) return spans;
  final out = <DiarySpan>[];
  for (final sp in spans) {
    if (sp.end <= s || sp.start >= e) {
      out.add(sp);
      continue;
    }
    if (sp.start < s) out.add(DiarySpan(sp.start, s, sp.fmt.clone()));
    if (sp.end > e) out.add(DiarySpan(e, sp.end, sp.fmt.clone()));
    final mid = sp.fmt.clone()..clearAttr(attr);
    final ms = math.max(sp.start, s), me = math.min(sp.end, e);
    if (me > ms && !mid.isEmpty) out.add(DiarySpan(ms, me, mid));
  }
  if (key.isNotEmpty) {
    final f = DiaryFmt()..setAttr(attr, key);
    out.add(DiarySpan(s, e, f));
  }
  return _mergeSpans(out);
}

/// Remove every attribute over [s,e).
List<DiarySpan> diaryClearRange(List<DiarySpan> spans, int s, int e) {
  if (s >= e) return spans;
  final out = <DiarySpan>[];
  for (final sp in spans) {
    if (sp.end <= s || sp.start >= e) {
      out.add(sp);
      continue;
    }
    if (sp.start < s) out.add(DiarySpan(sp.start, s, sp.fmt.clone()));
    if (sp.end > e) out.add(DiarySpan(e, sp.end, sp.fmt.clone()));
  }
  return _mergeSpans(out);
}

/// Adjust spans after replacing text range [a,b) with [newLen] chars.
/// Spans touching the edited region are dropped; the rest shift.
List<DiarySpan> diaryShiftOnEdit(
    List<DiarySpan> spans, int a, int b, int newLen) {
  final delta = newLen - (b - a);
  final out = <DiarySpan>[];
  for (final sp in spans) {
    if (sp.end <= a) {
      out.add(sp);
    } else if (sp.start >= b) {
      out.add(DiarySpan(sp.start + delta, sp.end + delta, sp.fmt));
    }
  }
  return out;
}

/// Build styled inline spans for read mode. Base text uses the default
/// diary ink on ruled lines.
List<InlineSpan> buildDiaryTextSpans(String text, List<DiarySpan> spans,
    {double fontSize = 17, double lineHeight = 1.75}) {
  final clean = _mergeSpans(spans)
      .map((sp) => DiarySpan(sp.start.clamp(0, text.length),
          sp.end.clamp(0, text.length), sp.fmt))
      .where((sp) => sp.start < sp.end)
      .toList();
  final bounds = <int>{0, text.length};
  for (final sp in clean) {
    bounds.add(sp.start);
    bounds.add(sp.end);
  }
  final bs = bounds.toList()..sort();
  final out = <InlineSpan>[];
  for (var i = 0; i < bs.length - 1; i++) {
    final a = bs[i], b = bs[i + 1];
    if (a >= b) continue;
    String? color;
    String? mark;
    var u = false, s = false;
    String? size;
    for (final sp in clean.where((sp) => sp.start <= a && sp.end >= b)) {
      if (sp.fmt.color != null) color = sp.fmt.color;
      if (sp.fmt.mark != null) mark = sp.fmt.mark;
      if (sp.fmt.u) u = true;
      if (sp.fmt.s) s = true;
      if (sp.fmt.size != null) size = sp.fmt.size;
    }
    out.add(TextSpan(
      text: text.substring(a, b),
      style: TextStyle(
        fontFamily: 'serif',
        fontSize: fontSize * (diarySizeScale[size] ?? 1.0),
        height: lineHeight,
        color: color != null
            ? (diaryPenColors[color] ?? diaryDefaultInk)
            : diaryDefaultInk,
        backgroundColor: mark != null ? diaryMarkColors[mark] : null,
        decoration: TextDecoration.combine([
          if (u) TextDecoration.underline,
          if (s) TextDecoration.lineThrough,
        ]),
      ),
    ));
  }
  return out;
}

// ---------------- date helpers ----------------

int diaryDayOfYear(DateTime d) =>
    d.difference(DateTime(d.year, 1, 1)).inDays + 1;

DateTime diaryDateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Extra vertical units a page needs below the text for stickers/drawings.
double diaryNeededUnits(DiaryEntry? e) {
  var m = 0.0;
  for (final st in e?.stickers ?? <DiarySticker>[]) {
    m = math.max(m, st.y + st.w * st.a + 60);
  }
  for (final s in e?.draw ?? <DiaryStroke>[]) {
    for (var i = 1; i < s.d.length; i += 2) {
      m = math.max(m, s.d[i].toDouble() + 60);
    }
  }
  return m;
}

// ---------------- painters ----------------

/// Ruled lines + red margin on paper.
class LinedPaperPainter extends CustomPainter {
  final double lineGap;
  final double topOffset;
  const LinedPaperPainter({this.lineGap = 30, this.topOffset = 10});
  @override
  void paint(Canvas canvas, Size size) {
    final lp = Paint()
      ..color = diaryPaperLine
      ..strokeWidth = 1;
    for (var y = topOffset; y < size.height; y += lineGap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), lp);
    }
    final mp = Paint()
      ..color = diaryPaperMargin
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(52, 0), Offset(52, size.height), mp);
  }

  @override
  bool shouldRepaint(LinedPaperPainter old) =>
      old.lineGap != lineGap || old.topOffset != topOffset;
}

/// Renders diary strokes. The canvas is the web's 1000-unit page space
/// scaled uniformly, exactly like the web SVG draw layer.
class DrawingPainter extends CustomPainter {
  final List<DiaryStroke> strokes;
  final DiaryStroke? live;
  const DrawingPainter({required this.strokes, this.live});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 1000.0;
    canvas.save();
    canvas.scale(s);
    for (final st in strokes) {
      _paintStroke(canvas, st);
    }
    final l = live;
    if (l != null) _paintStroke(canvas, l);
    canvas.restore();
  }

  void _paintStroke(Canvas canvas, DiaryStroke st) {
    final isMark = st.t == 'b';
    final color = isMark
        ? (diaryMarkColors[st.c] ?? diaryMarkColors['yellow']!)
        : (diaryPenColors[st.c] ?? diaryDefaultInk);
    final paint = Paint()
      ..color = isMark ? color.withOpacity(0.55) : color
      ..strokeWidth = isMark ? 34 : 6.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final d = st.d;
    if (d.length < 2) return;
    switch (st.t) {
      case 'p':
      case 'b':
        {
          final pts = <Offset>[];
          for (var i = 0; i + 1 < d.length; i += 2) {
            pts.add(Offset(d[i].toDouble(), d[i + 1].toDouble()));
          }
          if (pts.length == 1) {
            canvas.drawCircle(pts[0], paint.strokeWidth / 2,
                paint..style = PaintingStyle.fill);
            return;
          }
          final path = Path()..moveTo(pts[0].dx, pts[0].dy);
          for (var i = 1; i < pts.length - 1; i++) {
            final mx = (pts[i].dx + pts[i + 1].dx) / 2;
            final my = (pts[i].dy + pts[i + 1].dy) / 2;
            path.quadraticBezierTo(pts[i].dx, pts[i].dy, mx, my);
          }
          path.lineTo(pts.last.dx, pts.last.dy);
          canvas.drawPath(path, paint);
          return;
        }
      case 'e':
        if (d.length < 4) return;
        canvas.drawOval(
            Rect.fromPoints(Offset(d[0].toDouble(), d[1].toDouble()),
                Offset(d[2].toDouble(), d[3].toDouble())),
            paint);
        return;
      case 'r':
        if (d.length < 4) return;
        canvas.drawRect(
            Rect.fromPoints(Offset(d[0].toDouble(), d[1].toDouble()),
                Offset(d[2].toDouble(), d[3].toDouble())),
            paint);
        return;
      case 'a':
        {
          if (d.length < 4) return;
          final p1 = Offset(d[0].toDouble(), d[1].toDouble());
          final p2 = Offset(d[2].toDouble(), d[3].toDouble());
          canvas.drawLine(p1, p2, paint);
          final ang = math.atan2(p2.dy - p1.dy, p2.dx - p1.dx);
          final len = (p2 - p1).distance;
          final hl = math.min(34, len * 0.4);
          for (final sd in [0.5, -0.5]) {
            final e = Offset(p2.dx - math.cos(ang + sd) * hl,
                p2.dy - math.sin(ang + sd) * hl);
            canvas.drawLine(p2, e, paint);
          }
          return;
        }
    }
  }

  @override
  bool shouldRepaint(DrawingPainter old) =>
      old.strokes != strokes || old.live != live;
}

class _RibbonClipper extends CustomClipper<Path> {
  final double notch;
  const _RibbonClipper({this.notch = 8});
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width / 2, size.height - notch)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(_RibbonClipper old) => old.notch != notch;
}

/// Small red "TODAY" ribbon pinned at the top of today's page.
class TodayRibbon extends StatelessWidget {
  const TodayRibbon({super.key});
  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const _RibbonClipper(notch: 7),
      child: Container(
        color: diaryRibbonRed,
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 13),
        child: const Text('TODAY',
            style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5)),
      ),
    );
  }
}

/// Long red bookmark ribbon hanging over the page edge (spread mode).
class BookmarkRibbon extends StatelessWidget {
  final double width;
  final double length;
  const BookmarkRibbon({super.key, this.width = 20, this.length = 110});
  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const _RibbonClipper(notch: 9),
      child: Container(width: width, height: length, color: diaryRibbonRed),
    );
  }
}

class _CoverDecorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gold = Paint()
      ..color = diaryGold.withOpacity(0.85)
      ..strokeWidth = 1.6;
    const inset = 15.0;
    final r = Rect.fromLTWH(
        inset, inset, size.width - inset * 2, size.height - inset * 2);
    _dashRect(canvas, r, gold, 7, 5);
    // corner protectors
    final tri = Paint()..color = diaryGold;
    const c = 26.0;
    for (final sx in [1.0, -1.0]) {
      for (final sy in [1.0, -1.0]) {
        final x = sx > 0 ? size.width : 0.0;
        final y = sy > 0 ? size.height : 0.0;
        canvas.drawPath(
            Path()
              ..moveTo(x, y)
              ..lineTo(x - sx * c, y)
              ..lineTo(x, y - sy * c)
              ..close(),
            tri);
      }
    }
  }

  void _dashRect(Canvas canvas, Rect r, Paint p, double dash, double gap) {
    _dashLine(
        canvas, Offset(r.left, r.top), Offset(r.right, r.top), p, dash, gap);
    _dashLine(
        canvas, Offset(r.right, r.top), Offset(r.right, r.bottom), p, dash, gap);
    _dashLine(canvas, Offset(r.right, r.bottom), Offset(r.left, r.bottom), p,
        dash, gap);
    _dashLine(
        canvas, Offset(r.left, r.bottom), Offset(r.left, r.top), p, dash, gap);
  }

  void _dashLine(
      Canvas canvas, Offset a, Offset b, Paint p, double dash, double gap) {
    final total = (b - a).distance;
    if (total <= 0) return;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final e = math.min(d + dash, total);
      canvas.drawLine(a + dir * d, a + dir * e, p);
      d = e + gap;
    }
  }

  @override
  bool shouldRepaint(_CoverDecorPainter old) => false;
}

class _FeatherPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = diaryGold
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final w = size.width, h = size.height;
    canvas.drawLine(
        Offset(w * 0.72, h * 0.86), Offset(w * 0.3, h * 0.2), p);
    canvas.drawPath(
        Path()
          ..moveTo(w * 0.3, h * 0.2)
          ..quadraticBezierTo(w * 0.62, h * 0.22, w * 0.58, h * 0.52)
          ..quadraticBezierTo(w * 0.44, h * 0.5, w * 0.3, h * 0.2),
        p);
    canvas.drawPath(
        Path()
          ..moveTo(w * 0.3, h * 0.2)
          ..quadraticBezierTo(w * 0.24, h * 0.44, w * 0.4, h * 0.6)
          ..quadraticBezierTo(w * 0.34, h * 0.4, w * 0.3, h * 0.2),
        p);
  }

  @override
  bool shouldRepaint(_FeatherPainter old) => false;
}

// ---------------- book cover ----------------

/// Flat-design closed book cover. Tap to open.
class DiaryBookCover extends StatelessWidget {
  final String username;
  final int year;
  final VoidCallback onOpen;
  const DiaryBookCover(
      {super.key,
      required this.username,
      required this.year,
      required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, bc) {
      final w = math.max(
          120.0, math.min(bc.maxWidth - 48, (bc.maxHeight - 130) * 0.72));
      final h = w / 0.72;
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 46),
            child: InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: w,
                height: h,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: diaryLeather,
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: diaryCoverDark, width: 2),
                        boxShadow: const [
                          BoxShadow(
                              color: Colors.black54,
                              blurRadius: 22,
                              offset: Offset(0, 10)),
                        ],
                      ),
                    ),
                    Positioned.fill(
                        child: CustomPaint(
                            painter: _CoverDecorPainter())),
                    // spine
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: 52,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: diaryCoverDark,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(8),
                            bottomLeft: Radius.circular(8),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceEvenly,
                          children: List.generate(
                              4,
                              (_) => Container(
                                    height: 9,
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 10),
                                    decoration: BoxDecoration(
                                      color: diaryCoverBand,
                                      borderRadius:
                                          BorderRadius.circular(4),
                                    ),
                                  )),
                        ),
                      ),
                    ),
                    // center content
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                            72, 28, 24, 28),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 84,
                              height: 84,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: diaryGold, width: 2.5),
                              ),
                              child: CustomPaint(
                                  painter: _FeatherPainter()),
                            ),
                            const SizedBox(height: 18),
                            const Text('My Diary',
                                style: TextStyle(
                                    fontFamily: 'serif',
                                    fontSize: 36,
                                    fontWeight: FontWeight.w600,
                                    color: diaryGold,
                                    letterSpacing: 1)),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              children: [
                                Container(
                                    width: 44,
                                    height: 1.5,
                                    color: diaryGold),
                                Container(
                                  width: 9,
                                  height: 9,
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 8),
                                  transform: Matrix4.rotationZ(
                                      math.pi / 4),
                                  color: diaryGold,
                                ),
                                Container(
                                    width: 44,
                                    height: 1.5,
                                    color: diaryGold),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text('$year',
                                style: const TextStyle(
                                    color: diaryGold,
                                    fontSize: 18,
                                    letterSpacing: 6)),
                            const SizedBox(height: 22),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 22, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.black26,
                                borderRadius:
                                    BorderRadius.circular(6),
                                border: Border.all(
                                    color: diaryGold, width: 1.5),
                              ),
                              child: Column(
                                children: [
                                  const Text('BELONGS TO',
                                      style: TextStyle(
                                          color: diaryGold,
                                          fontSize: 10,
                                          letterSpacing: 3)),
                                  const SizedBox(height: 2),
                                  Text(username,
                                      style: const TextStyle(
                                          fontFamily: 'serif',
                                          fontStyle:
                                              FontStyle.italic,
                                          fontSize: 22,
                                          color:
                                              Color(0xFFF3E3B3))),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // bookmark ribbon hanging off the bottom
                    const Positioned(
                      bottom: -42,
                      left: 0,
                      right: 0,
                      child: Center(
                          child: ClipPath(
                        clipper: _RibbonClipper(notch: 8),
                        child: SizedBox(
                          width: 26,
                          height: 66,
                          child: ColoredBox(
                              color: diaryRibbonRed),
                        ),
                      )),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.touch_app_outlined,
                  size: 18, color: Color(0xFF9C8B6E)),
              SizedBox(width: 8),
              Text('CLICK KORE KHOLUN',
                  style: TextStyle(
                      color: Color(0xFF9C8B6E),
                      fontSize: 13,
                      letterSpacing: 2.5,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      );
    });
  }
}

// ---------------- page furniture ----------------

const List<String> _weekdays = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday'
];
const List<String> _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December'
];

/// Page header: big day number, weekday + month/year, mood stamp.
/// Mirrors the web .dy-hd: Playfair-italic numeral, script weekday,
/// gray caps month/year, light-blue rule below.
class DiaryPageHeader extends StatelessWidget {
  final DateTime date;
  final String mood;
  const DiaryPageHeader({super.key, required this.date, this.mood = ''});
  @override
  Widget build(BuildContext context) {
    final emoji = diaryMoodEmoji(mood);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
              bottom: BorderSide(
                  color: Color(0x473C5AA0), width: 2)), // rgba(60,90,160,.28)
        ),
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${date.day}',
                style: TextStyle(
                    fontFamily: 'serif',
                    fontStyle: FontStyle.italic,
                    fontSize: 48,
                    fontWeight: FontWeight.w600,
                    color: diaryDateBrown.withOpacity(0.85),
                    height: 1)),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_weekdays[date.weekday % 7],
                      style: const TextStyle(
                          fontFamily: 'serif',
                          fontStyle: FontStyle.italic,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: diaryDateBrown)),
                  Text(
                      '${_months[date.month - 1]} ${date.year}'
                          .toUpperCase(),
                      style: TextStyle(
                          fontSize: 12,
                          letterSpacing: 1.5,
                          color: Colors.grey[600])),
                ],
              ),
            ),
            const Spacer(),
            if (emoji.isNotEmpty)
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: diaryGold, width: 1.5),
                  color: const Color(0xFFFFFDF5),
                ),
                child: Center(
                    child:
                        Text(emoji, style: const TextStyle(fontSize: 22))),
              ),
          ],
        ),
      ),
    );
  }
}

/// Page footer: "likha:" timestamp + day-of-year page number.
class DiaryPageFooter extends StatelessWidget {
  final DateTime date;
  final int? at; // ms epoch, null/0 → no likha stamp
  const DiaryPageFooter({super.key, required this.date, this.at});
  @override
  Widget build(BuildContext context) {
    final likha = at != null && at! > 0
        ? 'likha: ${DateFormat('MMM d, yyyy, h:mm a').format(DateTime.fromMillisecondsSinceEpoch(at!))}'
        : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        children: [
          Expanded(
              child: Text(likha,
                  style: const TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: diaryMutedBrown))),
          Text('— ${diaryDayOfYear(date)} —',
              style: const TextStyle(
                  fontSize: 12, color: diaryMutedBrown)),
        ],
      ),
    );
  }
}

// ---------------- stickers ----------------

/// A photo sticker on the page. [s] = px per 1000-unit.
class StickerView extends StatelessWidget {
  final DiarySticker st;
  final double s;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final GestureDragUpdateCallback? onDrag;
  const StickerView(
      {super.key,
      required this.st,
      required this.s,
      this.selected = false,
      this.onTap,
      this.onDelete,
      this.onDrag});

  @override
  Widget build(BuildContext context) {
    final wPx = st.w * s;
    final hPx = wPx * st.a;
    Widget photo = st.url != null && st.url!.isNotEmpty
        ? Image.network(st.url!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
                color: const Color(0xFFE3D9C2),
                child: const Icon(Icons.broken_image_outlined)))
        : Container(
            color: const Color(0xFFE3D9C2),
            child: const Icon(Icons.image_outlined));
    photo = SizedBox(width: wPx, height: hPx, child: photo);

    Widget body;
    switch (st.k) {
      case 'polaroid':
        body = Container(
          color: Colors.white,
          padding:
              const EdgeInsets.fromLTRB(8, 8, 8, 26),
          child: photo,
        );
        break;
      case 'pin':
        body = Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black26,
                      blurRadius: 6,
                      offset: Offset(0, 3))
                ],
              ),
              child: photo,
            ),
            Positioned(
              top: -8,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                      color: Color(0xFFC0262D),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black38,
                            blurRadius: 3,
                            offset: Offset(0, 2))
                      ]),
                ),
              ),
            ),
          ],
        );
        break;
      case 'clip':
        body = Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: const BoxDecoration(
                boxShadow: [
                  BoxShadow(
                      color: Colors.black26,
                      blurRadius: 6,
                      offset: Offset(0, 3))
                ],
              ),
              child: photo,
            ),
            const Positioned(
              top: -10,
              right: 6,
              child: RotatedBox(
                quarterTurns: 1,
                child: Icon(Icons.attach_file,
                    size: 30, color: Color(0xFF9AA0A6)),
              ),
            ),
          ],
        );
        break;
      default: // tape
        body = Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: const BoxDecoration(
                boxShadow: [
                  BoxShadow(
                      color: Colors.black26,
                      blurRadius: 6,
                      offset: Offset(0, 3))
                ],
              ),
              child: photo,
            ),
            Positioned(
              top: -11,
              left: 0,
              right: 0,
              child: Center(
                child: Transform.rotate(
                  angle: -0.06,
                  child: Container(
                    width: wPx * 0.55,
                    height: 22,
                    color: const Color(0xBFE8C86A),
                  ),
                ),
              ),
            ),
          ],
        );
    }

    Widget w = GestureDetector(
      onTap: onTap,
      onPanUpdate: onDrag,
      child: Transform.rotate(
        angle: st.r * math.pi / 180,
        child: Container(
          decoration: selected
              ? BoxDecoration(
                  border: Border.all(
                      color: const Color(0xFF4A5FD0), width: 2))
              : null,
          child: body,
        ),
      ),
    );
    if (selected && onDelete != null) {
      w = Stack(
        clipBehavior: Clip.none,
        children: [
          w,
          Positioned(
            top: -12,
            right: -12,
            child: GestureDetector(
              onTap: onDelete,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(
                    color: Color(0xFFE5484D),
                    shape: BoxShape.circle),
                child: const Icon(Icons.close,
                    size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      );
    }
    return Positioned(
      left: st.x * s,
      top: st.y * s,
      child: w,
    );
  }
}

// ---------------- read-only page ----------------

/// Read-only book page: header, lined paper, styled text, stickers,
/// drawings, footer, optional TODAY ribbon + bookmark.
class DiaryPage extends StatelessWidget {
  final DateTime date;
  final DiaryEntry? entry;
  final bool isToday;
  final bool bookmark;
  final VoidCallback? onTap;
  final double minHeight;
  const DiaryPage({
    super.key,
    required this.date,
    this.entry,
    this.isToday = false,
    this.bookmark = false,
    this.onTap,
    this.minHeight = 420,
  });

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final hasText =
        e != null && ((e.html?.isNotEmpty ?? false) || e.text.isNotEmpty);
    final parsed = (e?.html?.isNotEmpty ?? false)
        ? parseDiaryMarkup(e!.html!)
        : (e?.text ?? '', <DiarySpan>[]);
    final strokes = e?.draw ?? const <DiaryStroke>[];
    final stickers = e?.stickers ?? const <DiarySticker>[];
    final showPlaceholder =
        !hasText && strokes.isEmpty && stickers.isEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: minHeight),
        decoration: BoxDecoration(
          color: diaryPaper,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFD8CFB8)),
          boxShadow: const [
            BoxShadow(
                color: Colors.black45,
                blurRadius: 14,
                offset: Offset(0, 6)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                    painter: const LinedPaperPainter()),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DiaryPageHeader(date: date, mood: e?.mood ?? ''),
                  LayoutBuilder(builder: (ctx, bc) {
                    final w = bc.maxWidth;
                    final s = w / 1000.0;
                    final needPx = math.max(
                        560 * s, diaryNeededUnits(e) * s);
                    return ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: needPx),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                                66, 4, 14, 12),
                            child: showPlaceholder
                                ? const Text('Ekhane likhun…',
                                    style: TextStyle(
                                        fontFamily: 'serif',
                                        fontStyle:
                                            FontStyle.italic,
                                        color: diaryPlaceholder,
                                        fontSize: 17,
                                        height: 1.75))
                                : RichText(
                                    text: TextSpan(
                                        children:
                                            buildDiaryTextSpans(
                                                parsed.$1,
                                                parsed.$2))),
                          ),
                          for (final st in stickers)
                            StickerView(st: st, s: s),
                          if (strokes.isNotEmpty)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                    painter: DrawingPainter(
                                        strokes: strokes)),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                  DiaryPageFooter(date: date, at: e?.at),
                ],
              ),
              if (isToday)
                const Positioned(
                    top: 0, right: 26, child: TodayRibbon()),
              if (bookmark)
                const Positioned(
                    top: 0, right: 54, child: BookmarkRibbon()),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- interactive drawing canvas ----------------

List<Offset> _strokePolyline(DiaryStroke st) {
  final d = st.d;
  switch (st.t) {
    case 'e':
      {
        if (d.length < 4) return [];
        final x1 = d[0].toDouble(),
            y1 = d[1].toDouble(),
            x2 = d[2].toDouble(),
            y2 = d[3].toDouble();
        final cx = (x1 + x2) / 2,
            cy = (y1 + y2) / 2,
            rx = (x2 - x1).abs() / 2,
            ry = (y2 - y1).abs() / 2;
        return List.generate(
            25,
            (i) => Offset(cx + math.cos(i / 24 * 2 * math.pi) * rx,
                cy + math.sin(i / 24 * 2 * math.pi) * ry));
      }
    case 'r':
      {
        if (d.length < 4) return [];
        final p1 = Offset(d[0].toDouble(), d[1].toDouble());
        final p2 = Offset(d[2].toDouble(), d[1].toDouble());
        final p3 = Offset(d[2].toDouble(), d[3].toDouble());
        final p4 = Offset(d[0].toDouble(), d[3].toDouble());
        return [p1, p2, p3, p4, p1];
      }
    case 'a':
      {
        if (d.length < 4) return [];
        return [
          Offset(d[0].toDouble(), d[1].toDouble()),
          Offset(d[2].toDouble(), d[3].toDouble())
        ];
      }
    default:
      {
        final pts = <Offset>[];
        for (var i = 0; i + 1 < d.length; i += 2) {
          pts.add(Offset(d[i].toDouble(), d[i + 1].toDouble()));
        }
        return pts;
      }
  }
}

double _segDist(double px, double py, Offset a, Offset b) {
  final dx = b.dx - a.dx, dy = b.dy - a.dy;
  final l2 = dx * dx + dy * dy;
  var t = l2 == 0 ? 0.0 : ((px - a.dx) * dx + (py - a.dy) * dy) / l2;
  t = t.clamp(0.0, 1.0);
  final cx = a.dx + t * dx, cy = a.dy + t * dy;
  return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
}

bool _hitStroke(DiaryStroke st, List<int> p, double tol) {
  final pts = _strokePolyline(st);
  if (pts.isEmpty) return false;
  if (pts.length == 1) {
    return (pts[0] - Offset(p[0].toDouble(), p[1].toDouble())).distance <
        tol;
  }
  final px = p[0].toDouble(), py = p[1].toDouble();
  for (var i = 0; i < pts.length - 1; i++) {
    if (_segDist(px, py, pts[i], pts[i + 1]) < tol) return true;
  }
  return false;
}

/// Interactive drawing surface over a page. Pointer positions are stored
/// in the web's 1000-unit page space (page width = 1000 units).
class DrawCanvas extends StatefulWidget {
  final List<DiaryStroke> strokes;
  final String tool; // 'p','b','e','r','a','del'
  final String penColor; // pen key for p/e/r/a
  final String markColor; // marker key for b
  final ValueChanged<List<DiaryStroke>> onChanged;
  const DrawCanvas(
      {super.key,
      required this.strokes,
      required this.tool,
      required this.penColor,
      required this.markColor,
      required this.onChanged});

  @override
  State<DrawCanvas> createState() => _DrawCanvasState();
}

class _DrawCanvasState extends State<DrawCanvas> {
  List<int>? _liveD;
  String _liveT = 'p';
  String _liveC = '';

  List<int> _toUnit(Offset p, double w) => [
        (p.dx / w * 1000).round(),
        math.max(0, (p.dy / w * 1000)).round(),
      ];

  void _start(Offset p, double w) {
    final u = _toUnit(p, w);
    if (widget.tool == 'del') {
      _eraseAt(u);
      return;
    }
    setState(() {
      _liveT = widget.tool;
      _liveC = widget.tool == 'b' ? widget.markColor : widget.penColor;
      _liveD = _liveT == 'p' || _liveT == 'b'
          ? [u[0], u[1]]
          : [u[0], u[1], u[0], u[1]];
    });
  }

  void _move(Offset p, double w) {
    final u = _toUnit(p, w);
    if (widget.tool == 'del') {
      _eraseAt(u);
      return;
    }
    final d = _liveD;
    if (d == null) return;
    setState(() {
      if (_liveT == 'p' || _liveT == 'b') {
        final n = d.length;
        if (n >= 1200) return;
        final dx = (u[0] - d[n - 2]).toDouble();
        final dy = (u[1] - d[n - 1]).toDouble();
        if (math.sqrt(dx * dx + dy * dy) < 4) return;
        d.add(u[0]);
        d.add(u[1]);
      } else {
        d[2] = u[0];
        d[3] = u[1];
      }
    });
  }

  void _end() {
    final d = _liveD;
    if (d == null) return;
    setState(() => _liveD = null);
    final big = _liveT == 'p' || _liveT == 'b'
        ? d.length >= 2
        : math.sqrt(math.pow(d[2] - d[0], 2) +
                math.pow(d[3] - d[1], 2)) >
            10;
    if (big && widget.strokes.length < 300) {
      widget.onChanged([
        ...widget.strokes,
        DiaryStroke(t: _liveT, c: _liveC, d: List.of(d))
      ]);
    }
  }

  void _eraseAt(List<int> u) {
    var removed = false;
    final next = widget.strokes.where((st) {
      final hit = _hitStroke(st, u, st.t == 'b' ? 30 : 20);
      if (hit) removed = true;
      return !hit;
    }).toList();
    if (removed) widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, bc) {
      final w = bc.maxWidth;
      final live = _liveD == null
          ? null
          : DiaryStroke(t: _liveT, c: _liveC, d: _liveD!);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) => _start(d.localPosition, w),
        onPanUpdate: (d) => _move(d.localPosition, w),
        onPanEnd: (_) => _end(),
        onPanCancel: () => setState(() => _liveD = null),
        child: CustomPaint(
          painter: DrawingPainter(strokes: widget.strokes, live: live),
        ),
      );
    });
  }
}

// ---------------- toolbars ----------------

/// Text formatting toolbar: pen colors, marker colors, U/S, sizes, clear.
/// Bengali tooltips mirror the web dyTools bar.
class DiaryFormatToolbar extends StatelessWidget {
  final void Function(String attr, String key) onApply;
  final VoidCallback onClear;
  const DiaryFormatToolbar(
      {super.key, required this.onApply, required this.onClear});

  static const _penTips = [
    'Nil kali (default)',
    'Black kali',
    'Red kali',
    'Green kali',
    'Purple kali',
    'Brown kali',
  ];
  static const _markTips = [
    'Yellow marker',
    'Green marker',
    'Pink marker',
    'Blue marker',
    'Orange marker',
  ];
  static const _sizeTips = [
    'Choto lekha (word select korun)',
    'Normal lekha (word select korun)',
    'Boro lekha (word select korun)',
    'Onek boro lekha (word select korun)',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: diaryDeskBar,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < diaryPenKeys.length; i++)
              _swatch(diaryPenColors[diaryPenKeys[i]]!, _penTips[i],
                  () => onApply('c', diaryPenKeys[i])),
            _sep(),
            for (var i = 0; i < diaryMarkKeys.length; i++)
              _swatch(diaryMarkColors[diaryMarkKeys[i]]!, _markTips[i],
                  () => onApply('m', diaryMarkKeys[i]),
                  square: true),
            _sep(),
            _tbtn(
                'U',
                const TextStyle(
                    decoration: TextDecoration.underline,
                    color: Colors.white,
                    fontWeight: FontWeight.w700),
                'Underline (Ctrl+U)',
                () => onApply('u', '1')),
            _tbtn(
                'S',
                const TextStyle(
                    decoration: TextDecoration.lineThrough,
                    color: Colors.white,
                    fontWeight: FontWeight.w700),
                'Kete deya (strike)',
                () => onApply('s', '1')),
            _sep(),
            _tbtn('A', const TextStyle(fontSize: 11, color: Colors.white),
                _sizeTips[0], () => onApply('z', 'sm')),
            _tbtn('A', const TextStyle(fontSize: 15, color: Colors.white),
                _sizeTips[1], () => onApply('z', 'md')),
            _tbtn(
                'A',
                const TextStyle(
                    fontSize: 19,
                    color: Colors.white,
                    fontWeight: FontWeight.w700),
                _sizeTips[2],
                () => onApply('z', 'lg')),
            _tbtn(
                'A',
                const TextStyle(
                    fontSize: 23,
                    color: Colors.white,
                    fontWeight: FontWeight.w800),
                _sizeTips[3],
                () => onApply('z', 'xl')),
            _sep(),
            IconButton(
                tooltip: 'Format muche fela',
                onPressed: onClear,
                icon: const Icon(Icons.format_clear_outlined,
                    color: Colors.white70, size: 20)),
          ],
        ),
      ),
    );
  }

  Widget _swatch(Color c, String tip, VoidCallback onTap,
      {bool square = false}) {
    return Tooltip(
      message: tip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: c,
              shape: square ? BoxShape.rectangle : BoxShape.circle,
              borderRadius:
                  square ? BorderRadius.circular(7) : null,
              border: Border.all(color: Colors.white38),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tbtn(
      String label, TextStyle style, String tip, VoidCallback onTap) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 32,
          alignment: Alignment.center,
          child: Text(label, style: style),
        ),
      ),
    );
  }

  Widget _sep() => Container(
      width: 1,
      height: 24,
      color: Colors.white24,
      margin: const EdgeInsets.symmetric(horizontal: 6));
}

/// Drawing toolbar: tool, colors, undo. Bengali tooltips mirror the web
/// dyTools bar. Marker colors render as squares like the web (fa-square).
class DiaryDrawToolbar extends StatelessWidget {
  final String tool;
  final ValueChanged<String> onTool;
  final String penColor;
  final ValueChanged<String> onPenColor;
  final String markColor;
  final ValueChanged<String> onMarkColor;
  final VoidCallback? onUndo;
  final VoidCallback? onTextMode;
  final VoidCallback? onSticker;
  const DiaryDrawToolbar(
      {super.key,
      required this.tool,
      required this.onTool,
      required this.penColor,
      required this.onPenColor,
      required this.markColor,
      required this.onMarkColor,
      this.onUndo,
      this.onTextMode,
      this.onSticker});

  static const _toolTips = {
    'p': 'Free pen (hate aaka)',
    'b': 'Marker brush (jayga mark)',
    'e': 'Gol dag (circle)',
    'r': 'Chokro dag (rectangle)',
    'a': 'Arrow',
    'del': 'Aaka muche fela (drag korun)',
  };

  @override
  Widget build(BuildContext context) {
    final isMark = tool == 'b';
    final colors = isMark ? diaryMarkKeys : diaryPenKeys;
    Color colorOf(String k) =>
        isMark ? diaryMarkColors[k]! : diaryPenColors[k]!;
    String tipOf(String k) {
      if (isMark) {
        return '${k[0].toUpperCase()}${k.substring(1)} marker';
      }
      if (k.isEmpty) return 'Nil kali (default)';
      return '${k[0].toUpperCase()}${k.substring(1)} kali';
    }

    final selColor = isMark ? markColor : penColor;
    void pick(String k) =>
        isMark ? onMarkColor(k) : onPenColor(k);

    return Container(
      color: diaryDeskBar,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Tooltip(
                  message: 'Lekha (text)',
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 2),
                    child: InkWell(
                      onTap: onTextMode,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 42,
                        height: 38,
                        alignment: Alignment.center,
                        child: const Text('I',
                            style: TextStyle(
                                fontFamily: 'serif',
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: Colors.white70)),
                      ),
                    ),
                  ),
                ),
                _toolBtn('p', Icons.draw_outlined),
                _toolBtn('b', Icons.highlight_outlined),
                _toolBtn('e', Icons.circle_outlined),
                _toolBtn('r', Icons.square_outlined),
                _toolBtn('a', Icons.arrow_right_alt),
                _toolBtn('del', Icons.ink_eraser),
                Container(
                    width: 1,
                    height: 24,
                    color: Colors.white24,
                    margin:
                        const EdgeInsets.symmetric(horizontal: 6)),
                IconButton(
                    tooltip: 'Undo (shesh aaka ta muche)',
                    onPressed: onUndo,
                    icon: const Icon(Icons.undo_outlined,
                        color: Colors.white70, size: 20)),
                if (onSticker != null)
                  IconButton(
                      tooltip:
                          'Sticky picture lagan (page e jekono jaygay)',
                      onPressed: onSticker,
                      icon: const Icon(Icons.image_outlined,
                          color: Color(0xFFB45309), size: 20)),
              ],
            ),
          ),
          const SizedBox(height: 2),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final k in colors)
                  Tooltip(
                    message: tipOf(k),
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 3),
                      child: InkWell(
                        onTap: () => pick(k),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: colorOf(k),
                            shape: isMark
                                ? BoxShape.rectangle
                                : BoxShape.circle,
                            borderRadius: isMark
                                ? BorderRadius.circular(7)
                                : null,
                            border: Border.all(
                                color: selColor == k
                                    ? Colors.white
                                    : Colors.white38,
                                width:
                                    selColor == k ? 2.5 : 1),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolBtn(String t, IconData icon) {
    final sel = tool == t;
    return Tooltip(
      message: _toolTips[t] ?? t,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: InkWell(
          onTap: () => onTool(t),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 42,
            height: 38,
            decoration: BoxDecoration(
              color: sel
                  ? diaryPeach.withOpacity(0.3)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: sel ? diaryPeach : Colors.transparent),
            ),
            child: Icon(icon,
                color: sel ? diaryPeach : Colors.white70, size: 22),
          ),
        ),
      ),
    );
  }
}
