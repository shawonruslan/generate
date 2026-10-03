import 'dart:convert';
import 'dart:typed_data';

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/theme_engine.dart';
import '../../state/app_state.dart';
import 'fa.dart';

extension AppCtx on BuildContext {
  AppState get app => read<AppState>();
  AppState get appWatch => watch<AppState>();
  ZedgePalette get pal => watch<AppState>().palette;
  ZedgePalette get palRead => read<AppState>().palette;
}

/// Glass card - the base surface of the v27 "Glass UI".
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.color,
    this.borderColor,
    this.radius,
    this.glow = false,
    this.onTap,
    this.gradient,
    this.blur = true,
  });
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets? margin;
  final Color? color;
  final Color? borderColor;
  final double? radius;
  final bool glow;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final r = radius ?? p.radiusMd;
    final bg = color ?? p.cardColor.withValues(alpha: p.isDark ? 0.72 : 0.92);
    final card = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: gradient == null ? bg : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(r),
        border: Border.all(color: borderColor ?? p.border),
        boxShadow: [
          BoxShadow(color: (p.isDark ? Colors.black : p.accent).withValues(alpha: glow ? 0.35 : (p.isDark ? 0.35 : 0.08)), blurRadius: glow ? 32 : 20, offset: const Offset(0, 10)),
          if (glow) BoxShadow(color: p.primary.withValues(alpha: 0.25), blurRadius: 40, spreadRadius: -6),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: blur
            ? BackdropFilter(filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12), child: Padding(padding: padding, child: child))
            : Padding(padding: padding, child: child),
      ),
    );
    if (onTap == null) return card;
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: onTap, child: card));
  }
}

/// Section heading with icon + optional trailing actions (`.section-title`).
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.icon, this.subtitle, this.trailing, this.size = 17});
  final String title;
  final String? icon;
  final String? subtitle;
  final Widget? trailing;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final head = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (icon != null) ...[
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(gradient: p.primaryGradient, borderRadius: BorderRadius.circular(10)),
          child: Center(child: Fa(icon!, size: 14, color: p.onPrimary)),
        ),
        const SizedBox(width: 10),
      ],
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: p.text, letterSpacing: -0.2)),
          if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle!, style: TextStyle(fontSize: 12, color: p.muted, height: 1.4))),
        ]),
      ),
    ]);
    if (trailing == null) return head;
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 620) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [head, const SizedBox(height: 8), trailing!]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [Expanded(child: head), const SizedBox(width: 12), trailing!]);
    });
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.icon, this.color, this.fg, this.outline = false, this.small = false, this.onTap, this.tooltip});
  final String text;
  final String? icon;
  final Color? color;
  final Color? fg;
  final bool outline;
  final bool small;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = color ?? p.badgeColor;
    final f = fg ?? (outline ? c : (color == null ? p.badgeFg : _fgFor(c)));
    final w = Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 7 : 10, vertical: small ? 2 : 4),
      decoration: BoxDecoration(
        color: outline ? c.withValues(alpha: 0.12) : c,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: outline ? c.withValues(alpha: 0.5) : Colors.transparent),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Fa(icon!, size: small ? 9 : 11, color: f), const SizedBox(width: 5)],
        Text(text, style: TextStyle(color: f, fontSize: small ? 10.5 : 12, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
      ]),
    );
    final wrapped = tooltip != null ? Tooltip(message: tooltip!, child: w) : w;
    if (onTap == null) return wrapped;
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: onTap, child: wrapped));
  }

  static Color _fgFor(Color c) => c.computeLuminance() > 0.45 ? const Color(0xff14121a) : Colors.white;
}

enum ZBtnKind { primary, ghost, danger, success, soft }

