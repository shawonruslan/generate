import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/dhaka_time.dart';
import 'common.dart';
import 'fa.dart';

/// v27.12 - realistic phone "scenes" drawn over the media inside [PhoneMockup]:
/// plain wallpaper, lock screen, home screen (icon grid + dock), the Zedge app
/// item page, an incoming call (ringtone preview) and an incoming message
/// notification. iOS / Android styling follows the chosen device frame.
enum PhoneScene { plain, lock, home, app, call, notify }

class PhoneSceneMeta {
  const PhoneSceneMeta(this.scene, this.id, this.label, this.icon, this.hint);
  final PhoneScene scene;
  final String id, label, icon, hint;
}

const List<PhoneSceneMeta> kPhoneScenes = [
  PhoneSceneMeta(PhoneScene.plain, 'plain', 'Plain', 'fa-image', 'Just the file on the screen'),
  PhoneSceneMeta(PhoneScene.lock, 'lock', 'Lock screen', 'fa-lock', 'Clock, date and notifications on top of the wallpaper'),
  PhoneSceneMeta(PhoneScene.home, 'home', 'Home screen', 'fa-house', 'App icons, dock and search bar on top of the wallpaper'),
  PhoneSceneMeta(PhoneScene.app, 'app', 'Zedge app', 'fa-mobile-screen-button', 'How the item page looks inside the Zedge app'),
  PhoneSceneMeta(PhoneScene.call, 'call', 'Incoming call', 'fa-phone', 'Ringtone preview - a call arrives on the phone'),
  PhoneSceneMeta(PhoneScene.notify, 'notify', 'Message', 'fa-message', 'Notification preview - a message arrives on the lock screen'),
];

PhoneSceneMeta sceneMeta(PhoneScene s) => kPhoneScenes.firstWhere((m) => m.scene == s);
PhoneScene sceneById(String id) => kPhoneScenes.where((m) => m.id == id).map((m) => m.scene).firstOrNull ?? PhoneScene.plain;

/// Which scenes hide the small status-bar clock (a big lock-screen clock is shown instead).
bool sceneHidesStatusTime(PhoneScene s) => s == PhoneScene.lock || s == PhoneScene.notify;

/// Which scenes should ring / play the audio of a ringtone item.
bool sceneRings(PhoneScene s) => s == PhoneScene.call || s == PhoneScene.notify;

bool isIosDevice(String deviceId) => deviceId.startsWith('ios');

/// Fills the phone screen: [media] underneath, the scene UI on top.
class PhoneSceneView extends StatefulWidget {
  const PhoneSceneView({
    super.key,
    required this.scene,
    required this.media,
    required this.deviceId,
    required this.title,
    required this.typeLabel,
    this.tags = const [],
    this.creator = 'Meta Hawladar',
    this.isRingtone = false,
    this.playing = false,
    this.replayTick = 0,
    this.onCallAction,
  });
  final PhoneScene scene;
  final Widget media;
  final String deviceId;
  final String title;
  final String typeLabel;
  final List<String> tags;
  final String creator;
  final bool isRingtone;
  /// Audio is currently playing (drives the equalizer bars).
  final bool playing;
  /// Bump to replay the notification / call entrance animation.
  final int replayTick;
  /// Called when the user taps accept (true) or decline (false) on the call scene.
  final ValueChanged<bool>? onCallAction;

  @override
  State<PhoneSceneView> createState() => _PhoneSceneViewState();
}

class _PhoneSceneViewState extends State<PhoneSceneView> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth, h = c.maxHeight;
      final ui_ = _SceneUi(w: w, h: h, ios: isIosDevice(widget.deviceId), deviceId: widget.deviceId);
      switch (widget.scene) {
        case PhoneScene.plain:
          return widget.media;
        case PhoneScene.lock:
          return Stack(fit: StackFit.expand, children: [
            widget.media,
            _Scrim(top: 0.35, bottom: 0.45),
            _LockLayer(u: ui_, title: widget.title, typeLabel: widget.typeLabel, showNotifications: true),
            _LockBottom(u: ui_),
          ]);
        case PhoneScene.home:
          return Stack(fit: StackFit.expand, children: [
            widget.media,
            _Scrim(top: 0.15, bottom: 0.35),
            _HomeLayer(u: ui_),
          ]);
        case PhoneScene.app:
          return _AppLayer(u: ui_, media: widget.media, title: widget.title, typeLabel: widget.typeLabel, tags: widget.tags, creator: widget.creator, isRingtone: widget.isRingtone);
        case PhoneScene.call:
          return Stack(fit: StackFit.expand, children: [
            widget.media,
            ClipRect(child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: const SizedBox.expand())),
            _Scrim(top: 0.55, bottom: 0.72),
            _CallLayer(key: ValueKey('call-${widget.replayTick}'), u: ui_, title: widget.title, isRingtone: widget.isRingtone, playing: widget.playing, onAction: widget.onCallAction),
          ]);
        case PhoneScene.notify:
          return Stack(fit: StackFit.expand, children: [
            widget.media,
            _Scrim(top: 0.35, bottom: 0.45),
            _LockLayer(u: ui_, title: widget.title, typeLabel: widget.typeLabel, showNotifications: false),
            _LockBottom(u: ui_),
            _NotifyLayer(key: ValueKey('notify-${widget.replayTick}'), u: ui_, title: widget.title, typeLabel: widget.typeLabel, isRingtone: widget.isRingtone, playing: widget.playing),
          ]);
      }
    });
  }
}

