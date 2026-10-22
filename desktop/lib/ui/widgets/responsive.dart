import 'package:flutter/widgets.dart';

/// Breakpoints shared by the shell and the screens (works for any desktop ratio, incl. ultra-wide and portrait).
class Bp {
  static const double xs = 640;
  static const double sm = 900;
  static const double md = 1200;
  static const double lg = 1600;
  static const double xl = 2000;

  static bool isNarrow(BuildContext c) => MediaQuery.sizeOf(c).width < sm;
  static bool isCompact(BuildContext c) => MediaQuery.sizeOf(c).width < md;
  static bool isWide(BuildContext c) => MediaQuery.sizeOf(c).width >= lg;

  /// Number of grid columns for a given width and minimum tile width.
  static int cols(double width, double minTile, {int min = 1, int max = 12}) {
    final n = (width / minTile).floor();
    return n.clamp(min, max).toInt();
  }

  static double pagePad(BuildContext c) {
    final w = MediaQuery.sizeOf(c).width;
    if (w < xs) return 12;
    if (w < sm) return 16;
    if (w < lg) return 22;
    return 28;
  }
}

/// Responsive grid: children get equal widths computed from the max tile
/// count, and every row is stretched to the height of its tallest tile so
/// cards line up cleanly.
class AutoGrid extends StatelessWidget {
  const AutoGrid({super.key, required this.children, this.minTile = 220, this.gap = 12, this.maxCols = 12, this.minCols = 1, this.equalHeight = true});
  final List<Widget> children;
  final double minTile;
  final double gap;
  final int maxCols;
  final int minCols;
  final bool equalHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final cols = Bp.cols(c.maxWidth + gap, minTile + gap, min: minCols, max: maxCols);
      if (!equalHeight) {
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(spacing: gap, runSpacing: gap, children: children.map((ch) => SizedBox(width: w, child: ch)).toList());
      }
      final rows = <Widget>[];
      for (var i = 0; i < children.length; i += cols) {
        final slice = children.sublist(i, (i + cols).clamp(0, children.length).toInt());
        final cells = <Widget>[];
        for (var j = 0; j < cols; j++) {
          if (j > 0) cells.add(SizedBox(width: gap));
          cells.add(Expanded(child: j < slice.length ? slice[j] : const SizedBox.shrink()));
        }
        if (rows.isNotEmpty) rows.add(SizedBox(height: gap));
        rows.add(IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: cells)));
      }
      return Column(mainAxisSize: MainAxisSize.min, children: rows);
    });
  }
}
