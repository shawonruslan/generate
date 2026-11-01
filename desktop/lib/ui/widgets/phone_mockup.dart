import 'package:flutter/material.dart';

import '../../core/dhaka_time.dart';
import 'common.dart';
import 'fa.dart';

/// `DEVICE_PRESETS` - phone frame styles of the asset preview.
class DevicePreset {
  const DevicePreset(this.id, this.icon, this.label);
  final String id, icon, label;
}

const List<DevicePreset> kDevicePresets = [
  DevicePreset('ios-island', 'fa-mobile-screen', 'iPhone 16 Pro'),
  DevicePreset('ios-notch', 'fa-mobile-screen', 'iPhone 14'),
  DevicePreset('ios-classic', 'fa-mobile', 'iPhone SE'),
  DevicePreset('and-dot', 'fa-mobile-alt', 'Dot Notch'),
  DevicePreset('and-dot-left', 'fa-mobile-alt', 'Dot Left'),
  DevicePreset('and-drop', 'fa-mobile-alt', 'Teardrop'),
  DevicePreset('and-curved', 'fa-mobile-screen', 'Galaxy Edge'),
  DevicePreset('and-flat', 'fa-expand', 'Bezel-less'),
  DevicePreset('tablet', 'fa-tablet-screen-button', 'Tablet'),
  // v41.9 - only shown when the item carries a foldable (landscape 2800x2400) companion
  DevicePreset('foldable', 'fa-book-open', 'Foldable'),
];

/// v41.9 - resolves the device actually drawn: Foldable only when the item has a fold image.
String effectiveDeviceId(String pref, bool hasFold) => pref == 'foldable' && !hasFold ? 'ios-island' : pref;

const List<int> kPresSpeeds = [2000, 3000, 5000, 8000];

/// Phone / tablet frame (`.phone-mockup`). The child fills the screen (9:19.5 or 3:4 for tablet).
///
/// Geometry is computed per device preset so the notch / island / punch-hole
/// is centred and the status bar (time · signal · wifi · battery) always sits
/// in the safe area next to it.
class PhoneMockup extends StatelessWidget {
  const PhoneMockup({super.key, required this.deviceId, required this.child, this.width = 250, this.showLockClock = false, this.hideStatusTime = false});
  final String deviceId;
  final Widget child;
  final double width;
  final bool showLockClock;
  /// v27.12 - hide the small status-bar clock (a scene draws its own big clock).
  final bool hideStatusTime;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final g = _Geometry.of(deviceId, width);
    final screen = Container(
      width: g.screenW,
      height: g.screenH,
      decoration: BoxDecoration(color: Colors.black, borderRadius: g.screenRadius),
      clipBehavior: Clip.antiAlias,
      child: Stack(fit: StackFit.expand, alignment: Alignment.topCenter, children: [
        child,
        // subtle inner glass edge
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: g.screenRadius,
              border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1),
            ),
          ),
        ),
        _StatusBar(g: g, hideTime: showLockClock || hideStatusTime),
        if (showLockClock) _LockClock(top: g.statusTop + 44),
        if (g.cutout != null) g.cutout!,
        // v41.10 foldable: soft screen crease + glass glare
        if (g.foldable) ...[
          Positioned(
            top: 0,
            bottom: 0,
            left: g.screenW / 2 - 14,
            child: IgnorePointer(
              child: Container(
                width: 28,
                decoration: BoxDecoration(
                  gradient: LinearGradient(stops: const [0.0, 0.25, 0.45, 0.5, 0.55, 0.75, 1.0], colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.07),
                    Colors.black.withValues(alpha: 0.16),
                    Colors.white.withValues(alpha: 0.10),
                    Colors.black.withValues(alpha: 0.14),
                    Colors.black.withValues(alpha: 0.06),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: const Alignment(-1, -1),
                    end: const Alignment(1, 0.6),
                    stops: const [0.0, 0.22, 0.38, 0.72, 1.0],
                    colors: [
                      Colors.white.withValues(alpha: 0.085),
                      Colors.white.withValues(alpha: 0.03),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.white.withValues(alpha: 0.035),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
        if (g.homeIndicator && g.foldable)
          Positioned(
            bottom: 10,
            left: g.screenW * 0.75 - 32,
            child: Container(width: 64, height: 3, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(3))),
          )
        else if (g.homeIndicator)
          Positioned(
            bottom: 8,
            child: Container(width: g.screenW * 0.36, height: 4.5, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(4))),
          ),
      ]),
    );

    if (g.foldable) return _foldBody(g, screen);
    return SizedBox(
      width: width + 8,
      height: g.frameH,
      child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
        // side buttons (drawn behind the body)
        if (!g.tablet && !g.foldable) ...[
          _SideButton(left: 0, top: g.frameH * 0.22, h: 26),
          _SideButton(left: 0, top: g.frameH * 0.30, h: 46),
          _SideButton(left: 0, top: g.frameH * 0.40, h: 46),
          _SideButton(right: 0, top: g.frameH * 0.31, h: 70),
        ],
        // body
        Container(
          width: width,
          height: g.frameH,
          padding: EdgeInsets.fromLTRB(g.bezelX, g.bezelTop, g.bezelX, g.bezelBottom),
          decoration: BoxDecoration(
            color: const Color(0xff15171c),
            borderRadius: BorderRadius.circular(g.frameRadius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 1.4),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 44, offset: const Offset(0, 24)),
              BoxShadow(color: p.primary.withValues(alpha: 0.20), blurRadius: 70, spreadRadius: -8),
            ],
          ),
          child: Stack(alignment: Alignment.topCenter, clipBehavior: Clip.none, children: [
            Positioned.fill(child: Center(child: screen)),
            if (g.classic) ...[
              // earpiece + camera in the top bezel, home button in the bottom bezel
              Positioned(top: -g.bezelTop + 18, child: Container(width: 48, height: 5, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.28), borderRadius: BorderRadius.circular(4)))),
              Positioned(top: -g.bezelTop + 16, left: g.screenW * 0.30, child: Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.35)))),
              Positioned(bottom: -g.bezelBottom + 8, child: Container(width: 36, height: 36, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black, border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 2)))),
            ],
            if (g.tablet) Positioned(top: -g.bezelTop + 9, child: Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.4)))),
          ]),
        ),
      ]),
    );
  }
}