/// Scale helper - every size is relative to a 232 px wide phone screen.
class _SceneUi {
  _SceneUi({required this.w, required this.h, required this.ios, required this.deviceId});
  final double w, h;
  final bool ios;
  final String deviceId;
  double get s => (w / 232).clamp(0.6, 2.4).toDouble();
  double sz(double v) => v * s;
  /// Safe top below the notch / island / punch-hole and status bar.
  double get safeTop {
    switch (deviceId) {
      case 'ios-island':
        return sz(46);
      case 'ios-notch':
        return sz(40);
      case 'and-drop':
        return sz(36);
      case 'ios-classic':
        return sz(24);
      case 'tablet':
        return sz(30);
      default:
        return sz(34);
    }
  }
  double get safeBottom => deviceId == 'ios-classic' || deviceId == 'tablet' ? sz(10) : sz(22);
  /// Wide (3:4) screens get a denser home grid and no widget row.
  bool get tablet => h / w < 1.5;
  List<Shadow> get textShadow => [Shadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: sz(10))];
  TextStyle white(double size, {FontWeight weight = FontWeight.w600, double alpha = 1, double letterSpacing = 0, double height = 1.15}) =>
      TextStyle(color: Colors.white.withValues(alpha: alpha), fontSize: sz(size), fontWeight: weight, shadows: textShadow, letterSpacing: letterSpacing, height: height);
}

class _Scrim extends StatelessWidget {
  const _Scrim({required this.top, required this.bottom});
  final double top, bottom;
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withValues(alpha: top), Colors.black.withValues(alpha: 0.05), Colors.black.withValues(alpha: 0.05), Colors.black.withValues(alpha: bottom)],
              stops: const [0, 0.3, 0.65, 1],
            ),
          ),
        ),
      );
}

/// Dhaka clock that refreshes itself.
class _LiveClock extends StatefulWidget {
  const _LiveClock({required this.builder});
  final Widget Function(DateTime dhaka) builder;
  @override
  State<_LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<_LiveClock> {
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(getDhakaDate(0));
}

String _hm(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${two(h)}:${two(d.minute)}';
}

String _dateLine(DateTime d) => '${kWeekdayLong[(d.weekday + 6) % 7]}, ${d.day} ${kMonthLong[d.month - 1]}';

// ============================================================ lock screen
class _LockLayer extends StatelessWidget {
  const _LockLayer({required this.u, required this.title, required this.typeLabel, required this.showNotifications, this.pushDown = false});
  final _SceneUi u;
  final String title, typeLabel;
  final bool showNotifications, pushDown;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Positioned(
      top: u.safeTop + (pushDown ? u.sz(54) : u.sz(6)),
      left: u.sz(14),
      right: u.sz(14),
      child: IgnorePointer(
        child: Column(children: [
          _LiveClock(builder: (d) {
            return Column(children: [
              if (u.ios) ...[
                Text(_dateLine(d), style: u.white(12.5, weight: FontWeight.w600, alpha: 0.95)),
                Text(_hm(d), style: u.white(64, weight: FontWeight.w700, letterSpacing: -2, height: 1.05)),
              ] else ...[
                Text(_hm(d), style: u.white(70, weight: FontWeight.w300, letterSpacing: -2, height: 1.0)),
                Text(_dateLine(d), style: u.white(12.5, weight: FontWeight.w500, alpha: 0.92)),
              ],
            ]);
          }),
          if (showNotifications && !u.tablet) ...[
            SizedBox(height: u.sz(18)),
            _NotifCard(
              u: u,
              icon: 'fa-bolt',
              gradient: p.primaryGradient,
              app: 'Zedge',
              time: 'now',
              heading: 'Your upload is live',
              body: '"$title" is now on Zedge · $typeLabel',
            ),
            SizedBox(height: u.sz(8)),
            _NotifCard(
              u: u,
              icon: 'fa-solid-comment',
              gradient: const LinearGradient(colors: [Color(0xff34c759), Color(0xff1f9d4a)]),
              app: 'Messages',
              time: '2m',
              heading: 'Rafi',
              body: 'Bro ei wallpaper ta dekh - joss hoise!',
            ),
          ],
        ]),
      ),
    );
  }
}

