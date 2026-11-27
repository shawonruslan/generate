import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// Small helper: show a toast — web-style black pill, icon, white 13px text.
void showMsg(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            error ? Icons.error_outline : Icons.check_circle,
            color: error ? const Color(0xFFE5484D) : const Color(0xFF46A758),
            size: 18,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(msg,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
      backgroundColor: Colors.black,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      margin: const EdgeInsets.only(left: 24, right: 24, bottom: 26),
    ),
  );
}

/// Run [fn], showing [ApiException] messages as snackbars. Returns null on error.
Future<T?> guard<T>(BuildContext context, Future<T> Function() fn) async {
  try {
    return await fn();
  } on UnauthorizedException {
    showMsg(context, 'Session expired — please log in again.', error: true);
    return null;
  } on ApiException catch (e) {
    showMsg(context, e.message, error: true);
    return null;
  } catch (e) {
    showMsg(context, 'Something went wrong: $e', error: true);
    return null;
  }
}

/// Yes/No confirmation dialog.
Future<bool> confirmDialog(BuildContext context,
    {required String title, required String message, String okLabel = 'Delete'}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.pop(c, true),
          style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(c).colorScheme.error),
          child: Text(okLabel),
        ),
      ],
    ),
  );
  return res ?? false;
}

/// Simple text-input dialog.
Future<String?> promptDialog(BuildContext context,
    {required String title,
    String? initial,
    String? hint,
    String okLabel = 'Save',
    bool obscure = false,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1}) async {
  final ctrl = TextEditingController(text: initial ?? '');
  final res = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        obscureText: obscure,
        keyboardType: keyboardType,
        maxLines: maxLines,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (_) => Navigator.pop(c, ctrl.text),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        ElevatedButton(
            onPressed: () => Navigator.pop(c, ctrl.text), child: Text(okLabel)),
      ],
    ),
  );
  return res;
}

