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
];

const List<int> kPresSpeeds = [2000, 3000, 5000, 8000];

/// Phone / tablet frame (`.phone-mockup`). The child fills the screen (9:16 or 3:4 for tablet).
class PhoneMockup extends StatelessWidget {
  const PhoneMockup({super.key, required this.deviceId, required this.child, this.width = 250, this.showLockClock = false});
  final String deviceId;
  final Widget child;
  final double width;
  final bool showLockClock;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tablet = deviceId == 'tablet';
    final classic = deviceId == 'ios-classic';
    final flat = deviceId == 'and-flat';
    final curved = deviceId == 'and-curved';
    final aspect = tablet ? 3 / 4 : 9 / 19.5;
    final screenW = width - (flat ? 10 : 18);
    final screenH = screenW / aspect;
    final topBezel = classic ? 44.0 : (tablet ? 26.0 : (flat ? 5.0 : 9.0));
    final bottomBezel = classic ? 44.0 : (tablet ? 26.0 : (flat ? 5.0 : 9.0));
    final frameRadius = tablet ? 30.0 : classic ? 34.0 : flat ? 26.0 : 44.0;
    final screenRadius = tablet ? 16.0 : classic ? 4.0 : flat ? 20.0 : 36.0;
    return Container(
      width: width,
      padding: EdgeInsets.fromLTRB(flat ? 5 : 9, topBezel, flat ? 5 : 9, bottomBezel),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [const Color(0xff2a2d36), const Color(0xff0c0e14)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(frameRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1.2),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 40, offset: const Offset(0, 22)),
          BoxShadow(color: p.primary.withValues(alpha: 0.18), blurRadius: 60, spreadRadius: -10),
        ],
      ),
      child: Stack(alignment: Alignment.topCenter, children: [
        Container(
          width: screenW,
          height: screenH,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: curved ? BorderRadius.horizontal(left: Radius.elliptical(screenW * 0.12, screenH * 0.06), right: Radius.elliptical(screenW * 0.12, screenH * 0.06)) : BorderRadius.circular(screenRadius),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(fit: StackFit.expand, children: [
            child,
            if (showLockClock) const _LockClock(),
            if (!classic && !tablet) _Notch(deviceId: deviceId, screenW: screenW),
            if (!classic && !tablet && !flat)
              Positioned(
                bottom: 8,
                child: Container(width: screenW * 0.38, height: 4, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(4))),
              ),
          ]),
        ),
        if (classic)
          Positioned(top: -30, child: Container(width: 46, height: 5, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(4)))),
        if (classic)
          Positioned(bottom: -38, child: Container(width: 34, height: 34, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2)))),
        if (tablet)
          Positioned(top: -17, child: Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.35)))),
      ]),
    );
  }
}

class _Notch extends StatelessWidget {
  const _Notch({required this.deviceId, required this.screenW});
  final String deviceId;
  final double screenW;

  @override
  Widget build(BuildContext context) {
    const black = Colors.black;
    switch (deviceId) {
      case 'ios-island':
        return Positioned(top: 10, child: Container(width: screenW * 0.34, height: 24, decoration: BoxDecoration(color: black, borderRadius: BorderRadius.circular(14))));
      case 'ios-notch':
        return Positioned(
            top: 0,
            child: Container(width: screenW * 0.52, height: 26, decoration: const BoxDecoration(color: black, borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)))));
      case 'and-dot':
        return Positioned(top: 10, child: Container(width: 14, height: 14, decoration: const BoxDecoration(color: black, shape: BoxShape.circle)));
      case 'and-dot-left':
        return Positioned(top: 10, left: 16, child: Container(width: 14, height: 14, decoration: const BoxDecoration(color: black, shape: BoxShape.circle)));
      case 'and-drop':
        return Positioned(
            top: 0, child: Container(width: 30, height: 24, decoration: const BoxDecoration(color: black, borderRadius: BorderRadius.vertical(bottom: Radius.elliptical(16, 22)))));
      case 'and-curved':
        return Positioned(top: 8, child: Container(width: 12, height: 12, decoration: const BoxDecoration(color: black, shape: BoxShape.circle)));
      default:
        return const SizedBox.shrink();
    }
  }
}

/// v27 lock-screen overlay (clock + date, Dhaka time).
class _LockClock extends StatelessWidget {
  const _LockClock();

  @override
  Widget build(BuildContext context) {
    final d = getDhakaDate(0);
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    String two(int n) => n.toString().padLeft(2, '0');
    return Positioned(
      top: 54,
      left: 0,
      right: 0,
      child: Column(children: [
        Text('${two(h)}:${two(d.minute)}', style: TextStyle(color: Colors.white, fontSize: 52, fontWeight: FontWeight.w300, height: 1, shadows: [Shadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 12)])),
        Text('${kWeekdayLong[(d.weekday + 6) % 7].substring(0, 3)}, ${d.day} ${kMonthShort[d.month - 1]}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 14, fontWeight: FontWeight.w600, shadows: [Shadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10)])),
      ]),
    );
  }
}

/// Device chooser row under the phone (`renderDeviceChooser`).
class DeviceChooser extends StatelessWidget {
  const DeviceChooser({super.key, required this.active, required this.onChanged});
  final String active;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: kDevicePresets.map((d) {
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
                  gradient: on ? p.buttonGradient : null,
                  color: on ? null : p.surfaceHover.withValues(alpha: 0.6),
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
      decoration: BoxDecoration(gradient: LinearGradient(colors: [p.primary2, p.accent2.withValues(alpha: 0.85), const Color(0xff0b0d14)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
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
          gradient: const SweepGradient(colors: [Color(0xff111111), Color(0xff2a2a2a), Color(0xff111111), Color(0xff333333), Color(0xff111111)]),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 24, offset: const Offset(0, 12))],
        ),
        child: Center(
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [context.pal.primary, context.pal.accent])),
            child: const Center(child: Fa('fa-music', size: 14, color: Colors.white)),
          ),
        ),
      ),
    );
  }
}