/// Glass notification card (lock screen / banner).
class _NotifCard extends StatelessWidget {
  const _NotifCard({required this.u, required this.icon, required this.gradient, required this.app, required this.time, required this.heading, required this.body, this.trailing});
  final _SceneUi u;
  final String icon, app, time, heading, body;
  final Gradient gradient;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final r = u.sz(u.ios ? 18 : 14);
    return ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: EdgeInsets.all(u.sz(10)),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: u.ios ? 0.22 : 0.16),
            borderRadius: BorderRadius.circular(r),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 0.8),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: u.sz(30),
              height: u.sz(30),
              decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(u.sz(u.ios ? 8 : 15))),
              alignment: Alignment.center,
              child: Fa(icon, size: u.sz(13), color: Colors.white),
            ),
            SizedBox(width: u.sz(9)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(u.ios ? heading : app.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: u.white(u.ios ? 11.5 : 9.5, weight: FontWeight.w800, alpha: u.ios ? 1 : 0.8, letterSpacing: u.ios ? 0 : 0.6))),
                  Text(time, style: u.white(9.5, weight: FontWeight.w500, alpha: 0.75)),
                ]),
                if (!u.ios) Text(heading, maxLines: 1, overflow: TextOverflow.ellipsis, style: u.white(11.5, weight: FontWeight.w800)),
                SizedBox(height: u.sz(1)),
                Text(body, maxLines: 2, overflow: TextOverflow.ellipsis, style: u.white(10.5, weight: FontWeight.w500, alpha: 0.92, height: 1.3)),
              ]),
            ),
            if (trailing != null) ...[SizedBox(width: u.sz(8)), trailing!],
          ]),
        ),
      ),
    );
  }
}

/// Flashlight / camera (iOS) or phone / fingerprint / camera (Android) at the bottom of the lock screen.
class _LockBottom extends StatelessWidget {
  const _LockBottom({required this.u});
  final _SceneUi u;

  Widget _round(String icon) => Container(
        width: u.sz(44),
        height: u.sz(44),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.18))),
        alignment: Alignment.center,
        child: Fa(icon, size: u.sz(15), color: Colors.white),
      );

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: u.sz(26),
      right: u.sz(26),
      bottom: u.safeBottom + u.sz(6),
      child: IgnorePointer(
        child: u.ios
            ? Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_round('fa-lightbulb'), _round('fa-camera')])
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: u.sz(52),
                  height: u.sz(52),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: u.sz(1.6)), color: Colors.black.withValues(alpha: 0.25)),
                  alignment: Alignment.center,
                  child: Fa('fa-fingerprint', size: u.sz(22), color: Colors.white),
                ),
                SizedBox(height: u.sz(10)),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_round('fa-phone'), Text('Swipe up to unlock', style: u.white(9.5, weight: FontWeight.w500, alpha: 0.85)), _round('fa-camera')]),
              ]),
      ),
    );
  }
}

// ============================================================ home screen
class _AppIconSpec {
  const _AppIconSpec(this.label, this.icon, this.c1, this.c2, {this.fg = Colors.white});
  final String label, icon;
  final Color c1, c2, fg;
}

const List<_AppIconSpec> _kHomeApps = [
  _AppIconSpec('Phone', 'fa-phone', Color(0xff34c759), Color(0xff1f9d4a)),
  _AppIconSpec('Messages', 'fa-solid-comment', Color(0xff5ac8fa), Color(0xff2f80ed)),
  _AppIconSpec('Camera', 'fa-camera', Color(0xff6b7280), Color(0xff374151)),
  _AppIconSpec('Zedge', 'fa-bolt', Color(0xff7c5cff), Color(0xff22d3ee)),
  _AppIconSpec('Photos', 'fa-solid-image', Color(0xfffb923c), Color(0xffec4899)),
  _AppIconSpec('YouTube', 'fa-youtube', Color(0xffff3b30), Color(0xffc81e1e)),
  _AppIconSpec('Instagram', 'fa-instagram', Color(0xfff58529), Color(0xff8134af)),
  _AppIconSpec('WhatsApp', 'fa-whatsapp', Color(0xff25d366), Color(0xff128c7e)),
  _AppIconSpec('Spotify', 'fa-spotify', Color(0xff1db954), Color(0xff0f7a37)),
  _AppIconSpec('Maps', 'fa-map-location-dot', Color(0xff4285f4), Color(0xff34a853)),
  _AppIconSpec('Clock', 'fa-solid-clock', Color(0xff1f2937), Color(0xff000000)),
  _AppIconSpec('Calendar', 'fa-calendar-days', Color(0xffffffff), Color(0xffe5e7eb), fg: Color(0xffef4444)),
  _AppIconSpec('Settings', 'fa-gear', Color(0xff9ca3af), Color(0xff4b5563)),
  _AppIconSpec('Facebook', 'fa-facebook', Color(0xff1877f2), Color(0xff0c5ccf)),
  _AppIconSpec('TikTok', 'fa-tiktok', Color(0xff111111), Color(0xff000000)),
];

class _HomeLayer extends StatelessWidget {
  const _HomeLayer({required this.u});
  final _SceneUi u;

