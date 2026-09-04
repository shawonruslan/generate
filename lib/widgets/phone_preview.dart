import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/queue_item.dart';
import '../theme/app_theme.dart';

enum NotchStyle { island, wideNotch, dotCenter, dotLeft, teardrop, none }

/// One selectable phone shape. Adding a device = adding one entry here.
class DevicePreset {
  const DevicePreset({
    required this.id,
    required this.label,
    required this.icon,
    required this.aspect,
    required this.bodyRadius,
    required this.screenRadius,
    required this.padding,
    required this.notch,
    this.homeButton = false,
    this.widthScale = 1.0,
  });

  final String id;
  final String label;
  final IconData icon;
  final double aspect; // width / height of the screen
  final double bodyRadius;
  final double screenRadius;
  final EdgeInsets padding;
  final NotchStyle notch;
  final bool homeButton;
  final double widthScale;
}

const List<DevicePreset> kDevicePresets = <DevicePreset>[
  DevicePreset(
    id: 'ios-island',
    label: 'iPhone 16 Pro',
    icon: Icons.phone_iphone_rounded,
    aspect: 9 / 19.5,
    bodyRadius: 42,
    screenRadius: 33,
    padding: EdgeInsets.fromLTRB(11, 12, 11, 10),
    notch: NotchStyle.island,
  ),
  DevicePreset(
    id: 'ios-notch',
    label: 'iPhone 14',
    icon: Icons.phone_iphone_rounded,
    aspect: 9 / 19.5,
    bodyRadius: 38,
    screenRadius: 29,
    padding: EdgeInsets.fromLTRB(11, 12, 11, 10),
    notch: NotchStyle.wideNotch,
  ),
  DevicePreset(
    id: 'ios-classic',
    label: 'iPhone SE',
    icon: Icons.smartphone_rounded,
    aspect: 9 / 16,
    bodyRadius: 26,
    screenRadius: 4,
    padding: EdgeInsets.fromLTRB(10, 42, 10, 52),
    notch: NotchStyle.none,
    homeButton: true,
  ),
  DevicePreset(
    id: 'and-dot',
    label: 'Dot Notch',
    icon: Icons.smartphone_rounded,
    aspect: 9 / 20,
    bodyRadius: 34,
    screenRadius: 27,
    padding: EdgeInsets.fromLTRB(9, 10, 9, 9),
    notch: NotchStyle.dotCenter,
  ),
  DevicePreset(
    id: 'and-dot-left',
    label: 'Dot Left',
    icon: Icons.smartphone_rounded,
    aspect: 9 / 20,
    bodyRadius: 34,
    screenRadius: 27,
    padding: EdgeInsets.fromLTRB(9, 10, 9, 9),
    notch: NotchStyle.dotLeft,
  ),
  DevicePreset(
    id: 'and-drop',
    label: 'Teardrop',
    icon: Icons.smartphone_rounded,
    aspect: 9 / 19.5,
    bodyRadius: 32,
    screenRadius: 25,
    padding: EdgeInsets.fromLTRB(9, 10, 9, 9),
    notch: NotchStyle.teardrop,
  ),
  DevicePreset(
    id: 'and-curved',
    label: 'Galaxy Edge',
    icon: Icons.phone_android_rounded,
    aspect: 9 / 21,
    bodyRadius: 40,
    screenRadius: 34,
    padding: EdgeInsets.fromLTRB(7, 9, 7, 8),
    notch: NotchStyle.dotCenter,
  ),
  DevicePreset(
    id: 'and-flat',
    label: 'Bezel-less',
    icon: Icons.crop_portrait_rounded,
    aspect: 9 / 20,
    bodyRadius: 30,
    screenRadius: 24,
    padding: EdgeInsets.all(8),
    notch: NotchStyle.none,
  ),
  DevicePreset(
    id: 'tablet',
    label: 'Tablet',
    icon: Icons.tablet_mac_rounded,
    aspect: 3 / 4,
    bodyRadius: 26,
    screenRadius: 12,
    padding: EdgeInsets.fromLTRB(14, 16, 14, 14),
    notch: NotchStyle.none,
    widthScale: 1.28,
  ),
];

/// Phone mock-up with a device switcher and the auto rotating presentation.
///
/// Everything is drawn by Flutter (no WebView, no HTML): the frame is a
/// decorated box, the cut-outs are painted shapes, and images crossfade with a
/// standard [AnimatedSwitcher].
class PhonePreview extends StatefulWidget {
  const PhonePreview({
    super.key,
    required this.frames,
    this.autoPlay = false,
    this.baseWidth = 250,
    this.showDeviceChooser = true,
    this.showControls = true,
    this.audioLabel,
    this.onFrameChanged,
  });

  final List<PreviewFrame> frames;
  final bool autoPlay;
  final double baseWidth;
  final bool showDeviceChooser;
  final bool showControls;

  /// When set the screen shows the ringtone face instead of an image.
  final String? audioLabel;
  final ValueChanged<int>? onFrameChanged;