extension _FoldBody on PhoneMockup {
  /// v41.10 realistic Galaxy Z Fold style body: brushed-aluminium armour rim, uniform black glass bezel,
  /// hinge split in the rim (top + bottom centre) and the side keys on the right half.
  Widget _foldBody(_Geometry g, Widget screen) {
    Widget key(double h) => Container(
          width: 3,
          height: h,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(2)),
            gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xff9a9da5), Color(0xff50535a), Color(0xff8c9098), Color(0xff50535a)]),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), offset: const Offset(1, 0), blurRadius: 1)],
          ),
        );
    Widget gap() => Container(
          width: 4,
          height: 4,
          decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xff050506), Color(0xff1a1b1f)])),
        );
    final h = g.frameH;
    return SizedBox(
      width: width + 8,
      height: h,
      child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
        Positioned(right: 1, top: h * 0.16, child: key(h * 0.145)),
        Positioned(right: 1, top: h * 0.16 + h * 0.2, child: key(h * 0.10)),
        Container(
          width: width,
          height: h,
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(g.frameRadius),
            gradient: const LinearGradient(
              stops: [0.0, 0.07, 0.16, 0.30, 0.47, 0.50, 0.53, 0.70, 0.84, 0.93, 1.0],
              colors: [
                Color(0xff3c3f46), Color(0xff8e929b), Color(0xff2a2c32), Color(0xff5d6068), Color(0xffc3c6cc), Color(0xff3a3d44),
                Color(0xffc3c6cc), Color(0xff5d6068), Color(0xff2a2c32), Color(0xff8e929b), Color(0xff3c3f46),
              ],
            ),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.65), spreadRadius: 1),
              BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 3, offset: const Offset(0, 2)),
              BoxShadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 34, spreadRadius: -8, offset: const Offset(0, 18)),
              BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 80, spreadRadius: -20, offset: const Offset(0, 42)),
            ],
          ),
          child: Container(
            decoration: BoxDecoration(color: const Color(0xff060608), borderRadius: BorderRadius.circular(g.frameRadius - 2.5)),
            child: Center(child: screen),
          ),
        ),
        Positioned(top: -1.5, child: gap()),
        Positioned(bottom: -1.5, child: gap()),
      ]),
    );
  }
}

class _Geometry {
  _Geometry({
    required this.screenW,
    required this.screenH,
    required this.bezelX,
    required this.bezelTop,
    required this.bezelBottom,
    required this.frameRadius,
    required this.screenRadius,
    required this.statusTop,
    required this.statusLeft,
    required this.statusRight,
    required this.homeIndicator,
    required this.classic,
    required this.tablet,
    this.foldable = false,
    this.cutout,
  });
  final double screenW, screenH, bezelX, bezelTop, bezelBottom, frameRadius, statusTop, statusLeft, statusRight;
  final BorderRadius screenRadius;
  final bool homeIndicator, classic, tablet, foldable;
  final Widget? cutout;
  double get frameH => screenH + bezelTop + bezelBottom;