  Widget _icon(_AppIconSpec a, {bool label = true, Gradient? override, double? size}) {
    size ??= u.sz(44);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: override ?? LinearGradient(colors: [a.c1, a.c2], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(u.sz(u.ios ? 11 : 22)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: u.sz(8), offset: Offset(0, u.sz(3)))],
        ),
        alignment: Alignment.center,
        child: Fa(a.icon, size: size * 0.43, color: a.fg),
      ),
      if (label) ...[
        SizedBox(height: u.sz(4)),
        Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: u.white(9, weight: FontWeight.w600)),
      ],
    ]);
  }

  Widget _searchPill(BuildContext context) => Container(
        height: u.sz(38),
        padding: EdgeInsets.symmetric(horizontal: u.sz(14)),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: u.ios ? 0.22 : 0.92), borderRadius: BorderRadius.circular(u.sz(22)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: u.sz(10), offset: Offset(0, u.sz(3)))]),
        child: Row(children: [
          Fa(u.ios ? 'fa-magnifying-glass' : 'fa-google', size: u.sz(13), color: u.ios ? Colors.white : const Color(0xff4285f4)),
          SizedBox(width: u.sz(8)),
          Expanded(child: Text('Search', style: TextStyle(fontSize: u.sz(12), color: u.ios ? Colors.white : const Color(0xff374151), fontWeight: FontWeight.w500))),
          if (!u.ios) Fa('fa-microphone', size: u.sz(13), color: const Color(0xff4285f4)),
          if (!u.ios) ...[SizedBox(width: u.sz(10)), Fa('fa-camera', size: u.sz(13), color: const Color(0xff34a853))],
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final apps = _kHomeApps;
    final zedge = LinearGradient(colors: [p.primary, p.accent], begin: Alignment.topLeft, end: Alignment.bottomRight);
    final dock = [apps[0], apps[1], apps[7], apps[2]];
    final cols = u.tablet ? 6 : 4;
    final tileW = (u.w - u.sz(24) - u.sz(6) * (cols - 1)) / cols;
    final iconSize = math.min(u.sz(44), tileW * 0.74);
    final tileH = iconSize + u.sz(17);
    return Positioned.fill(
      child: IgnorePointer(
        child: Padding(
          padding: EdgeInsets.fromLTRB(u.sz(12), u.safeTop + u.sz(4), u.sz(12), u.safeBottom + u.sz(4)),
          child: Column(children: [
            if (!u.ios && !u.tablet) ...[
              // Android: at-a-glance date + weather widget
              _LiveClock(builder: (d) => Row(children: [
                    Text(_dateLine(d), style: u.white(12.5, weight: FontWeight.w600)),
                    const Spacer(),
                    Fa('fa-cloud-sun', size: u.sz(12), color: Colors.white),
                    SizedBox(width: u.sz(5)),
                    Text('31°', style: u.white(12.5, weight: FontWeight.w600)),
                  ])),
              SizedBox(height: u.sz(14)),
            ] else if (u.ios && !u.tablet) ...[
              // iOS: big clock widget row
              _LiveClock(builder: (d) => Row(children: [
                    Expanded(
                      child: Container(
                        height: u.sz(78),
                        padding: EdgeInsets.all(u.sz(10)),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(u.sz(16))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text(_dateLine(d).split(',').first.toUpperCase(), style: u.white(9, weight: FontWeight.w800, alpha: 0.8, letterSpacing: 0.6)),
                          Text(_hm(d), style: u.white(26, weight: FontWeight.w700, letterSpacing: -1)),
                        ]),
                      ),
                    ),
                    SizedBox(width: u.sz(10)),
                    Expanded(
                      child: Container(
                        height: u.sz(78),
                        padding: EdgeInsets.all(u.sz(10)),
                        decoration: BoxDecoration(gradient: LinearGradient(colors: [p.primary.withValues(alpha: 0.85), p.accent.withValues(alpha: 0.85)]), borderRadius: BorderRadius.circular(u.sz(16))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Row(children: [Fa('fa-bolt', size: u.sz(10), color: Colors.white), SizedBox(width: u.sz(4)), Text('ZEDGE', style: u.white(9, weight: FontWeight.w800, letterSpacing: 0.6))]),
                          Text('3 uploads\nscheduled today', style: u.white(10.5, weight: FontWeight.w700, height: 1.2)),
                        ]),
                      ),
                    ),
                  ])),
              SizedBox(height: u.sz(14)),
            ],
            // 4 x 4 grid
            Expanded(
              child: GridView.count(
                crossAxisCount: cols,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                mainAxisSpacing: u.sz(12),
                crossAxisSpacing: u.sz(6),
                childAspectRatio: tileW / tileH,
                children: [
                  for (var i = 3; i < apps.length; i++) _icon(apps[i], size: iconSize, override: apps[i].label == 'Zedge' ? zedge : null),
                ],
              ),
            ),
            // page dots
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < 3; i++)
                Container(width: u.sz(5), height: u.sz(5), margin: EdgeInsets.symmetric(horizontal: u.sz(3)), decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: i == 1 ? 0.95 : 0.4))),
            ]),
            SizedBox(height: u.sz(10)),
            // dock
            ClipRRect(
              borderRadius: BorderRadius.circular(u.sz(u.ios ? 26 : 30)),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: u.sz(12), vertical: u.sz(9)),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(u.sz(u.ios ? 26 : 30))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [for (final a in dock) _icon(a, label: false)]),
                ),
              ),
            ),
            if (!u.ios) ...[SizedBox(height: u.sz(10)), _searchPill(context)],
          ]),
        ),
      ),
    );
  }
}

