import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../domain/theme_engine.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/fa.dart';
import '../widgets/responsive.dart';

/// v31 Theme Switcher drawer: strictly Zedge Panel (light default) and Night (dark) themes.
Future<void> openThemeStudio(BuildContext context) async {
  final app = context.read<AppState>();
  if (app.themeEditing) return;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close Theme',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (ctx, a, b) => const _ThemeDrawer(),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return SlideTransition(position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(curved), child: child);
    },
  ).whenComplete(() {
    if (app.themeEditing) app.themeCloseDrawer(keep: false);
  });
}

class _ThemeDrawer extends StatefulWidget {
  const _ThemeDrawer();

  @override
  State<_ThemeDrawer> createState() => _ThemeDrawerState();
}

class _ThemeDrawerState extends State<_ThemeDrawer> {
  late ThemeConfig _draft;
  String _status = '';
  String _statusKind = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _draft = ThemeConfig.sanitize(app.themeCurrent.toJson());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) app.themePreview(_draft.copy());
    });
  }

  AppState get _app => context.read<AppState>();

  void _preview() {
    _draft = ThemeConfig.sanitize(_draft.toJson());
    _app.themePreview(_draft.copy());
    setState(() {});
  }

  String? get _presetKey => _draft.matchingPreset();

  Future<void> _save(bool all) async {
    final app = _app;
    setState(() {
      _saving = true;
      _status = 'Saving…';
      _statusKind = '';
    });
    try {
      final accounts = await app.themeSave(_draft.copy(), all: all);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _status = 'Saved for ${accounts.map(app.accountLabel).join(', ')} — synced across panel & apps.';
        _statusKind = 'ok';
      });
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) {
        app.themeCloseDrawer(keep: true);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _status = 'Saved on this device only. Firebase: $e';
        _statusKind = 'err';
      });
    }
  }

  void _close() {
    _app.themeCloseDrawer(keep: false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.appWatch;
    final p = app.palette;
    final size = MediaQuery.sizeOf(context);
    final w = size.width < Bp.xs ? size.width : 400.0;
    final accLabel = app.accountLabel(app.activeProject);

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
      child: Focus(
        autofocus: true,
        child: Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: w,
              height: size.height,
              decoration: BoxDecoration(
                color: p.surface,
                border: Border(left: BorderSide(color: p.border)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 40, offset: const Offset(-10, 0))],
              ),
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
                  decoration: BoxDecoration(color: p.surface, border: Border(bottom: BorderSide(color: p.border))),
                  child: Row(children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: p.primary, borderRadius: BorderRadius.circular(12)),
                      alignment: Alignment.center,
                      child: Fa('fa-palette', size: 16, color: p.onPrimary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Theme', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: p.text)),
                        Text('$accLabel · Zedge Panel & Night', style: TextStyle(fontSize: 11.5, color: p.muted)),
                      ]),
                    ),
                    ZIconButton('fa-times', tooltip: 'Close', onPressed: _close),
                  ]),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Expanded(child: Text('SELECT THEME', style: TextStyle(fontSize: 11, letterSpacing: 1.1, fontWeight: FontWeight.w800, color: p.muted))),
                        Text('Zedge Panel or Night', style: TextStyle(fontSize: 11, color: p.muted)),
                      ]),
                      const SizedBox(height: 12),
                      AutoGrid(
                        minTile: 150,
                        gap: 12,
                        maxCols: 2,
                        minCols: 2,
                        children: kThemePresets.map((pr) => _PresetTile(
                          preset: pr,
                          on: _presetKey == pr.key,
                          ring: p.primary,
                          onTap: () {
                            _draft.applyPreset(pr);
                            _preview();
                          },
                        )).toList(),
                      ),
                      const SizedBox(height: 18),
                      if (_status.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: (_statusKind == 'ok' ? p.ok : (_statusKind == 'err' ? p.danger : p.info)).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(p.radiusSm),
                            border: Border.all(color: (_statusKind == 'ok' ? p.ok : (_statusKind == 'err' ? p.danger : p.info)).withValues(alpha: 0.5)),
                          ),
                          child: Text(_status, style: TextStyle(fontSize: 12.5, color: p.text)),
                        ),
                    ]),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                  decoration: BoxDecoration(color: p.tintSoft, border: Border(top: BorderSide(color: p.border))),
                  child: Row(children: [
                    ZButton('Default (Zedge)', kind: ZBtnKind.ghost, small: true, onPressed: () {
                      _draft = ThemeConfig.sanitize(ThemeConfig.defaults.toJson());
                      _preview();
                    }),
                    const Spacer(),
                    ZButton('All accounts', kind: ZBtnKind.ghost, small: true, tooltip: 'Save this theme for every account', onPressed: _saving ? null : () => _save(true)),
                    const SizedBox(width: 8),
                    ZButton('Save for $accLabel', icon: 'fa-save', small: true, busy: _saving, onPressed: _saving ? null : () => _save(false)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _PresetTile extends StatefulWidget {
  const _PresetTile({required this.preset, required this.on, required this.ring, required this.onTap});
  final ThemePreset preset;
  final bool on;
  final Color ring;
  final VoidCallback onTap;

  @override
  State<_PresetTile> createState() => _PresetTileState();
}

class _PresetTileState extends State<_PresetTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final pr = widget.preset;
    final primary = colorFromHex(pr.primary), accent = colorFromHex(pr.accent), bg = colorFromHex(pr.bg), surface = colorFromHex(pr.surface), text = colorFromHex(pr.text);
    final dark = pr.isDark;
    final on = widget.on;
    final line = text.withValues(alpha: dark ? 0.16 : 0.12);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hover && !on ? 1.025 : 1,
          duration: const Duration(milliseconds: 140),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: on ? widget.ring : (_hover ? primary.withValues(alpha: 0.7) : line), width: on ? 2 : 1),
              boxShadow: [
                if (on) BoxShadow(color: widget.ring.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 4)),
                if (_hover && !on) BoxShadow(color: primary.withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0, 4)),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                height: 68,
                child: Stack(children: [
                  Positioned(left: 0, right: 0, top: 0, height: 14, child: DecoratedBox(decoration: BoxDecoration(color: primary))),
                  Positioned(left: 0, top: 14, bottom: 0, width: 20, child: ColoredBox(color: surface)),
                  Positioned(left: 26, top: 20, right: 8, height: 22, child: Container(decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(4), border: Border.all(color: line, width: 0.8)))),
                  Positioned(left: 26, top: 46, height: 14, width: 34, child: Container(decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(7)))),
                  if (on)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(width: 18, height: 18, decoration: BoxDecoration(color: primary, shape: BoxShape.circle), alignment: Alignment.center, child: const Fa('fa-check', size: 9, color: Colors.white)),
                    ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(pr.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: text)),
                  Text(pr.vibe, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: text.withValues(alpha: 0.65))),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
