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
  const AvatarWidget(
      {super.key, this.url, required this.name, this.radius = 18});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (url != null && url!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(url!),
        onBackgroundImageError: (_, __) {},
        child: null,
      );
    }
    final initial =
        name.isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: radius,
      backgroundColor: theme.colorScheme.primary.withOpacity(0.15),
      child: Text(initial,
          style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
              fontSize: radius * 0.85)),
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