// ============================================================ Zedge app item page
class _AppLayer extends StatelessWidget {
  const _AppLayer({required this.u, required this.media, required this.title, required this.typeLabel, required this.tags, required this.creator, required this.isRingtone});
  final _SceneUi u;
  final Widget media;
  final String title, typeLabel, creator;
  final List<String> tags;
  final bool isRingtone;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    const bg = Color(0xff0b0b12);
    const card = Color(0xff15151f);
    final chips = (tags.isNotEmpty ? tags : const ['wallpaper', 'hd', 'aesthetic', '4k']).take(4).toList();
    final cta = isRingtone ? 'Set as Ringtone' : (typeLabel.toLowerCase().contains('live') ? 'Set Live Wallpaper' : (typeLabel.toLowerCase().contains('charging') ? 'Set Charging Animation' : 'Set as Wallpaper'));
    Widget navItem(String icon, String label, bool on) => Column(mainAxisSize: MainAxisSize.min, children: [
          Fa(icon, size: u.sz(14), color: on ? p.primary : Colors.white.withValues(alpha: 0.55)),
          SizedBox(height: u.sz(3)),
          Text(label, style: TextStyle(fontSize: u.sz(8.5), color: on ? p.primary : Colors.white.withValues(alpha: 0.55), fontWeight: FontWeight.w700)),
        ]);
    Widget stat(String icon, String v) => Row(mainAxisSize: MainAxisSize.min, children: [
          Fa(icon, size: u.sz(10), color: Colors.white.withValues(alpha: 0.7)),
          SizedBox(width: u.sz(4)),
          Text(v, style: TextStyle(fontSize: u.sz(10), color: Colors.white.withValues(alpha: 0.8), fontWeight: FontWeight.w600)),
        ]);
    return Container(
      color: bg,
      padding: EdgeInsets.only(top: u.safeTop, bottom: u.safeBottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // app bar
        Padding(
          padding: EdgeInsets.symmetric(horizontal: u.sz(14), vertical: u.sz(4)),
          child: Row(children: [
            Fa('fa-arrow-left', size: u.sz(13), color: Colors.white),
            SizedBox(width: u.sz(12)),
            Container(width: u.sz(18), height: u.sz(18), decoration: BoxDecoration(gradient: p.primaryGradient, borderRadius: BorderRadius.circular(u.sz(5))), alignment: Alignment.center, child: Fa('fa-bolt', size: u.sz(9), color: Colors.white)),
            SizedBox(width: u.sz(6)),
            Text('zedge', style: TextStyle(fontSize: u.sz(15), fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
            const Spacer(),
            Fa('fa-magnifying-glass', size: u.sz(13), color: Colors.white),
            SizedBox(width: u.sz(14)),
            Fa('fa-share', size: u.sz(13), color: Colors.white),
          ]),
        ),
        // media card
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(u.sz(14), u.sz(6), u.sz(14), u.sz(8)),
            child: Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(u.sz(18)), border: Border.all(color: Colors.white.withValues(alpha: 0.08)), boxShadow: [BoxShadow(color: p.primary.withValues(alpha: 0.25), blurRadius: u.sz(24), offset: Offset(0, u.sz(8)))]),
              clipBehavior: Clip.antiAlias,
              child: Stack(fit: StackFit.expand, children: [
                ColoredBox(color: card, child: media),
                Positioned(
                  left: u.sz(8),
                  top: u.sz(8),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: u.sz(7), vertical: u.sz(3)),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(u.sz(6))),
                    child: Text(typeLabel.toUpperCase(), style: TextStyle(fontSize: u.sz(7.5), color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                  ),
                ),
                Positioned(
                  right: u.sz(8),
                  top: u.sz(8),
                  child: Container(width: u.sz(26), height: u.sz(26), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), shape: BoxShape.circle), alignment: Alignment.center, child: Fa('fa-heart', size: u.sz(11), color: Colors.white)),
                ),
              ]),
            ),
          ),
        ),
        // title + creator + stats
        Padding(
          padding: EdgeInsets.symmetric(horizontal: u.sz(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: u.sz(13), fontWeight: FontWeight.w800, color: Colors.white)),
            SizedBox(height: u.sz(3)),
            Row(children: [
              Container(width: u.sz(14), height: u.sz(14), decoration: BoxDecoration(gradient: p.primaryGradient, shape: BoxShape.circle), alignment: Alignment.center, child: Text(creator.isNotEmpty ? creator[0].toUpperCase() : 'M', style: TextStyle(fontSize: u.sz(7.5), fontWeight: FontWeight.w900, color: Colors.white))),
              SizedBox(width: u.sz(5)),
              Expanded(child: Text('by $creator', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: u.sz(9.5), color: Colors.white.withValues(alpha: 0.65)))),
              stat('fa-download', '12.4K'),
              SizedBox(width: u.sz(10)),
              stat('fa-solid-heart', '1.2K'),
            ]),
            SizedBox(height: u.sz(7)),
            Row(children: [
              for (final t in chips)
                Container(
                  margin: EdgeInsets.only(right: u.sz(5)),
                  padding: EdgeInsets.symmetric(horizontal: u.sz(7), vertical: u.sz(3)),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(u.sz(6)), border: Border.all(color: Colors.white.withValues(alpha: 0.1))),
                  child: Text('#$t', style: TextStyle(fontSize: u.sz(8.5), color: Colors.white.withValues(alpha: 0.8), fontWeight: FontWeight.w600)),
                ),
            ]),
            SizedBox(height: u.sz(8)),
            Container(
              height: u.sz(34),
              decoration: BoxDecoration(gradient: p.primaryGradient, borderRadius: BorderRadius.circular(u.sz(12)), boxShadow: [BoxShadow(color: p.primary.withValues(alpha: 0.4), blurRadius: u.sz(14), offset: Offset(0, u.sz(4)))]),
              alignment: Alignment.center,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Fa(isRingtone ? 'fa-music' : 'fa-download', size: u.sz(11), color: p.onPrimary),
                SizedBox(width: u.sz(6)),
                Text(cta, style: TextStyle(fontSize: u.sz(11), fontWeight: FontWeight.w800, color: p.onPrimary)),
              ]),
            ),
          ]),
        ),
        SizedBox(height: u.sz(8)),
        // bottom nav
        Container(
          padding: EdgeInsets.symmetric(vertical: u.sz(6)),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08)))),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            navItem('fa-house', 'Home', true),
            navItem('fa-compass', 'Discover', false),
            navItem('fa-heart', 'Saved', false),
            navItem('fa-user', 'Profile', false),
          ]),
        ),
      ]),
    );
  }
}

