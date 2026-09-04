import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/queue_item.dart';
import '../theme/app_theme.dart';

/// White rounded panel with the soft gold shadow used everywhere.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 20,
    this.color = Zc.panel,
    this.borderColor = Zc.line,
    this.gradient,
    this.shadow = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color color;
  final Color borderColor;
  final Gradient? gradient;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? color : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: shadow ? kSoftShadow : null,
      ),
      child: child,
    );
  }
}

/// Section header: icon square + title + optional subtitle + trailing actions.
class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.gradient = Zc.goldGradient,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(13),
            boxShadow: kSoftShadow,
          ),
          child: Icon(icon, color: Zc.ink, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: Zc.ink,
                  height: 1.1,
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Zc.muted,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Pill-shaped gradient button (primary CTA of the dashboard).
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.gradient = Zc.goldGradient,
    this.foreground = Zc.ink,
    this.dense = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Gradient gradient;
  final Color foreground;
  final bool dense;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null && !busy;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(99),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: dense ? 14 : 20,
              vertical: dense ? 9 : 13,
            ),
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(99),
              boxShadow: enabled ? kSoftShadow : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (busy)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: foreground,
                    ),
                  )
                else if (icon != null)
                  Icon(icon, size: dense ? 15 : 17, color: foreground),
                if (busy || icon != null) const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: dense ? 12 : 13.5,
                    color: foreground,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small stat legend card (calendar legend / queue pills).
class LegendCard extends StatelessWidget {
  const LegendCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.accent = Zc.goldDeep,
    this.hint,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color accent;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 118),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Zc.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Zc.line, width: 1.5),
        boxShadow: kSoftShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 13, color: accent),
                const SizedBox(width: 5),
              ],
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 9.5,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800,
                  color: Zc.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: accent == Zc.goldDeep ? Zc.ink : accent,
            ),
          ),
          if (hint != null)
            Text(
              hint!,
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: Zc.muted,
              ),
            ),
        ],
      ),
    );
  }
}

/// Thumbnail of a queue row: image, video cover with play badge, or audio disc.
class ItemThumb extends StatelessWidget {
  const ItemThumb({
    super.key,
    required this.item,
    this.radius = 12,
    this.fit = BoxFit.cover,
  });

  final QueueItem item;
  final double radius;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final String url = item.previewUrl;
    Widget body;
    if (item.isAudio || url.isEmpty) {
      body = Container(
        decoration: const BoxDecoration(gradient: Zc.darkGradient),
        child: Center(
          child: Icon(
            item.isAudio
                ? Icons.graphic_eq_rounded
                : (item.isVideo
                    ? Icons.movie_rounded
                    : Icons.image_not_supported_rounded),
            color: Zc.gold,
            size: 30,
          ),
        ),
      );
    } else {
      body = CachedNetworkImage(
        imageUrl: url,
        fit: fit,
        placeholder: (BuildContext c, String u) => Container(
          color: Zc.creamDeep,
          child: const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        errorWidget: (BuildContext c, String u, Object e) => Container(
          color: Zc.creamDeep,
          child: const Icon(Icons.broken_image_rounded, color: Zc.muted),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          body,
          if (item.isVideo)
            const Center(
              child: Icon(Icons.play_circle_fill_rounded,
                  color: Colors.white, size: 34),
            ),
          if (item.isSet)
            Positioned(
              right: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Zc.ink.withOpacity(0.72),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '${item.filledSlots.length}/${item.slots.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: Zc.secondaryGradient,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: Zc.ink, size: 30),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: Zc.ink,
              ),
            ),
            if (message != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Zc.muted,
                ),
              ),
            ],
            if (action != null) ...<Widget>[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Yes/no confirmation dialog styled like the dashboard.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool danger = false,
}) async {
  final bool? result = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
      content: Text(message,
          style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4)),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        GradientButton(
          label: confirmLabel,
          dense: true,
          gradient: danger ? Zc.dangerGradient : Zc.goldGradient,
          foreground: danger ? Colors.white : Zc.ink,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
      ],
    ),
  );
  return result ?? false;
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: error ? Zc.danger : Zc.ink,
        content: Text(message),
      ),
    );
}

/// Responsive column count for card grids.
int gridColumns(double width, {double minTile = 220}) {
  final int cols = (width / minTile).floor();
  return cols < 1 ? 1 : cols;
}

/// Small helper: `label: value` line in muted style.
class MetaLine extends StatelessWidget {
  const MetaLine(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 86,
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 9.5,
                letterSpacing: 1,
                fontWeight: FontWeight.w800,
                color: Zc.muted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Zc.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
