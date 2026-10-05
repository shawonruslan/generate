import 'dart:math';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Realistic phone mockup preview: shows a generated wallpaper as it
/// would look on a device — plain wallpaper, lock screen, home screen,
/// an in-app (chat) view and an incoming call screen.
enum MockupMode { wallpaper, lock, home, chat, call }

Future<void> showDevicePreview(
  BuildContext context, {
  required String imageUrl,
  required String title,
}) {
  return showDialog(
    context: context,
    builder: (_) => _DevicePreviewDialog(imageUrl: imageUrl, title: title),
  );
}

class _DevicePreviewDialog extends StatefulWidget {
  final String imageUrl;
  final String title;
  const _DevicePreviewDialog({required this.imageUrl, required this.title});

  @override
  State<_DevicePreviewDialog> createState() => _DevicePreviewDialogState();
}

class _DevicePreviewDialogState extends State<_DevicePreviewDialog> {
  MockupMode _mode = MockupMode.lock;
  double _rotX = 0.0;
  double _rotY = 0.0;
  double _zoom = 1.0;

  void _resetView() => setState(() {
        _rotX = 0.0;
        _rotY = 0.0;
        _zoom = 1.0;
      });

  void _bumpZoom(double d) => setState(() {
        _zoom = clampDouble(_zoom + d, 0.6, 2.0);
      });