/// Button used everywhere (`.btn`, `.gh-btn`, `.sched-btn` ...).
class ZButton extends StatelessWidget {
  const ZButton(this.label, {super.key, this.icon, this.onPressed, this.kind = ZBtnKind.primary, this.small = false, this.busy = false, this.tooltip, this.expand = false});
  final String label;
  final String? icon;
  final VoidCallback? onPressed;
  final ZBtnKind kind;
  final bool small;
  final bool busy;
  final String? tooltip;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final disabled = onPressed == null || busy;
    Color bg, fg, border;
    Gradient? grad;
    switch (kind) {
      case ZBtnKind.primary:
        grad = p.buttonGradient;
        bg = p.buttonColor;
        fg = p.buttonFg;
        border = Colors.transparent;
        break;
      case ZBtnKind.ghost:
        bg = p.surfaceHover.withValues(alpha: 0.6);
        fg = p.text;
        border = p.border;
        break;
      case ZBtnKind.danger:
        bg = p.danger.withValues(alpha: 0.14);
        fg = p.danger;
        border = p.danger.withValues(alpha: 0.4);
        break;
      case ZBtnKind.success:
        bg = p.ok.withValues(alpha: 0.16);
        fg = p.ok;
        border = p.ok.withValues(alpha: 0.4);
        break;
      case ZBtnKind.soft:
        bg = p.primary.withValues(alpha: 0.14);
        fg = p.primary;
        border = p.primary.withValues(alpha: 0.35);
        break;
    }
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          SizedBox(width: small ? 11 : 13, height: small ? 11 : 13, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
        else if (icon != null)
          Fa(icon!, size: small ? 11 : 13, color: fg),
        if (busy || icon != null) SizedBox(width: small ? 6 : 8),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: small ? 12 : 13.5, fontWeight: FontWeight.w700))),
      ],
    );
    final btn = AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: disabled ? 0.55 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled ? null : onPressed,
          borderRadius: BorderRadius.circular(p.radiusSm),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: small ? 10 : 14, vertical: small ? 6 : 10),
            decoration: BoxDecoration(
              color: grad == null ? bg : null,
              gradient: grad,
              borderRadius: BorderRadius.circular(p.radiusSm),
              border: Border.all(color: border),
              boxShadow: kind == ZBtnKind.primary && !disabled ? [BoxShadow(color: p.primary.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6))] : null,
            ),
            child: child,
          ),
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: btn) : btn;
  }
}

/// Square icon button (`.v27-icon-btn`, `.gh-icon-btn`).
class ZIconButton extends StatelessWidget {
  const ZIconButton(this.icon, {super.key, this.onPressed, this.tooltip, this.size = 34, this.color, this.badge, this.danger = false});
  final String icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final Color? color;
  final int? badge;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final w = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: danger ? p.danger.withValues(alpha: 0.12) : p.surfaceHover.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: danger ? p.danger.withValues(alpha: 0.4) : p.border),
            ),
            child: Center(child: Fa(icon, size: size * 0.42, color: color ?? (danger ? p.danger : p.text))),
          ),
          if (badge != null && badge! > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: p.danger, borderRadius: BorderRadius.circular(999), border: Border.all(color: p.surface, width: 1.5)),
                child: Text(badge! > 99 ? '99+' : '$badge', style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800)),
              ),
            ),
        ]),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: w) : w;
  }
}

/// Segmented control (`.sched-seg`, `.v27-seg`).
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.options, required this.value, required this.onChanged, this.small = false});
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: p.bg.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(10), border: Border.all(color: p.border)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((o) {
          final on = o.$1 == value;
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => onChanged(o.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: EdgeInsets.symmetric(horizontal: small ? 9 : 12, vertical: small ? 4 : 6),
                decoration: BoxDecoration(gradient: on ? p.buttonGradient : null, borderRadius: BorderRadius.circular(8)),
                child: Text(o.$2, style: TextStyle(color: on ? p.buttonFg : p.muted, fontSize: small ? 11.5 : 12.5, fontWeight: FontWeight.w700)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Labelled form field wrapper.
class Field extends StatelessWidget {
  const Field(this.label, {super.key, required this.child, this.hint, this.width});
  final String label;
  final Widget child;
  final String? hint;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final col = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.muted, letterSpacing: 0.4)),
      const SizedBox(height: 5),
      child,
      if (hint != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(hint!, style: TextStyle(fontSize: 11, color: p.muted))),
    ]);
    return width == null ? col : SizedBox(width: width, child: col);
  }
}

/// Simple styled dropdown.
class ZDropdown<T> extends StatelessWidget {
  const ZDropdown({super.key, required this.value, required this.items, required this.onChanged, this.width, this.dense = false});
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  final double? width;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final dd = Container(
      height: dense ? 34 : 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: p.bg.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(p.radiusSm), border: Border.all(color: p.border)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: items.any((e) => e.$1 == value) ? value : items.first.$1,
          isExpanded: true,
          isDense: true,
          dropdownColor: p.surface,
          borderRadius: BorderRadius.circular(p.radiusSm),
          style: TextStyle(color: p.text, fontSize: 13, fontWeight: FontWeight.w600),
          icon: Fa('fa-chevron-right', size: 10, color: p.muted),
          items: items.map((e) => DropdownMenuItem<T>(value: e.$1, child: Text(e.$2, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
    return width == null ? dd : SizedBox(width: width, child: dd);
  }
}

/// Empty state block (`.gh-empty`, `.meta-alert-empty`).
class EmptyNote extends StatelessWidget {
  const EmptyNote(this.text, {super.key, this.icon, this.big = false});
  final String text;
  final String? icon;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(big ? 28 : 14),
      decoration: BoxDecoration(color: p.bg.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(p.radiusSm), border: Border.all(color: p.border)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Fa(icon!, size: big ? 26 : 16, color: p.muted), SizedBox(height: big ? 10 : 6)],
        Text(text, textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: big ? 14 : 12.5)),
      ]),
    );
  }
}