/// Circular storage-usage ring with % in the center (matches the web widget).
class StorageRing extends StatelessWidget {
  final double fraction; // 0..1
  final double size;
  final double stroke;
  const StorageRing(
      {super.key, required this.fraction, this.size = 56, this.stroke = 7});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final night = theme.brightness == Brightness.dark;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(
              fraction: fraction.clamp(0, 1),
              track: night ? const Color(0xFF2D2D2D) : const Color(0xFFE3E0D6),
              fill: theme.colorScheme.primary,
              stroke: stroke,
            ),
          ),
          Text(
            '${(fraction.clamp(0, 1) * 100).toStringAsFixed(fraction < 0.1 ? 1 : 0)}%',
            style: TextStyle(
                fontSize: size * 0.22, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double fraction;
  final Color track;
  final Color fill;
  final double stroke;
  _RingPainter(
      {required this.fraction,
      required this.track,
      required this.fill,
      required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);
    if (fraction > 0) {
      final fillPaint = Paint()
        ..color = fill
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -3.14159 / 2,
          2 * 3.14159 * fraction, false, fillPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.fraction != fraction || old.track != track || old.fill != fill;
}

/// Sidebar storage card: ring + "STORAGE" label + used/limit + files/pools.
class StorageCard extends StatelessWidget {
  final DriveStats stats;
  final VoidCallback? onTap;
  const StorageCard({super.key, required this.stats, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final night = theme.brightness == Brightness.dark;
    final limit = stats.limit > 0 ? stats.limit : 1;
    final frac = stats.used / limit;
    final limitLabel = stats.quota >= 0 && stats.quota != stats.limit
        ? formatBytes(stats.quota)
        : formatBytes(stats.limit);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              StorageRing(fraction: frac),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.storage_outlined,
                            size: 13,
                            color: night
                                ? AppColors.nightMuted
                                : AppColors.dayMuted),
                        const SizedBox(width: 4),
                        Text('STORAGE',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.8,
                                color: night
                                    ? AppColors.nightMuted
                                    : AppColors.dayMuted)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('${formatBytes(stats.used)} / $limitLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                        '${stats.count} files${stats.pools != null ? ' · ${stats.pools} R2' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            color: night
                                ? AppColors.nightMuted
                                : AppColors.dayMuted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Avatar with initial-letter fallback.
class AvatarWidget extends StatelessWidget {
  final String? url;
  final String name;
  final double radius;
  final UserBadge? badge;
  final bool showBadgeTag;
  const AvatarWidget({
    super.key,
    this.url,
    required this.name,
    this.radius = 18,
    this.badge,
    this.showBadgeTag = true,
  });

  Widget _core(BuildContext context) {
    final theme = Theme.of(context);
    final initial = name.isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    Widget fallback() => CircleAvatar(
          radius: radius,
          backgroundColor: theme.colorScheme.primary.withOpacity(0.15),
          child: Text(initial,
              style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: radius * 0.85)),
        );
    if (url != null && url!.isNotEmpty) {
      return SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: ClipOval(
          child: Image.network(
            url!,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => fallback(),
          ),
        ),
      );
    }
    return fallback();
  }

  @override
  Widget build(BuildContext context) {
    final b = badge;
    if (b == null || b.tier.isEmpty) return _core(context);
    return _FramedAvatarWidget(
      radius: radius,
      badge: b,
      showTag: showBadgeTag && radius >= 15 && b.title.isNotEmpty,
      child: _core(context),
    );
  }
}

class _FramedAvatarWidget extends StatefulWidget {
  final double radius;
  final UserBadge badge;
  final bool showTag;
  final Widget child;
  const _FramedAvatarWidget({
    required this.radius,
    required this.badge,
    required this.showTag,
    required this.child,
  });

  @override
  State<_FramedAvatarWidget> createState() => _FramedAvatarWidgetState();
}

class _FramedAvatarWidgetState extends State<_FramedAvatarWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(
          milliseconds: widget.badge.tier == 'legendary' ? 3000 : 3800),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  static ({
    List<Color> ringColors,
    List<Color> tagColors,
    Color textColor,
    Color glowColor,
    String tierName,
  }) _tierStyle(String tier) {
    switch (tier) {
      case 'legendary':
        return (
          ringColors: const [
            Color(0xFFF59E0B),
            Color(0xFFEC4899),
            Color(0xFF7C3AED),
            Color(0xFFFDE047),
            Color(0xFFF59E0B),
          ],
          tagColors: const [
            Color(0xFFB45309),
            Color(0xFFF59E0B),
            Color(0xFFEC4899),
            Color(0xFF7C3AED),
          ],
          textColor: Colors.white,
          glowColor: const Color(0xFFF59E0B),
          tierName: 'Legendary',
        );
      case 'diamond':
        return (
          ringColors: const [
            Color(0xFF0284C7),
            Color(0xFF22D3EE),
            Color(0xFFE0F2FE),
            Color(0xFF38BDF8),
            Color(0xFF0284C7),
          ],
          tagColors: const [
            Color(0xFF0284C7),
            Color(0xFF06B6D4),
            Color(0xFF67E8F9),
          ],
          textColor: const Color(0xFF042F2E),
          glowColor: const Color(0xFF22D3EE),
          tierName: 'Diamond',
        );
      case 'platinum':
        return (
          ringColors: const [
            Color(0xFF059669),
            Color(0xFF34D399),
            Color(0xFF8B5CF6),
            Color(0xFFC084FC),
            Color(0xFF059669),
          ],
          tagColors: const [
            Color(0xFF059669),
            Color(0xFF10B981),
            Color(0xFF8B5CF6),
            Color(0xFF7C3AED),
          ],
          textColor: Colors.white,
          glowColor: const Color(0xFF8B5CF6),
          tierName: 'Platinum',
        );
      case 'golden':
        return (
          ringColors: const [
            Color(0xFFB45309),
            Color(0xFFF59E0B),
            Color(0xFFFEF08A),
            Color(0xFFD97706),
            Color(0xFFB45309),
          ],
          tagColors: const [
            Color(0xFFB45309),
            Color(0xFFF59E0B),
            Color(0xFFFDE68A),
          ],
          textColor: const Color(0xFF451A03),
          glowColor: const Color(0xFFF59E0B),
          tierName: 'Golden',
        );
      case 'silver':
        return (
          ringColors: const [
            Color(0xFF475569),
            Color(0xFFCBD5E1),
            Color(0xFFF1F5F9),
            Color(0xFF64748B),
            Color(0xFF475569),
          ],
          tagColors: const [
            Color(0xFF64748B),
            Color(0xFFCBD5E1),
            Color(0xFFE2E8F0),
          ],
          textColor: const Color(0xFF0F172A),
          glowColor: const Color(0xFF94A3B8),
          tierName: 'Silver',
        );
      default: // bronze
        return (
          ringColors: const [
            Color(0xFF7C2D12),
            Color(0xFFEA580C),
            Color(0xFFFDBA74),
            Color(0xFF9A3412),
            Color(0xFF7C2D12),
          ],
          tagColors: const [
            Color(0xFF7C2D12),
            Color(0xFFC2410C),
            Color(0xFFFDBA74),
          ],
          textColor: const Color(0xFFFFF7ED),
          glowColor: const Color(0xFFEA580C),
          tierName: 'Bronze',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = _tierStyle(widget.badge.tier);
    final isLegend = widget.badge.tier == 'legendary';
    final ringW = widget.radius >= 20 ? 3.0 : 2.2;
    final sepW = widget.radius >= 20 ? 2.0 : 1.5;
    final cardBg = Theme.of(context).cardColor;
    final outerSize = (widget.radius + ringW + sepW) * 2;
    final tagFont = widget.radius >= 30
        ? 9.5
        : (widget.radius >= 20 ? 8.0 : 7.0);

    return Tooltip(
      message: '${st.tierName} · ${widget.badge.title}',
      child: Padding(
        padding: EdgeInsets.only(bottom: widget.showTag ? 6 : 0),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, child) => Container(
                width: outerSize,
                height: outerSize,
                padding: EdgeInsets.all(ringW),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    colors: st.ringColors,
                    transform: GradientRotation(_ctrl.value * 2 * math.pi),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: st.glowColor.withOpacity(isLegend ? 0.52 : 0.38),
                      blurRadius: isLegend ? 11 : 7,
                      spreadRadius: isLegend ? 0.8 : 0.2,
                    ),
                  ],
                ),
                child: child,
              ),
              child: Container(
                padding: EdgeInsets.all(sepW),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cardBg,
                ),
                child: widget.child,
              ),
            ),
            if (widget.showTag)
              Positioned(
                bottom: -6,
                child: Container(
                  constraints:
                      BoxConstraints(maxWidth: math.max(outerSize + 24, 62)),
                  padding: EdgeInsets.symmetric(
                      horizontal: widget.radius >= 28 ? 8 : 5.5,
                      vertical: widget.radius >= 28 ? 2 : 1.2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: LinearGradient(colors: st.tagColors),
                    border: Border.all(color: cardBg, width: 1.4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.35),
                        blurRadius: 4,
                        offset: const Offset(0, 1.5),
                      ),
                    ],
                  ),
                  child: Text(
                    widget.badge.title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: tagFont,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: st.textColor,
                      height: 1.15,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// File-type icon chip.
class FileTypeIcon extends StatelessWidget {
  final String name;
  final String mime;
  final double size;
  const FileTypeIcon(
      {super.key, required this.name, required this.mime, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final night = theme.brightness == Brightness.dark;
    IconData icon;
    Color color;
    if (isImageMime(mime)) {
      icon = Icons.image_outlined;
      color = const Color(0xFF46A758);
    } else if (isVideoMime(mime)) {
      icon = Icons.movie_outlined;
      color = const Color(0xFF5B7CFA);
    } else if (isAudioMime(mime)) {
      icon = Icons.audio_file_outlined;
      color = const Color(0xFFB45309);
    } else if (isPdfMime(mime)) {
      icon = Icons.picture_as_pdf_outlined;
      color = const Color(0xFFE5484D);
    } else if (mime.contains('zip') ||
        mime.contains('rar') ||
        mime.contains('tar') ||
        name.endsWith('.apk') ||
        name.endsWith('.exe')) {
      icon = Icons.archive_outlined;
      color = const Color(0xFFB45309);
    } else if (mime.contains('text') || name.endsWith('.md')) {
      icon = Icons.description_outlined;
      color = night ? AppColors.nightMuted : AppColors.dayMuted;
    } else {
      icon = Icons.insert_drive_file_outlined;
      color = night ? AppColors.nightMuted : AppColors.dayMuted;
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: size * 0.55),
    );
  }
}

class LoadingView extends StatelessWidget {
  final String label;
  const LoadingView({super.key, this.label = 'Loading…'});
  @override
  Widget build(BuildContext context) =>
      Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 12),
        Text(label),
      ]));
}

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorView({super.key, required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, size: 40),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(message, textAlign: TextAlign.center),
        ),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
      ]));
}