  static const _labels = {
    MockupMode.wallpaper: 'Wallpaper',
    MockupMode.lock: 'Lock',
    MockupMode.home: 'Home',
    MockupMode.chat: 'App',
    MockupMode.call: 'Call',
  };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // Keep the zoomed phone inside the dialog width (no overflow clipping).
    final fitCap = clampDouble(
        (MediaQuery.of(context).size.width - 64) / 264.0, 0.6, 2.0);
    final effZoom = clampDouble(_zoom, 0.6, fitCap);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.smartphone_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Device preview',
                        style: textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_outlined),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final m in MockupMode.values)
                    ChoiceChip(
                      label: Text(_labels[m]!),
                      selected: _mode == m,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _mode = m),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              // Rotatable (360 deg) + zoomable phone area.
              SizedBox(
                height: 560 * effZoom + 24,
                child: Center(
                  child: Listener(
                    onPointerSignal: (e) {
                      if (e is PointerScrollEvent) {
                        _bumpZoom(e.scrollDelta.dy < 0 ? 0.1 : -0.1);
                      }
                    },
                    child: GestureDetector(
                      onPanUpdate: (d) => setState(() {
                        _rotY += d.delta.dx * 0.012;
                        _rotX += d.delta.dy * 0.012;
                      }),
                      onDoubleTap: _resetView,
                      child: Transform.scale(
                        scale: effZoom,
                        alignment: Alignment.center,
                        child: _PhoneFrame(
                          imageUrl: widget.imageUrl,
                          mode: _mode,
                          rotX: _rotX,
                          rotY: _rotY,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Zoom out',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.zoom_out_outlined),
                    onPressed:
                        _zoom > 0.6 ? () => _bumpZoom(-0.2) : null,
                  ),
                  SizedBox(
                    width: 52,
                    child: Center(
                      child: Text('${(effZoom * 100).round()}%',
                          style: textTheme.bodySmall),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Zoom in',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.zoom_in_outlined),
                    onPressed:
                        _zoom < 2.0 ? () => _bumpZoom(0.2) : null,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Reset view',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.refresh_outlined),
                    onPressed: _resetView,
                  ),
                ],
              ),
              Text(
                  'Drag to rotate 360 deg. Scroll or use the buttons to zoom. Double-tap to reset.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline)),
              const SizedBox(height: 4),
              Text(_labels[_mode]!,
                  style: textTheme.bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.outline)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Phone hardware frame with a subtle 3D tilt, bezel, dynamic island,
/// side buttons and shadow.
class _PhoneFrame extends StatelessWidget {
  final String imageUrl;
  final MockupMode mode;
  final double rotX;
  final double rotY;

  const _PhoneFrame(
      {required this.imageUrl,
      required this.mode,
      this.rotX = 0.0,
      this.rotY = 0.0});

  static const _w = 264.0;
  static const _h = 572.0;

  /// True when the screen side faces the viewer; otherwise the back shows.
  bool get _frontVisible => cos(rotX) * cos(rotY) >= 0;

  @override
  Widget build(BuildContext context) {
    final front = _frontVisible;
    // The back side is rotated pi about Y relative to the front.
    final y = front ? rotY : rotY + pi;
    return Transform(
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0012)
        ..rotateX(rotX)
        ..rotateY(y),
      alignment: Alignment.center,
      child: front ? _frontBody() : _backBody(),
    );
  }

  Widget _frontBody() => Container(
        width: _w,
        height: _h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(46),
          color: const Color(0xFF0b0b0e),
          border: Border.all(color: const Color(0xFF3d3d44), width: 2.5),
          boxShadow: const [
            BoxShadow(
                color: Color(0x66000000),
                blurRadius: 32,
                offset: Offset(0, 18)),
            BoxShadow(
                color: Color(0x22000000),
                blurRadius: 8,
                offset: Offset(0, 4)),
          ],
        ),
        child: Stack(
          children: [
            // side buttons
            Positioned(
                left: -4,
                top: 110,
                child: _sideButton(height: 56)),
            Positioned(
                left: -4,
                top: 176,
                child: _sideButton(height: 88)),
            Positioned(
                right: -4,
                top: 150,
                child: _sideButton(height: 72)),
            // screen
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(9),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(37),
                  child:
                      _MockupScreen(imageUrl: imageUrl, mode: mode),
                ),
              ),
            ),
            // dynamic island
            Positioned(
              top: 20,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 86,
                  height: 25,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  /// Back panel: titanium finish with a triple-lens camera module.
  Widget _backBody() => Container(
        width: _w,
        height: _h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(46),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2a2a31), Color(0xFF17171c)],
          ),
          border: Border.all(color: const Color(0xFF3d3d44), width: 2.5),
          boxShadow: const [
            BoxShadow(
                color: Color(0x66000000),
                blurRadius: 32,
                offset: Offset(0, 18)),
            BoxShadow(
                color: Color(0x22000000),
                blurRadius: 8,
                offset: Offset(0, 4)),
          ],
        ),
        child: Stack(
          children: [
            // camera plateau
            Positioned(
              top: 18,
              left: 18,
              child: Container(
                width: 118,
                height: 118,
                decoration: BoxDecoration(
                  color: const Color(0xFF232329),
                  borderRadius: BorderRadius.circular(28),
                  border:
                      Border.all(color: const Color(0xFF484850), width: 1.5),
                ),
                child: Stack(
                  children: [
                    Positioned(top: 12, left: 12, child: _lens()),
                    Positioned(top: 12, right: 12, child: _lens()),
                    Positioned(bottom: 12, left: 12, child: _lens()),
                    Positioned(
                      bottom: 22,
                      right: 20,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFFF3c4),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // subtle branding dot
            Center(
              child: Opacity(
                opacity: 0.35,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: const Color(0xFF6b6b76), width: 2),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Center(
                    child: Text('MH',
                        style: TextStyle(
                            color: Color(0xFF9a9aa5),
                            fontWeight: FontWeight.w800,
                            fontSize: 13)),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _lens() => Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF0d1526),
          border: Border.all(color: const Color(0xFF5a5a66), width: 3),
        ),
        child: Center(
          child: Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF2b4a7a),
            ),
          ),
        ),
      );

  Widget _sideButton({required double height}) => Container(
        width: 4,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFF3d3d44),
          borderRadius: BorderRadius.circular(2),
        ),
      );
}

class _MockupScreen extends StatelessWidget {
  final String imageUrl;
  final MockupMode mode;

  const _MockupScreen({required this.imageUrl, required this.mode});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                Container(color: Colors.black87)),
        switch (mode) {
          MockupMode.wallpaper => const SizedBox.shrink(),
          MockupMode.lock => const _LockOverlay(),
          MockupMode.home => const _HomeOverlay(),
          MockupMode.chat => const _ChatOverlay(),
          MockupMode.call => _CallOverlay(imageUrl: imageUrl),
        },
      ],
    );
  }
}

/// White text with a soft shadow so it stays legible on any wallpaper.
class _ShadedText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const _ShadedText(this.text, {this.style});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: (style ?? const TextStyle()).copyWith(
        color: Colors.white,
        shadows: const [
          Shadow(color: Colors.black54, blurRadius: 8),
          Shadow(color: Colors.black38, blurRadius: 2),
        ],
      ),
    );
  }
}

String _clockNow() {
  final n = DateTime.now();
  final h = n.hour % 12 == 0 ? 12 : n.hour % 12;
  return '$h:${n.minute.toString().padLeft(2, '0')}';
}