// ============================================================ incoming call
class _CallLayer extends StatefulWidget {
  const _CallLayer({super.key, required this.u, required this.title, required this.isRingtone, required this.playing, this.onAction});
  final _SceneUi u;
  final String title;
  final bool isRingtone, playing;
  final ValueChanged<bool>? onAction;

  @override
  State<_CallLayer> createState() => _CallLayerState();
}

class _CallLayerState extends State<_CallLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();
  bool _answered = false;
  bool _ended = false;
  int _secs = 0;
  Timer? _t;

  @override
  void dispose() {
    _pulse.dispose();
    _t?.cancel();
    super.dispose();
  }

  void _accept() {
    _t?.cancel();
    setState(() {
      _answered = true;
      _secs = 0;
    });
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _secs++);
    });
    widget.onAction?.call(true);
  }

  void _decline() {
    _t?.cancel();
    setState(() {
      _ended = true;
      _answered = false;
    });
    widget.onAction?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.u;
    final ringing = !_answered && !_ended;
    // short screens (tablet frame / small zoom) get a tighter layout
    final compact = u.h < u.sz(600);
    final av = compact ? 64.0 : 84.0;
    final avatar = SizedBox(
      width: u.sz(av + 28),
      height: u.sz(av + 28),
      child: Stack(alignment: Alignment.center, children: [
        if (ringing)
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) {
              return Stack(alignment: Alignment.center, children: [
                for (final off in [0.0, 0.5])
                  Builder(builder: (_) {
                    final t = (_pulse.value + off) % 1.0;
                    return Container(
                      width: u.sz(av + 28 * t),
                      height: u.sz(av + 28 * t),
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: (1 - t) * 0.55), width: u.sz(1.5))),
                    );
                  }),
              ]);
            },
          ),
        Container(
          width: u.sz(av),
          height: u.sz(av),
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [Color(0xfff472b6), Color(0xff7c5cff)], begin: Alignment.topLeft, end: Alignment.bottomRight), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: u.sz(18), offset: Offset(0, u.sz(8)))]),
          alignment: Alignment.center,
          child: Text('A', style: TextStyle(fontSize: u.sz(av * 0.42), fontWeight: FontWeight.w800, color: Colors.white)),
        ),
      ]),
    );

    Widget roundBtn(Color c, String icon, String label, VoidCallback? onTap, {bool big = true, double turns = 0}) => Column(mainAxisSize: MainAxisSize.min, children: [
          MouseRegion(
            cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                width: u.sz(big ? 60 : 40),
                height: u.sz(big ? 60 : 40),
                decoration: BoxDecoration(color: c, shape: BoxShape.circle, boxShadow: [BoxShadow(color: c.withValues(alpha: 0.45), blurRadius: u.sz(16), offset: Offset(0, u.sz(6)))]),
                alignment: Alignment.center,
                child: RotationTransition(turns: AlwaysStoppedAnimation(turns), child: Fa(icon, size: u.sz(big ? 23 : 14), color: Colors.white)),
              ),
            ),
          ),
          SizedBox(height: u.sz(6)),
          Text(label, style: u.white(10, weight: FontWeight.w600, alpha: 0.9)),
        ]);

    final ringtoneName = widget.isRingtone ? widget.title : 'Default ringtone';
    final mm = two(_secs ~/ 60), ss = two(_secs % 60);

    return Positioned.fill(
      child: Padding(
        padding: EdgeInsets.fromLTRB(u.sz(18), u.safeTop + u.sz(compact ? 6 : (u.ios ? 16 : 24)), u.sz(18), u.safeBottom + u.sz(compact ? 6 : 12)),
        child: Column(children: [
          if (!u.ios) ...[avatar, SizedBox(height: u.sz(10))],
          Text('Ammu', style: u.white(u.ios ? 30 : 26, weight: FontWeight.w600, letterSpacing: -0.5)),
          SizedBox(height: u.sz(3)),
          Text(
            _ended ? 'Call ended' : (_answered ? '$mm:$ss' : (u.ios ? 'mobile · Bangladesh' : 'Incoming call · mobile')),
            style: u.white(12.5, weight: FontWeight.w500, alpha: 0.8),
          ),
          if (u.ios) ...[SizedBox(height: u.sz(compact ? 10 : 20)), avatar],
          SizedBox(height: u.sz(compact ? 8 : 16)),
          // ringtone card
          if (!compact) IgnorePointer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(u.sz(14)),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: u.sz(12), vertical: u.sz(9)),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(u.sz(14)), border: Border.all(color: Colors.white.withValues(alpha: 0.18))),
                  child: Row(children: [
                    _EqBars(u: u, active: ringing && (widget.playing || !widget.isRingtone)),
                    SizedBox(width: u.sz(10)),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(ringing ? 'RINGTONE PLAYING' : (_answered ? 'ON CALL' : 'RINGTONE'), style: u.white(8, weight: FontWeight.w800, alpha: 0.7, letterSpacing: 0.8)),
                        Text(ringtoneName, maxLines: 1, overflow: TextOverflow.ellipsis, style: u.white(11, weight: FontWeight.w700)),
                      ]),
                    ),
                    Fa(widget.isRingtone ? 'fa-music' : 'fa-bell', size: u.sz(12), color: Colors.white.withValues(alpha: 0.8)),
                  ]),
                ),
              ),
            ),
          ),
          const Spacer(),
          if (ringing) ...[
            if (u.ios && !compact) ...[
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                roundBtn(Colors.white.withValues(alpha: 0.18), 'fa-clock', 'Remind Me', null, big: false),
                roundBtn(Colors.white.withValues(alpha: 0.18), 'fa-solid-comment', 'Message', null, big: false),
              ]),
              SizedBox(height: u.sz(14)),
            ],
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              roundBtn(const Color(0xffff3b30), 'fa-phone', 'Decline', _decline, turns: 0.375),
              if (!u.ios) roundBtn(Colors.white.withValues(alpha: 0.18), 'fa-solid-comment', 'Reply', null, big: false),
              _RingingPhone(u: u, child: roundBtn(const Color(0xff34c759), 'fa-phone', 'Accept', _accept)),
            ]),
          ] else if (_answered) ...[
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              roundBtn(Colors.white.withValues(alpha: 0.18), 'fa-microphone-slash', 'Mute', null, big: false),
              roundBtn(Colors.white.withValues(alpha: 0.18), 'fa-keyboard', 'Keypad', null, big: false),
              roundBtn(Colors.white.withValues(alpha: 0.18), 'fa-volume-high', 'Speaker', null, big: false),
            ]),
            SizedBox(height: u.sz(18)),
            roundBtn(const Color(0xffff3b30), 'fa-phone', 'End', _decline, turns: 0.375),
          ] else ...[
            Text('Pick "Incoming call" again or press Replay to ring once more', textAlign: TextAlign.center, style: u.white(10, weight: FontWeight.w500, alpha: 0.7)),
          ],
        ]),
      ),
    );
  }
}