class EmptyView extends StatelessWidget {
  final IconData icon;
  final String message;
  const EmptyView({super.key, required this.icon, required this.message});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final night = theme.brightness == Brightness.dark;
    return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon,
          size: 48, color: night ? AppColors.nightMuted : AppColors.dayMuted),
      const SizedBox(height: 12),
      Text(message,
          style: TextStyle(
              color: night ? AppColors.nightMuted : AppColors.dayMuted)),
    ]));
  }
}

/// Upload/download progress dialog driven by a [ProgressCallback]-style stream.
class ProgressDialog extends StatefulWidget {
  final String title;
  final Future<void> Function(void Function(int sent, int total)) task;
  const ProgressDialog({super.key, required this.title, required this.task});

  static Future<bool> show(BuildContext context,
      {required String title,
      required Future<void> Function(void Function(int, int)) task}) async {
    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => ProgressDialog(title: title, task: task),
    );
    return res ?? false;
  }

  @override
  State<ProgressDialog> createState() => _ProgressDialogState();
}

class _ProgressDialogState extends State<ProgressDialog> {
  double _frac = 0;
  String _label = 'Starting…';
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      await widget.task((sent, total) {
        if (!mounted) return;
        setState(() {
          _frac = total > 0 ? (sent / total).clamp(0, 1) : 0;
          _label = '${formatBytes(sent)} / ${formatBytes(total)}';
        });
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        child: _error != null
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 36),
                const SizedBox(height: 8),
                Text(_error!, textAlign: TextAlign.center),
              ])
            : Column(mainAxisSize: MainAxisSize.min, children: [
                LinearProgressIndicator(value: _frac),
                const SizedBox(height: 12),
                Text(_label),
                const SizedBox(height: 4),
                Text('${(_frac * 100).toStringAsFixed(1)}%'),
              ]),
      ),
      actions: [
        if (_error != null)
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Close')),
      ],
    );
  }
}


