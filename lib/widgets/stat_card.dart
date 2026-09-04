import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Dashboard metric tile with the same depth treatment as the web day cards.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.hint,
    this.accent = Zc.goldDeep,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? hint;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Zc.panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFEBE2CB), width: 1.5),
          boxShadow: kSoftShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 19, color: accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    maxLines: 2,
                    style: const TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w800,
                      color: Zc.muted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              value,
              style: const TextStyle(
                fontSize: 27,
                height: 1.05,
                fontWeight: FontWeight.w900,
                color: Zc.ink,
              ),
            ),
            if (hint != null) ...<Widget>[
              const SizedBox(height: 5),
              Text(
                hint!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Zc.muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Small pill used for statuses and content types.
class TagPill extends StatelessWidget {
  const TagPill({
    super.key,
    required this.text,
    required this.color,
    this.icon,
    this.filled = false,
  });

  final String text;
  final Color color;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color : color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withOpacity(filled ? 1.0 : 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 11, color: filled ? Zc.ink : color),
            const SizedBox(width: 4),
          ],
          Text(
            text.toUpperCase(),
            style: TextStyle(
              fontSize: 9.5,
              letterSpacing: 0.7,
              fontWeight: FontWeight.w900,
              color: filled ? Zc.ink : color,
            ),
          ),
        ],
      ),
    );
  }
}