/// Gentle shake of the accept button while ringing.
class _RingingPhone extends StatefulWidget {
  const _RingingPhone({required this.u, required this.child});
  final _SceneUi u;
  final Widget child;
  @override
  State<_RingingPhone> createState() => _RingingPhoneState();
}

class _RingingPhoneState extends State<_RingingPhone> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final t = _c.value;
        // shake for the first 40% of the cycle, rest still
        final a = t < 0.4 ? math.sin(t / 0.4 * math.pi * 4) * 0.06 : 0.0;
        return Transform.rotate(angle: a, child: child);
      },
      child: widget.child,
    );
  }
}

/// Five animated equalizer bars.
class _EqBars extends StatefulWidget {
  const _EqBars({required this.u, required this.active});
  final _SceneUi u;
  final bool active;
  @override
  State<_EqBars> createState() => _EqBarsState();
}

class _EqBarsState extends State<_EqBars> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant _EqBars old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) _c.repeat();
    if (!widget.active && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.u;
    final hMax = u.sz(22);
    return SizedBox(
      width: u.sz(26),
      height: hMax,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < 5; i++)
            Builder(builder: (_) {
              final phase = _c.value * 2 * math.pi + i * 1.1;
              final f = widget.active ? 0.35 + 0.65 * (0.5 + 0.5 * math.sin(phase)) : 0.25;
              return Container(width: u.sz(3.2), height: hMax * f, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(u.sz(2))));
            }),
        ]),
      ),
    );
  }
}