/// Resolves a user's badge (admin always receives the Legendary badge).
UserBadge? resolveBadge(String username, Map<String, UserBadge>? badges) {
  if (username == 'admin') {
    return badges?['admin'] ?? const UserBadge(tier: 'legendary', title: 'ADMIN');
  }
  return badges?[username];
}

const List<String> memberBadgeTiers = [
  'diamond',
  'platinum',
  'golden',
  'silver',
  'bronze',
];

/// Eye-catching animated job-position badge with metallic/holographic sheen
/// across 6 tiers: legendary (admin), diamond, platinum, golden, silver, bronze.
class AnimatedRoleBadge extends StatefulWidget {
  final UserBadge badge;
  final bool compact;
  const AnimatedRoleBadge({super.key, required this.badge, this.compact = false});

  @override
  State<AnimatedRoleBadge> createState() => _AnimatedRoleBadgeState();
}

class _AnimatedRoleBadgeState extends State<AnimatedRoleBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(
          milliseconds: widget.badge.tier == 'legendary' ? 2800 : 3400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  static ({
    List<Color> colors,
    Color textColor,
    Color borderColor,
    Color glowColor,
    IconData icon,
    String tierName,
  }) _styleFor(String tier) {
    switch (tier) {
      case 'legendary':
        return (
          colors: const [
            Color(0xFFB45309),
            Color(0xFFF59E0B),
            Color(0xFFEC4899),
            Color(0xFF7C3AED),
            Color(0xFFF59E0B),
          ],
          textColor: Colors.white,
          borderColor: const Color(0xFFFDE047),
          glowColor: const Color(0xFFF59E0B),
          icon: Icons.workspace_premium,
          tierName: 'Legendary',
        );
      case 'diamond':
        return (
          colors: const [
            Color(0xFF0284C7),
            Color(0xFF06B6D4),
            Color(0xFF67E8F9),
            Color(0xFF38BDF8),
          ],
          textColor: const Color(0xFF042F2E),
          borderColor: const Color(0xFFA5F3FC),
          glowColor: const Color(0xFF22D3EE),
          icon: Icons.diamond_outlined,
          tierName: 'Diamond',
        );
      case 'platinum':
        return (
          colors: const [
            Color(0xFF059669),
            Color(0xFF10B981),
            Color(0xFF8B5CF6),
            Color(0xFFA855F7),
          ],
          textColor: Colors.white,
          borderColor: const Color(0xFFC4B5FD),
          glowColor: const Color(0xFF8B5CF6),
          icon: Icons.verified_outlined,
          tierName: 'Platinum',
        );
      case 'golden':
        return (
          colors: const [
            Color(0xFFB45309),
            Color(0xFFF59E0B),
            Color(0xFFFDE68A),
            Color(0xFFD97706),
          ],
          textColor: const Color(0xFF451A03),
          borderColor: const Color(0xFFFDE68A),
          glowColor: const Color(0xFFF59E0B),
          icon: Icons.military_tech_outlined,
          tierName: 'Golden',
        );
      case 'silver':
        return (
          colors: const [
            Color(0xFF64748B),
            Color(0xFFCBD5E1),
            Color(0xFFE2E8F0),
            Color(0xFF94A3B8),
          ],
          textColor: const Color(0xFF0F172A),
          borderColor: const Color(0xFFCBD5E1),
          glowColor: const Color(0xFF94A3B8),
          icon: Icons.star_outline,
          tierName: 'Silver',
        );
      default: // bronze
        return (
          colors: const [
            Color(0xFF7C2D12),
            Color(0xFFC2410C),
            Color(0xFFFDBA74),
            Color(0xFF9A3412),
          ],
          textColor: const Color(0xFFFFF7ED),
          borderColor: const Color(0xFFFDBA74),
          glowColor: const Color(0xFFEA580C),
          icon: Icons.workspace_premium_outlined,
          tierName: 'Bronze',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = _styleFor(widget.badge.tier);
    final c = widget.compact;
    final isLegend = widget.badge.tier == 'legendary';
    return Tooltip(
      message: '${st.tierName} · ${widget.badge.title}',
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) {
          final t = _ctrl.value;
          final shift = -1.5 + t * 3.0;
          return Container(
            padding: EdgeInsets.symmetric(
                horizontal: c ? 6.5 : 8.5, vertical: c ? 1.5 : 2.5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: LinearGradient(
                begin: Alignment(shift - 1.0, -0.6),
                end: Alignment(shift + 1.0, 0.6),
                colors: st.colors,
              ),
              border: Border.all(
                  color: st.borderColor.withOpacity(0.85), width: 0.9),
              boxShadow: [
                BoxShadow(
                  color: st.glowColor.withOpacity(isLegend ? 0.45 : 0.28),
                  blurRadius: isLegend ? 10 : 6,
                  spreadRadius: isLegend ? 0.5 : 0,
                ),
              ],
            ),
            child: child,
          );
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(st.icon, size: c ? 10.5 : 12, color: st.textColor),
            SizedBox(width: c ? 3 : 4),
            Text(
              widget.badge.title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: c ? 8.8 : 9.8,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.45,
                color: st.textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
