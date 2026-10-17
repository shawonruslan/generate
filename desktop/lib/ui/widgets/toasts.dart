import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import 'fa.dart';

/// Toast host (`#zToastHost`) - bottom-right stack, auto dismissed by AppState after 3.4 s.
class ToastHost extends StatelessWidget {
  const ToastHost({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = app.palette;
    return Positioned(
      right: 18,
      bottom: 18,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: app.toasts.map((t) {
          final err = t.kind == 'err' || t.kind == 'error';
          final warn = t.kind == 'warn';
          final c = err ? p.danger : warn ? p.warn : p.ok;
          return TweenAnimationBuilder<double>(
            key: ValueKey(t.id),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            builder: (_, v, child) => Opacity(opacity: v.clamp(0, 1).toDouble(), child: Transform.translate(offset: Offset(0, (1 - v) * 16), child: child)),
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: p.ink,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.withValues(alpha: 0.6)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Fa(err ? 'fa-circle-xmark' : warn ? 'fa-triangle-exclamation' : 'fa-circle-check', size: 14, color: c),
                const SizedBox(width: 10),
                Flexible(child: Text(t.text, style: TextStyle(color: p.onInk, fontSize: 13, fontWeight: FontWeight.w600))),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }
}