/// Network image with placeholder / error fallback icon.
class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.fit = BoxFit.cover, this.fallbackIcon = 'fa-image', this.width, this.height, this.radius = 0});
  final String? url;
  final BoxFit fit;
  final String fallbackIcon;
  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget fallback = Container(
      width: width,
      height: height,
      color: p.surfaceHover,
      child: Center(child: Fa(fallbackIcon, size: 22, color: p.muted)),
    );
    if (url == null || url!.isEmpty) return ClipRRect(borderRadius: BorderRadius.circular(radius), child: fallback);
    // Legacy items may carry an inline data URL (`fileBase64` / `imageBase64`).
    if (url!.startsWith('data:')) {
      final bytes = decodeDataUrl(url!);
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: bytes == null ? fallback : Image.memory(bytes, fit: fit, width: width, height: height, gaplessPlayback: true, errorBuilder: (_, __, ___) => fallback),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        url!,
        fit: fit,
        width: width,
        height: height,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (c, child, prog) => prog == null
            ? child
            : Container(width: width, height: height, color: p.surfaceHover, child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.primary)))),
      ),
    );
  }
}

/// Simple key/value line.
class KV extends StatelessWidget {
  const KV(this.k, this.v, {super.key, this.vWidget});
  final String k;
  final String v;
  final Widget? vWidget;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 110, child: Text(k, style: TextStyle(color: p.muted, fontSize: 12.5))),
        Expanded(child: vWidget ?? SelectableText(v, style: TextStyle(color: p.text, fontSize: 12.5, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

/// Native-like confirm / alert / prompt dialogs (`confirm()`, `alert()`).
Future<bool> confirmDialog(BuildContext context, String message, {String title = 'Confirm', String okLabel = 'OK', bool danger = false}) async {
  final p = context.palRead;
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560, maxHeight: 460), child: SingleChildScrollView(child: SelectableText(message, style: TextStyle(color: p.text, fontSize: 13.5, height: 1.5)))),
      actions: [
        ZButton('Cancel', kind: ZBtnKind.ghost, onPressed: () => Navigator.pop(ctx, false)),
        ZButton(okLabel, kind: danger ? ZBtnKind.danger : ZBtnKind.primary, onPressed: () => Navigator.pop(ctx, true)),
      ],
    ),
  );
  return r == true;
}

Future<void> alertDialog(BuildContext context, String message, {String title = 'Notice'}) async {
  final p = context.palRead;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560, maxHeight: 460), child: SingleChildScrollView(child: SelectableText(message, style: TextStyle(color: p.text, fontSize: 13.5, height: 1.5)))),
      actions: [ZButton('OK', onPressed: () => Navigator.pop(ctx))],
    ),
  );
}

/// Pagination bar with ellipsis (`renderPagination`).
class Pagination extends StatelessWidget {
  const Pagination({super.key, required this.page, required this.pages, required this.onPage});
  final int page; // 1-based
  final int pages;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    if (pages <= 1) return const SizedBox.shrink();
    final p = context.pal;
    final nums = <int?>[];
    for (var i = 1; i <= pages; i++) {
      if (i == 1 || i == pages || (i >= page - 2 && i <= page + 2)) {
        nums.add(i);
      } else if (nums.isNotEmpty && nums.last != null) {
        nums.add(null);
      }
    }
    Widget btn(String label, VoidCallback? onTap, {bool on = false}) => Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              constraints: const BoxConstraints(minWidth: 34),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(gradient: on ? p.buttonGradient : null, color: on ? null : p.surfaceHover.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(8), border: Border.all(color: on ? Colors.transparent : p.border)),
              child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: on ? p.buttonFg : (onTap == null ? p.muted : p.text), fontWeight: FontWeight.w700, fontSize: 12.5)),
            ),
          ),
        );
    return Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
      btn('‹ Prev', page > 1 ? () => onPage(page - 1) : null),
      for (final n in nums) n == null ? Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text('…', style: TextStyle(color: p.muted))) : btn('$n', () => onPage(n), on: n == page),
      btn('Next ›', page < pages ? () => onPage(page + 1) : null),
    ]);
  }
}

/// Decode a `data:<mime>;base64,....` URL to bytes (null when malformed).
Uint8List? decodeDataUrl(String url) {
  final i = url.indexOf(',');
  if (i < 0) return null;
  try {
    return base64Decode(url.substring(i + 1).trim());
  } catch (_) {
    return null;
  }
}