  static _Geometry of(String id, double width) {
    const black = Colors.black;
    final tablet = id == 'tablet';
    final classic = id == 'ios-classic';
    final flat = id == 'and-flat';
    final curved = id == 'and-curved';
    final foldable = id == 'foldable';
    final bezelX = flat ? 5.0 : (tablet ? 14.0 : (foldable ? 12.5 : 9.0));
    final screenW = width - bezelX * 2;
    final aspect = tablet ? 3 / 4 : (foldable ? 7 / 6 : 9 / 19.5);
    final screenH = screenW / aspect;
    final bezelTop = classic ? 46.0 : (tablet ? 26.0 : (flat ? 5.0 : (foldable ? 12.5 : 9.0)));
    final bezelBottom = classic ? 52.0 : (tablet ? 26.0 : (flat ? 5.0 : (foldable ? 12.5 : 9.0)));
    final frameRadius = tablet ? 26.0 : classic ? 36.0 : flat ? 24.0 : foldable ? 22.0 : 46.0;
    final BorderRadius screenRadius = curved
        ? BorderRadius.horizontal(left: Radius.elliptical(screenW * 0.14, screenH * 0.055), right: Radius.elliptical(screenW * 0.14, screenH * 0.055))
        : BorderRadius.circular(tablet ? 14 : classic ? 3 : flat ? 20 : foldable ? 11 : 38);

    Widget? cutout;
    var statusTop = 8.0;
    var statusLeft = 18.0;
    var statusRight = 18.0;
    switch (id) {
      case 'ios-island':
        statusTop = 13;
        statusLeft = 24;
        statusRight = 24;
        cutout = Positioned(top: 11, child: Container(width: screenW * 0.33, height: 25, decoration: BoxDecoration(color: black, borderRadius: BorderRadius.circular(14))));
        break;
      case 'ios-notch':
        statusTop = 9;
        statusLeft = 22;
        statusRight = 22;
        cutout = Positioned(
          top: 0,
          child: Container(width: screenW * 0.52, height: 27, decoration: const BoxDecoration(color: black, borderRadius: BorderRadius.vertical(bottom: Radius.circular(17)))),
        );
        break;
      case 'and-dot':
        statusTop = 10;
        cutout = Positioned(top: 10, child: Container(width: 15, height: 15, decoration: const BoxDecoration(color: black, shape: BoxShape.circle)));
        break;
      case 'and-dot-left':
        statusTop = 10;
        statusLeft = 40;
        cutout = Positioned(top: 10, left: 18, child: Container(width: 15, height: 15, decoration: const BoxDecoration(color: black, shape: BoxShape.circle)));
        break;
      case 'and-drop':
        statusTop = 7;
        cutout = Positioned(
          top: 0,
          child: Container(width: 32, height: 26, decoration: const BoxDecoration(color: black, borderRadius: BorderRadius.vertical(bottom: Radius.elliptical(16, 24)))),
        );
        break;
      case 'and-curved':
        statusTop = 8;
        cutout = Positioned(top: 8, child: Container(width: 12, height: 12, decoration: const BoxDecoration(color: black, shape: BoxShape.circle)));
        break;
      case 'ios-classic':
        statusTop = 5;
        statusLeft = 12;
        statusRight = 12;
        break;
      case 'foldable':
        statusTop = 9;
        statusLeft = 16;
        statusRight = 16;
        // under-display camera: faint pixel mesh on the right half
        cutout = Positioned(
          top: 12,
          right: screenW * 0.25 - 4.5,
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(stops: const [0.4, 0.6, 1.0], colors: [const Color(0xff0a0a0e).withValues(alpha: 0.55), const Color(0xff0a0a0e).withValues(alpha: 0.30), const Color(0xff0a0a0e).withValues(alpha: 0.08)]),
            ),
          ),
        );
        break;
      case 'tablet':
        statusTop = 6;
        statusLeft = 16;
        statusRight = 16;
        break;
      default: // and-flat
        statusTop = 7;
    }
    return _Geometry(
      screenW: screenW,
      screenH: screenH,
      bezelX: bezelX,
      bezelTop: bezelTop,
      bezelBottom: bezelBottom,
      frameRadius: frameRadius,
      screenRadius: screenRadius,
      statusTop: statusTop,
      statusLeft: statusLeft,
      statusRight: statusRight,
      homeIndicator: !classic && !tablet,
      classic: classic,
      tablet: tablet,
      foldable: foldable,
      cutout: cutout,
    );
  }
}

