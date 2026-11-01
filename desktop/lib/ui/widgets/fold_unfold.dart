import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'common.dart';
import 'fa.dart';

/// v41.11 - unfold intro for the Foldable mockup: the phone starts folded (cover screen shows the
/// portrait wallpaper), opens like a book and the inner screen wakes up with the foldable image.
/// [child] is the real PhoneMockup; it is shown once the animation finishes (+ a replay button).
class FoldUnfoldIntro extends StatefulWidget {
  const FoldUnfoldIntro({super.key, required this.foldUrl, required this.portraitUrl, required this.child});
  final String foldUrl;
  final String portraitUrl;
  final Widget child;

  @override
  State<FoldUnfoldIntro> createState() => _FoldUnfoldIntroState();
}

class _FoldUnfoldIntroState extends State<FoldUnfoldIntro> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  bool _running = true;

  static const _metal = LinearGradient(
    stops: [0.0, 0.07, 0.16, 0.30, 0.47, 0.50, 0.53, 0.70, 0.84, 0.93, 1.0],
    colors: [
      Color(0xff3c3f46), Color(0xff8e929b), Color(0xff2a2c32), Color(0xff5d6068), Color(0xffc3c6cc), Color(0xff3a3d44),
      Color(0xffc3c6cc), Color(0xff5d6068), Color(0xff2a2c32), Color(0xff8e929b), Color(0xff3c3f46),
    ],
  );

  @override
  void initState() {
    super.initState();
    _play();
  }

  void _play() {
    setState(() => _running = true);
    _c.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _running = false);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  // 0..0.22 hold folded, 0.22..0.86 open (eased), then rest
  double get _open => Curves.easeInOutCubic.transform(((_c.value - 0.22) / 0.64).clamp(0.0, 1.0));
  double get _wake => 1 - ((_c.value - 0.24) / 0.28).clamp(0.0, 1.0); // black overlay on the inner screen

  Widget _key(double h) => Container(
        width: 3,
        height: h,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(2)),
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xff9a9da5), Color(0xff50535a), Color(0xff8c9098), Color(0xff50535a)]),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), offset: const Offset(1, 0), blurRadius: 1)],
        ),
      );

  Widget _halfImage(String url, {required bool right}) => LayoutBuilder(
        builder: (c, bc) => ClipRect(
          child: OverflowBox(
            alignment: right ? Alignment.centerRight : Alignment.centerLeft,
            minWidth: bc.maxWidth * 2,
            maxWidth: bc.maxWidth * 2,
            minHeight: bc.maxHeight,
            maxHeight: bc.maxHeight,
            child: NetImage(url, fit: BoxFit.cover),
          ),
        ),
      );

  Widget _innerHalf({required bool right, required double shade}) {
    const r = Radius.circular(22), ri = Radius.circular(19.5), rs = Radius.circular(11);
    return Container(
      padding: right ? const EdgeInsets.fromLTRB(0, 2.5, 2.5, 2.5) : const EdgeInsets.fromLTRB(2.5, 2.5, 0, 2.5),
      decoration: BoxDecoration(
        gradient: _metal,
        borderRadius: right ? const BorderRadius.horizontal(left: Radius.circular(4), right: r) : const BorderRadius.horizontal(left: r),
        boxShadow: right
            ? [
                BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 3, offset: const Offset(0, 2)),
                BoxShadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 34, spreadRadius: -8, offset: const Offset(0, 18)),
              ]
            : null,
      ),
      child: Container(
        padding: right ? const EdgeInsets.fromLTRB(0, 10, 10, 10) : const EdgeInsets.fromLTRB(10, 10, 0, 10),
        decoration: BoxDecoration(
          color: const Color(0xff060608),
          borderRadius: right ? const BorderRadius.horizontal(left: Radius.circular(2), right: ri) : const BorderRadius.horizontal(left: ri),
        ),
        child: ClipRRect(
          borderRadius: right ? const BorderRadius.horizontal(right: rs) : const BorderRadius.horizontal(left: rs),
          child: Stack(fit: StackFit.expand, children: [
            _halfImage(widget.foldUrl, right: right),
            Container(color: Colors.black.withValues(alpha: _wake)),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: right
                        ? [Colors.black.withValues(alpha: 0.6 * shade), Colors.black.withValues(alpha: 0.1 * shade)]
                        : [Colors.transparent, Colors.black.withValues(alpha: 0.55 * shade)],
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// v41.12 outside of the folded phone = real back side (frosted back glass + camera island), not a screen.
  Widget _cover() {
    Widget lens() => Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              stops: [0.0, 0.22, 0.32, 0.48, 0.60, 0.64, 0.70, 0.78, 0.86, 1.0],
              colors: [Color(0xff0b1a2c), Color(0xff0b1a2c), Color(0xff04060a), Color(0xff151820), Color(0xff2c2f36), Color(0xff0c0d10), Color(0xff5d6068), Color(0xff1c1d22), Color(0xff9a9da5), Color(0xff3a3d44)],
            ),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 2, offset: const Offset(0, 1))],
          ),
          child: Align(
            alignment: const Alignment(-0.3, -0.35),
            child: Container(width: 5, height: 4, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xffaac8ff).withValues(alpha: 0.35))),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(4), right: Radius.circular(22)),
        gradient: const LinearGradient(colors: [Color(0xff3c3f46), Color(0xff9a9ea6), Color(0xff2a2c32), Color(0xff6a6d75), Color(0xffc3c6cc), Color(0xff4a4d54)]),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 40, spreadRadius: -8, offset: const Offset(0, 22))],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(3), right: Radius.circular(19.5)),
        child: Stack(fit: StackFit.expand, children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-0.6, -1),
                end: Alignment(0.6, 1),
                stops: [0.0, 0.38, 0.62, 1.0],
                colors: [Color(0xff3a3d44), Color(0xff24262b), Color(0xff1b1c20), Color(0xff2c2e34)],
              ),
            ),
          ),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: const Alignment(0.3, 0.1), colors: [Colors.white.withValues(alpha: 0.12), Colors.transparent]),
              ),
            ),
          ),
          Positioned(top: 16, left: 14, child: Column(children: [lens(), const SizedBox(height: 7), lens(), const SizedBox(height: 7), lens()])),
          Positioned(
            top: 22,
            left: 48,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(stops: [0.35, 0.6, 1.0], colors: [Color(0xfffff6d8), Color(0xffc9b98a), Color(0xff55524a)])),
            ),
          ),
          Positioned(top: 40, left: 50, child: Container(width: 3, height: 3, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xff0a0a0c)))),
          Positioned(
            left: 0,
            right: 0,
            bottom: 30,
            child: Text('SAMSUNG', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.22), fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 3)),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(clipBehavior: Clip.none, children: [
      // the real mockup keeps the layout size; hidden while the intro runs
      Opacity(opacity: _running ? 0 : 1, child: widget.child),
      if (_running)
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => LayoutBuilder(builder: (context, bc) {
                final w = bc.maxWidth - 8; // PhoneMockup body width (SizedBox is width + 8)
                final hw = w / 2;
                final p = _open;
                final angle = math.pi * (1 - p);
                final shadeL = (1 - p);
                final shadeR = (1 - ((_c.value - 0.22) / 0.55).clamp(0.0, 1.0));
                // v41.13 2D flip: no 3D perspective -> hinge edge never moves, no glitches
                final c = math.cos(angle);
                const sy = 1.0; // v41.14: no vertical scale -> edges stay flush at the hinge
                final dim = c < 0 ? 1 - (0.55 + 0.45 * -c) : 1 - (0.6 + 0.4 * c);
                Widget dimmed(Widget child, BorderRadius r) => ClipRRect(
                      borderRadius: r,
                      child: Stack(fit: StackFit.expand, children: [child, IgnorePointer(child: Container(color: Colors.black.withValues(alpha: dim.clamp(0.0, 1.0))))]),
                    );
                final Widget flap = c < 0
                    ? Positioned(
                        left: 4 + hw,
                        top: 0,
                        width: hw,
                        height: bc.maxHeight,
                        child: Transform(
                          alignment: Alignment.centerLeft,
                          transform: Matrix4.diagonal3Values(math.max(0.001, -c), sy, 1),
                          child: dimmed(_cover(), const BorderRadius.horizontal(left: Radius.circular(4), right: Radius.circular(22))),
                        ),
                      )
                    : Positioned(
                        left: 4,
                        top: 0,
                        width: hw,
                        height: bc.maxHeight,
                        child: Transform(
                          alignment: Alignment.centerRight,
                          transform: Matrix4.diagonal3Values(math.max(0.001, c), sy, 1),
                          child: dimmed(_innerHalf(right: false, shade: shadeL), const BorderRadius.horizontal(left: Radius.circular(22))),
                        ),
                      );
                return Transform.translate(
                  offset: Offset(-hw / 2 * (1 - p), 0),
                  child: Stack(clipBehavior: Clip.none, children: [
                    Positioned(left: 4 + hw, top: 0, width: hw, height: bc.maxHeight, child: _innerHalf(right: true, shade: shadeR)),
                    flap,
                    // v41.15 side keys stay visible during the unfold (same spots as PhoneMockup)
                    Positioned(left: 4 + w, top: bc.maxHeight * 0.16, child: _key(bc.maxHeight * 0.145)),
                    Positioned(left: 4 + w, top: bc.maxHeight * 0.36, child: _key(bc.maxHeight * 0.10)),
                  ]),
                );
              }),
            ),
          ),
        ),
      if (!_running)
        Positioned(
          left: 26,
          bottom: 58,
          child: Tooltip(
            message: 'Unfold again',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: _play,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Fa('fa-rotate-left', size: 12, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}