// ============================================================ message notification
class _NotifyLayer extends StatefulWidget {
  const _NotifyLayer({super.key, required this.u, required this.title, required this.typeLabel, required this.isRingtone, required this.playing});
  final _SceneUi u;
  final String title, typeLabel;
  final bool isRingtone, playing;

  @override
  State<_NotifyLayer> createState() => _NotifyLayerState();
}

class _NotifyLayerState extends State<_NotifyLayer> with TickerProviderStateMixin {
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late final AnimationController _in2 = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _in.forward();
    _t = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) _in2.forward();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _in.dispose();
    _in2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.u;
    final p = context.pal;
    final slide1 = Tween<Offset>(begin: const Offset(0, -1.6), end: Offset.zero).animate(CurvedAnimation(parent: _in, curve: Curves.easeOutBack));
    final slide2 = Tween<Offset>(begin: const Offset(0, -0.6), end: Offset.zero).animate(CurvedAnimation(parent: _in2, curve: Curves.easeOutCubic));
    return Positioned(
      // below the big lock-screen clock, like a real incoming notification
      top: u.safeTop + u.sz(u.tablet ? 96 : 104),
      left: u.sz(12),
      right: u.sz(12),
      child: IgnorePointer(
        child: Column(children: [
          SlideTransition(
            position: slide1,
            child: FadeTransition(
              opacity: _in,
              child: _NotifCard(
                u: u,
                icon: 'fa-solid-comment',
                gradient: const LinearGradient(colors: [Color(0xff34c759), Color(0xff1f9d4a)]),
                app: 'Messages',
                time: 'now',
                heading: 'Rafi',
                body: 'Bro "${widget.title}" ta dekhso? Zedge e upload dilam - joss hoise!',
                trailing: _NotifyPulse(u: u, active: widget.playing || !widget.isRingtone),
              ),
            ),
          ),
          SizedBox(height: u.sz(8)),
          SlideTransition(
            position: slide2,
            child: FadeTransition(
              opacity: _in2,
              child: _NotifCard(
                u: u,
                icon: 'fa-bolt',
                gradient: p.primaryGradient,
                app: 'Zedge',
                time: '1m',
                heading: widget.isRingtone ? 'New notification sound' : 'Upload live',
                body: widget.isRingtone ? '"${widget.title}" is set as your notification tone' : '"${widget.title}" · ${widget.typeLabel} is live on Zedge',
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Small pulsing bell / sound-wave badge on the message banner.
class _NotifyPulse extends StatefulWidget {
  const _NotifyPulse({required this.u, required this.active});
  final _SceneUi u;
  final bool active;
  @override
  State<_NotifyPulse> createState() => _NotifyPulseState();
}

class _NotifyPulseState extends State<_NotifyPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.u;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Opacity(
        opacity: widget.active ? 0.55 + 0.45 * _c.value : 0.5,
        child: Container(
          width: u.sz(22),
          height: u.sz(22),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Fa('fa-volume-high', size: u.sz(9), color: Colors.white),
        ),
      ),
    );
  }
}

/// Scene chooser (segmented row) used under the phone / in the preview toolbar.
class SceneChooser extends StatelessWidget {
  const SceneChooser({super.key, required this.active, required this.onChanged, this.compact = false});
  final PhoneScene active;
  final ValueChanged<PhoneScene> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: p.surfaceHover.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(999), border: Border.all(color: p.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final m in kPhoneScenes)
          Tooltip(
            message: '${m.label} - ${m.hint}',
            waitDuration: const Duration(milliseconds: 400),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => onChanged(m.scene),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 11, vertical: 6),
                  decoration: BoxDecoration(gradient: m.scene == active ? p.buttonGradient : null, borderRadius: BorderRadius.circular(999)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Fa(m.icon, size: 11, color: m.scene == active ? p.buttonFg : p.muted),
                    if (!compact || m.scene == active) ...[
                      const SizedBox(width: 6),
                      Text(m.label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: m.scene == active ? p.buttonFg : p.text)),
                    ],
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