/// `.phone-statusbar` - time on the left, signal / wifi / battery on the right.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.g, required this.hideTime});
  final _Geometry g;
  final bool hideTime;

  @override
  Widget build(BuildContext context) {
    final d = getDhakaDate(0);
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final time = '$h:${two(d.minute)}';
    final shadow = [Shadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 5)];
    return Positioned(
      top: g.statusTop,
      left: g.statusLeft,
      right: g.statusRight,
      child: IgnorePointer(
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(hideTime ? '' : time, style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, shadows: shadow, letterSpacing: 0.2)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(faIcon('fa-signal'), size: 10, color: Colors.white, shadows: shadow),
            const SizedBox(width: 5),
            Icon(faIcon('fa-wifi'), size: 10, color: Colors.white, shadows: shadow),
            const SizedBox(width: 5),
            Container(
              width: 20,
              height: 10,
              decoration: BoxDecoration(border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.2), borderRadius: BorderRadius.circular(3)),
              padding: const EdgeInsets.all(1.5),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(widthFactor: 0.78, child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(1.5)))),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _SideButton extends StatelessWidget {
  const _SideButton({this.left, this.right, required this.top, required this.h});
  final double? left, right, top, h;
  @override
  Widget build(BuildContext context) => Positioned(
        left: left,
        right: right,
        top: top,
        child: Container(width: 4, height: h, decoration: BoxDecoration(color: const Color(0xff2b2e35), borderRadius: BorderRadius.circular(2), border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 0.8))),
      );
}

/// v27 lock-screen overlay (clock + date, Dhaka time).
class _LockClock extends StatelessWidget {
  const _LockClock({required this.top});
  final double top;

  @override
  Widget build(BuildContext context) {
    final d = getDhakaDate(0);
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Column(children: [
          Text('${kWeekdayLong[(d.weekday + 6) % 7]}, ${d.day} ${kMonthLong[d.month - 1]}',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.92), fontSize: 13, fontWeight: FontWeight.w600, shadows: [Shadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10)])),
          const SizedBox(height: 2),
          Text('${two(h)}:${two(d.minute)}', style: TextStyle(color: Colors.white, fontSize: 60, fontWeight: FontWeight.w300, height: 1.05, letterSpacing: -1, shadows: [Shadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 14)])),
        ]),
      ),
    );
  }
}

/// Device chooser row under the phone (`renderDeviceChooser`).
class DeviceChooser extends StatelessWidget {
  const DeviceChooser({super.key, required this.active, required this.onChanged, this.showFoldable = false});
  final String active;
  /// v41.9 - Foldable chip only for items that have a foldable image.
  final bool showFoldable;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: kDevicePresets.where((d) => d.id != 'foldable' || showFoldable).map((d) {
        final on = d.id == active;
        return Tooltip(
          message: d.label,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => onChanged(d.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: on ? p.buttonColor : p.surfaceHover.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: on ? Colors.transparent : p.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Fa(d.icon, size: 11, color: on ? p.buttonFg : p.muted),
                  const SizedBox(width: 6),
                  Text(d.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: on ? p.buttonFg : p.text)),
                ]),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Audio "screen" shown on the phone for ringtones (`.phone-audio-screen`).
class PhoneAudioScreen extends StatelessWidget {
  const PhoneAudioScreen({super.key, required this.title, required this.playing, this.progress = 0});
  final String title;
  final bool playing;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      decoration: const BoxDecoration(color: Color(0xff0b0d14)),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        _Vinyl(spinning: playing),
        const SizedBox(height: 26),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15))),
        const SizedBox(height: 6),
        Text('Ringtone · Zedge preview', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: progress.clamp(0, 1).toDouble(), minHeight: 4, color: Colors.white, backgroundColor: Colors.white.withValues(alpha: 0.25))),
        ),
      ]),
    );
  }
}

class _Vinyl extends StatefulWidget {
  const _Vinyl({required this.spinning});
  final bool spinning;
  @override
  State<_Vinyl> createState() => _VinylState();
}

class _VinylState extends State<_Vinyl> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 4));

  @override
  void initState() {
    super.initState();
    if (widget.spinning) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant _Vinyl old) {
    super.didUpdateWidget(old);
    if (widget.spinning && !_c.isAnimating) _c.repeat();
    if (!widget.spinning && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _c,
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xff18181b),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 24, offset: const Offset(0, 12))],
        ),
        child: Center(
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(shape: BoxShape.circle, color: context.pal.primary),
            child: const Center(child: Fa('fa-music', size: 14, color: Colors.white)),
          ),
        ),
      ),
    );
  }
}
