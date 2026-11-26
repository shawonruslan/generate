import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../compare/originality.dart';

/// Professional similarity-target control for Image to Prompt: slider +
/// presets + a live "stays / changes" plan, so the user sees exactly what
/// Gemini will be told.
class SimilarityTargetPanel extends StatefulWidget {
  const SimilarityTargetPanel({
    super.key,
    required this.target,
    required this.onChanged,
    required this.antiRepeat,
    required this.onAntiRepeat,
  });
  final int target;
  final ValueChanged<int> onChanged;
  final bool antiRepeat;
  final ValueChanged<bool> onAntiRepeat;

  @override
  State<SimilarityTargetPanel> createState() => _SimilarityTargetPanelState();
}

class _SimilarityTargetPanelState extends State<SimilarityTargetPanel> {
  late int _t = widget.target;

  @override
  void didUpdateWidget(SimilarityTargetPanel old) {
    super.didUpdateWidget(old);
    if (old.target != widget.target) _t = widget.target;
  }

  static Color colorFor(int t) => t >= 80
      ? const Color(0xFFEF4444)
      : t >= 65
          ? AppTheme.warning
          : t >= 45
              ? const Color(0xFF14B8A6)
              : AppTheme.success;

  void _set(int v, {bool save = false}) {
    setState(() => _t = v);
    if (save) widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final plan = planFor(_t);
    final c = colorFor(_t);
    final muted = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Similarity target',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('How close the new image stays to the reference',
                        style: muted),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$_t%',
                      style: TextStyle(
                          fontSize: 28,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          color: c)),
                  Text(plan.band,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: c)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: c,
              thumbColor: c,
              inactiveTrackColor: cs.surfaceContainerHighest,
              trackHeight: 6,
              overlayColor: c.withValues(alpha: 0.15),
            ),
            child: Slider(
              min: minSimilarityTarget.toDouble(),
              max: maxSimilarityTarget.toDouble(),
              divisions: (maxSimilarityTarget - minSimilarityTarget) ~/ 5,
              value: _t.toDouble(),
              label: '$_t% similar',
              onChanged: (v) => _set(v.round()),
              onChangeEnd: (v) => _set(v.round(), save: true),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              Text('More original', style: muted),
              const Spacer(),
              Text('Closer to reference', style: muted),
            ]),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in similarityPresets)
                ChoiceChip(
                  label: Text('${p.$1} ${p.$2}%'),
                  selected: _t == p.$2,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => _set(p.$2, save: true),
                ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, box) {
            final keep = _PlanList(
                title: 'Stays the same',
                icon: Icons.lock_outline,
                color: AppTheme.success,
                items: plan.keep);
            final change = _PlanList(
                title: 'Will change',
                icon: Icons.autorenew,
                color: AppTheme.warning,
                items: plan.change);
            if (box.maxWidth < 520) {
              return Column(
                  children: [keep, const SizedBox(height: 10), change]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: keep),
                const SizedBox(width: 12),
                Expanded(child: change),
              ],
            );
          }),
          if (_t >= 80) ...[
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 16, color: Color(0xFFEF4444)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    'Very close to the reference - use only for your own or '
                    'licensed pictures (copyright risk).',
                    style: muted),
              ),
            ]),
          ],
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: widget.antiRepeat,
            onChanged: widget.onAntiRepeat,
            title: const Text('Avoid repeating earlier prompts',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            subtitle: Text(
                'Rewrites a prompt once if it reads like another one of this '
                'session (targets up to 75%).',
                style: muted),
          ),
        ],
      ),
    );
  }
}

class _PlanList extends StatelessWidget {
  const _PlanList(
      {required this.title,
      required this.icon,
      required this.color,
      required this.items});
  final String title;
  final IconData icon;
  final Color color;
  final List<String> items;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text('$title (${items.length})',
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
          ]),
          const SizedBox(height: 6),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final t in items)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withValues(alpha: 0.30)),
                  ),
                  child: Text(t, style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ],
      );
}