  @override
  State<PhonePreview> createState() => _PhonePreviewState();
}

class _PhonePreviewState extends State<PhonePreview> {
  static const List<int> _speeds = <int>[2000, 3000, 5000, 8000];

  DevicePreset _device = kDevicePresets.first;
  int _index = 0;
  int _speed = 3000;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _restorePreferences();
    if (widget.autoPlay && widget.frames.length > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _play());
    }
  }

  @override
  void didUpdateWidget(PhonePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.frames.length != widget.frames.length) {
      _index = 0;
      _stop();
      if (widget.autoPlay && widget.frames.length > 1) _play();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _restorePreferences() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? deviceId = prefs.getString('previewDeviceId');
    final int? speed = prefs.getInt('presentationSpeed');
    if (!mounted) return;
    setState(() {
      _device = kDevicePresets.firstWhere(
        (DevicePreset preset) => preset.id == deviceId,
        orElse: () => kDevicePresets.first,
      );
      if (speed != null && _speeds.contains(speed)) _speed = speed;
    });
  }

  Future<void> _selectDevice(DevicePreset preset) async {
    setState(() => _device = preset);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('previewDeviceId', preset.id);
  }

  void _play() {
    if (widget.frames.length < 2) return;
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(milliseconds: _speed),
      (_) => _step(1),
    );
    setState(() {});
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    if (mounted) setState(() {});
  }

  void _step(int delta) {
    if (widget.frames.isEmpty) return;
    setState(() {
      _index = (_index + delta + widget.frames.length) % widget.frames.length;
    });
    widget.onFrameChanged?.call(_index);
  }

  Future<void> _cycleSpeed() async {
    final int next = _speeds[(_speeds.indexOf(_speed) + 1) % _speeds.length];
    setState(() => _speed = next);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt('presentationSpeed', next);
    if (_timer != null) _play();
  }

  bool get _playing => _timer != null;

  @override
  Widget build(BuildContext context) {
    final double width = widget.baseWidth * _device.widthScale;
    final PreviewFrame? frame =
        widget.frames.isEmpty ? null : widget.frames[_index.clamp(0, widget.frames.length - 1)];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: width,
          child: _PhoneBody(
            device: _device,
            child: widget.audioLabel != null
                ? _AudioFace(label: widget.audioLabel!)
                : _ImageFace(frame: frame),
          ),
        ),
        if (widget.showControls && widget.frames.length > 1) ...<Widget>[
          const SizedBox(height: 12),
          _ControlBar(
            playing: _playing,
            index: _index,
            total: widget.frames.length,
            speedLabel: '${_speed ~/ 1000}s',
            label: frame?.label ?? '',
            onPrev: () {
              _stop();
              _step(-1);
            },
            onNext: () {
              _stop();
              _step(1);
            },
            onToggle: () => _playing ? _stop() : _play(),
            onSpeed: _cycleSpeed,
          ),
        ],
        if (widget.showDeviceChooser) ...<Widget>[
          const SizedBox(height: 12),
          _DeviceChooser(active: _device, onSelect: _selectDevice),
        ],
      ],
    );
  }
}

class _PhoneBody extends StatelessWidget {
  const _PhoneBody({required this.device, required this.child});

  final DevicePreset device;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      padding: device.padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(device.bodyRadius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF2A2416), Color(0xFF13100A)],
        ),
        border: Border.all(color: const Color(0xFF3A3426), width: 2),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 44,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AspectRatio(
            aspectRatio: device.aspect,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(device.screenRadius),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  ColoredBox(color: const Color(0xFF17140C), child: child),
                  const _StatusBar(),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _CutoutPainter(device.notch),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 9),
          if (device.homeButton)
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF14110A),
                border: Border.all(color: const Color(0xFF3F3828), width: 2),
              ),
            )
          else
            Container(
              width: 92,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF4A4433),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    );
  }
}

/// Paints the camera cut-out of the selected device on top of the wallpaper.
class _CutoutPainter extends CustomPainter {
  _CutoutPainter(this.style);

  final NotchStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = const Color(0xFF05040A);
    switch (style) {
      case NotchStyle.island:
        final Rect rect = Rect.fromCenter(
          center: Offset(size.width / 2, 20),
          width: size.width * 0.30,
          height: 21,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(99)),
          paint,
        );
        break;
      case NotchStyle.wideNotch:
        final Rect rect = Rect.fromLTWH(
          size.width / 2 - size.width * 0.20,
          -12,
          size.width * 0.40,
          36,
        );
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            rect,
            bottomLeft: const Radius.circular(16),
            bottomRight: const Radius.circular(16),
          ),
          paint,
        );
        break;
      case NotchStyle.teardrop:
        final Rect rect = Rect.fromLTWH(
          size.width / 2 - 15,
          -10,
          30,
          27,
        );
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            rect,
            bottomLeft: const Radius.circular(99),
            bottomRight: const Radius.circular(99),
          ),
          paint,
        );
        break;
      case NotchStyle.dotCenter:
        canvas.drawCircle(Offset(size.width / 2, 17), 6.5, paint);
        break;
      case NotchStyle.dotLeft:
        canvas.drawCircle(const Offset(26, 17), 6.5, paint);
        break;
      case NotchStyle.none:
        break;
    }
  }

  @override
  bool shouldRepaint(_CutoutPainter oldDelegate) => oldDelegate.style != style;
}