String _dateNow() {
  const days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday'
  ];
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December'
  ];
  final n = DateTime.now();
  return '${days[n.weekday - 1]}, ${months[n.month - 1]} ${n.day}';
}

/// Dark gradient at top/bottom for overlay legibility.
Widget _scrim({bool top = true, bool bottom = true}) => Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              if (top) Colors.black.withOpacity(0.45) else Colors.transparent,
              Colors.transparent,
              Colors.transparent,
              if (bottom)
                Colors.black.withOpacity(0.5)
              else
                Colors.transparent,
            ],
            stops: const [0.0, 0.28, 0.62, 1.0],
          ),
        ),
      ),
    );

class _LockOverlay extends StatelessWidget {
  const _LockOverlay();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _scrim(),
        Column(
          children: [
            const SizedBox(height: 44),
            const Icon(Icons.lock_outline,
                color: Colors.white, size: 18),
            const SizedBox(height: 6),
            _ShadedText(_clockNow(),
                style: const TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.w200,
                    height: 1.0)),
            const SizedBox(height: 4),
            _ShadedText(_dateNow(),
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w500)),
            const SizedBox(height: 18),
            _notification(
                Icons.message_outlined, 'Messages', 'Maya', 'See you at 7!', '9:12'),
            const SizedBox(height: 8),
            _notification(Icons.mail_outline, 'Mail', 'Zedge',
                'Your upload was approved', '8:47'),
            const Spacer(),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _roundButton(Icons.flashlight_on_outlined),
                  _roundButton(Icons.photo_camera_outlined),
                ],
              ),
            ),
            Center(
              child: Container(
                width: 120,
                height: 4.5,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _notification(IconData icon, String app, String title, String body,
      String time) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.22),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 20, color: Colors.black87),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(app,
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ),
                    Text(time,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11)),
                  ],
                ),
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                Text(body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundButton(IconData icon) => Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.35),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      );
}

class _HomeOverlay extends StatelessWidget {
  const _HomeOverlay();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _scrim(top: true, bottom: false),
        Column(
          children: [
            const SizedBox(height: 40),
            const _StatusBar(),
            const SizedBox(height: 14),
            Expanded(
              child: GridView.count(
                crossAxisCount: 4,
                physics: const NeverScrollableScrollPhysics(),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14),
                mainAxisSpacing: 14,
                crossAxisSpacing: 6,
                children: const [
                  _AppIcon(Icons.phone, Color(0xFF34c759), 'Phone'),
                  _AppIcon(Icons.message, Color(0xFF30b455), 'Messages'),
                  _AppIcon(Icons.public, Color(0xFF0a84ff), 'Browser'),
                  _AppIcon(Icons.photo_camera, Color(0xFF8e8e93), 'Camera'),
                  _AppIcon(Icons.photo_library, Color(0xFFff9f0a), 'Photos'),
                  _AppIcon(Icons.map, Color(0xFF30b455), 'Maps'),
                  _AppIcon(Icons.music_note, Color(0xFFff375f), 'Music'),
                  _AppIcon(Icons.access_time, Color(0xFF1c1c1e), 'Clock'),
                  _AppIcon(Icons.note_alt, Color(0xFFffd60a), 'Notes'),
                  _AppIcon(Icons.calendar_month, Color(0xFFff453a), 'Calendar'),
                  _AppIcon(Icons.mail, Color(0xFF0a84ff), 'Mail'),
                  _AppIcon(Icons.settings, Color(0xFF8e8e93), 'Settings'),
                  _AppIcon(Icons.play_arrow, Color(0xFF0a84ff), 'Videos'),
                  _AppIcon(Icons.shopping_bag, Color(0xFFbf5af2), 'Store'),
                  _AppIcon(Icons.account_balance_wallet, Color(0xFF30d158), 'Wallet'),
                  _AppIcon(Icons.health_and_safety, Color(0xFFff6482), 'Health'),
                ],
              ),
            ),
            // dock
            Container(
              margin:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.25),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _AppIcon(Icons.phone, Color(0xFF34c759), '', small: true),
                  _AppIcon(Icons.public, Color(0xFF0a84ff), '', small: true),
                  _AppIcon(Icons.message, Color(0xFF30b455), '', small: true),
                  _AppIcon(Icons.music_note, Color(0xFFff375f), '', small: true),
                ],
              ),
            ),
            Container(
              width: 120,
              height: 4.5,
              margin: const EdgeInsets.only(bottom: 8, top: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        children: [
          _ShadedText(_clockNow(),
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
          const Spacer(),
          const Icon(Icons.signal_cellular_alt,
              color: Colors.white, size: 14),
          const SizedBox(width: 4),
          const Icon(Icons.wifi, color: Colors.white, size: 14),
          const SizedBox(width: 4),
          const Icon(Icons.battery_full,
              color: Colors.white, size: 16),
        ],
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final bool small;

  const _AppIcon(this.icon, this.color, this.label, {this.small = false});

  @override
  Widget build(BuildContext context) {
    final size = small ? 46.0 : 52.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color, color.withOpacity(0.75)],
            ),
            borderRadius: BorderRadius.circular(size * 0.28),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: Offset(0, 2)),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: size * 0.52),
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(height: 3),
          _ShadedText(label,
              style: const TextStyle(fontSize: 10)),
        ],
      ],
    );
  }
}