class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    const TextStyle style = TextStyle(
      color: Colors.white,
      fontSize: 10,
      fontWeight: FontWeight.w700,
      shadows: <Shadow>[Shadow(color: Color(0xB3000000), blurRadius: 4)],
    );
    return Positioned(
      top: 8,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const <Widget>[
            Text('9:41', style: style),
            Row(
              children: <Widget>[
                Icon(Icons.signal_cellular_alt_rounded,
                    size: 11, color: Colors.white),
                SizedBox(width: 4),
                Icon(Icons.wifi_rounded, size: 11, color: Colors.white),
                SizedBox(width: 4),
                Icon(Icons.battery_5_bar_rounded,
                    size: 12, color: Colors.white),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageFace extends StatelessWidget {
  const _ImageFace({this.frame});

  final PreviewFrame? frame;

  @override
  Widget build(BuildContext context) {
    final PreviewFrame? current = frame;
    if (current == null || current.url.isEmpty) {
      return const Center(
        child: Icon(Icons.image_not_supported_rounded,
            color: Color(0x66FFFFFF), size: 34),
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 1.045, end: 1).animate(animation),
            child: child,
          ),
        );
      },
      child: CachedNetworkImage(
        key: ValueKey<String>(current.url),
        imageUrl: current.url,
        fit: BoxFit.cover,
        placeholder: (BuildContext context, String url) => const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: Zc.gold),
          ),
        ),
        errorWidget: (BuildContext context, String url, Object error) =>
            const Center(
          child: Icon(Icons.broken_image_rounded,
              color: Color(0x66FFFFFF), size: 30),
        ),
      ),
    );
  }
}

class _AudioFace extends StatelessWidget {
  const _AudioFace({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFF2B2618), Color(0xFF171308)],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: <Color>[
                  Zc.gold,
                  Zc.orange,
                  Zc.amber,
                  Zc.gold,
                ],
              ),
            ),
            child: const Icon(Icons.music_note_rounded,
                color: Zc.ink, size: 30),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'RINGTONE PREVIEW',
            style: TextStyle(
              color: Color(0x8CFFFFFF),
              fontSize: 9,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.playing,
    required this.index,
    required this.total,
    required this.speedLabel,
    required this.label,
    required this.onPrev,
    required this.onNext,
    required this.onToggle,
    required this.onSpeed,
  });

  final bool playing;
  final int index;
  final int total;
  final String speedLabel;
  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToggle;
  final VoidCallback onSpeed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: Zc.cream,
            border: Border.all(color: Zc.line, width: 1.5),
            borderRadius: BorderRadius.circular(99),
            boxShadow: kSoftShadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                onPressed: onPrev,
                icon: const Icon(Icons.skip_previous_rounded, size: 18),
                tooltip: 'Previous',
                visualDensity: VisualDensity.compact,
              ),
              GestureDetector(
                onTap: onToggle,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: Zc.goldGradient,
                    boxShadow: playing
                        ? const <BoxShadow>[
                            BoxShadow(
                              color: Color(0x73F5A800),
                              blurRadius: 16,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Zc.ink,
                    size: 20,
                  ),
                ),
              ),
              IconButton(
                onPressed: onNext,
                icon: const Icon(Icons.skip_next_rounded, size: 18),
                tooltip: 'Next',
                visualDensity: VisualDensity.compact,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '${index + 1} / $total',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                    color: Zc.muted,
                  ),
                ),
              ),
              TextButton(
                onPressed: onSpeed,
                style: TextButton.styleFrom(
                  minimumSize: const Size(40, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  foregroundColor: Zc.inkSoft,
                ),
                child: Text(
                  speedLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (label.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10.5,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w800,
              color: Zc.muted,
            ),
          ),
        ],
      ],
    );
  }
}

class _DeviceChooser extends StatelessWidget {
  const _DeviceChooser({required this.active, required this.onSelect});

  final DevicePreset active;
  final ValueChanged<DevicePreset> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: kDevicePresets.length,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: 6),
        itemBuilder: (BuildContext context, int index) {
          final DevicePreset preset = kDevicePresets[index];
          final bool selected = preset.id == active.id;
          return ChoiceChip(
            selected: selected,
            onSelected: (bool _) => onSelect(preset),
            avatar: Icon(
              preset.icon,
              size: 14,
              color: selected ? Zc.ink : Zc.muted,
            ),
            label: Text(preset.label),
            labelStyle: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: selected ? Zc.ink : Zc.muted,
            ),
            selectedColor: Zc.gold,
            backgroundColor: Zc.cream,
            side: BorderSide(color: selected ? Zc.goldDeep : Zc.line),
            showCheckmark: false,
          );
        },
      ),
    );
  }
}