/// In-app view: a chat app with the wallpaper as the chat background.
class _ChatOverlay extends StatelessWidget {
  const _ChatOverlay();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // dim the wallpaper slightly so bubbles read well
        Positioned.fill(
            child: Container(color: Colors.black.withOpacity(0.25))),
        Column(
          children: [
            Container(
              padding: const EdgeInsets.only(
                  top: 44, left: 8, right: 8, bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1c1c1e).withOpacity(0.92),
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.arrow_back,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 6),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [
                        Color(0xFFbf5af2),
                        Color(0xFF0a84ff)
                      ]),
                    ),
                    child: const Center(
                        child: Text('M',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700))),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Maya',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                        Text('online',
                            style: TextStyle(
                                color: Colors.white60, fontSize: 11)),
                      ],
                    ),
                  ),
                  const Icon(Icons.videocam_outlined,
                      color: Colors.white70, size: 20),
                  const SizedBox(width: 12),
                  const Icon(Icons.call_outlined,
                      color: Colors.white70, size: 20),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: const [
                  _Bubble('That wallpaper is unreal', false),
                  _Bubble('Right? Made it this morning', true),
                  _Bubble('Send me the night version too', false),
                  _Bubble('Done — check your lock screen', true),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.all(10),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF2c2c2e).withOpacity(0.95),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Row(
                children: [
                  Expanded(
                    child: Text('Message',
                        style: TextStyle(
                            color: Colors.white38, fontSize: 14)),
                  ),
                  Icon(Icons.send_outlined,
                      color: Colors.white70, size: 20),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  final String text;
  final bool mine;
  const _Bubble(this.text, this.mine);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 180),
        decoration: BoxDecoration(
          color: mine
              ? const Color(0xFF0a84ff).withOpacity(0.92)
              : const Color(0xFF2c2c2e).withOpacity(0.92),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: Text(text,
            style: const TextStyle(color: Colors.white, fontSize: 13)),
      ),
    );
  }
}

/// Incoming call screen over a blurred wallpaper.
class _CallOverlay extends StatelessWidget {
  final String imageUrl;
  const _CallOverlay({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Image.network(
            imageUrl,
            fit: BoxFit.cover,
          ),
        ),
        Container(color: Colors.black.withOpacity(0.45)),
        Column(
          children: [
            const SizedBox(height: 64),
            const Text('Incoming call',
                style: TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 16),
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [
                  Color(0xFFbf5af2),
                  Color(0xFF0a84ff)
                ]),
                border: Border.all(
                    color: Colors.white.withOpacity(0.6), width: 2),
              ),
              child: const Center(
                  child: Text('M',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.w700))),
            ),
            const SizedBox(height: 12),
            const Text('Maya Chen',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w600)),
            const Text('mobile',
                style: TextStyle(color: Colors.white70, fontSize: 14)),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 40, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    children: [
                      _callButton(Icons.message_outlined,
                          Colors.white.withOpacity(0.25)),
                      const SizedBox(height: 6),
                      const Text('Message',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                  Column(
                    children: [
                      _callButton(Icons.alarm_outlined,
                          Colors.white.withOpacity(0.25)),
                      const SizedBox(height: 6),
                      const Text('Remind',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 44, vertical: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _callButton(Icons.call_end, const Color(0xFFff453a),
                      big: true),
                  _callButton(Icons.call, const Color(0xFF30d158),
                      big: true),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ],
    );
  }

  Widget _callButton(IconData icon, Color bg, {bool big = false}) {
    final s = big ? 62.0 : 46.0;
    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white, size: s * 0.48),
    );
  }
}
