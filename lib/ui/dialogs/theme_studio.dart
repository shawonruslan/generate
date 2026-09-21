import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../domain/theme_engine.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/fa.dart';
import '../widgets/responsive.dart';

/// v26/v27 Theme Studio drawer: presets, custom colours, font size, corner
/// radius, density, per-element colours. Live preview while editing; saving
/// writes `dashboardSettings/theme` for one or all accounts.
Future<void> openThemeStudio(BuildContext context) async {
  final app = context.read<AppState>();
  if (app.themeEditing) return;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close Theme Studio',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (ctx, a, b) => const _ThemeDrawer(),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return SlideTransition(position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(curved), child: child);
    },
  ).whenComplete(() {
    // close(false) – barrier tap / Esc: restore the saved theme unless we saved.
    if (app.themeEditing) app.themeCloseDrawer(keep: false);
  });
}

const List<List<String>> _kColorRows = [
  ['primary', 'Primary'],
  ['accent', 'Accent'],
  ['bg', 'Background'],
  ['surface', 'Cards'],
  ['text', 'Text'],
];

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
    // T.editing = true + apply current (no visible change) - after the first frame to avoid rebuild-during-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) app.themePreview(_draft.copy());
    });
  }

  AppState get _app => context.read<AppState>();

  void _preview() {
    _draft.preset = _draft.matchingPreset() ?? 'custom';
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
        _status = 'Saved for ${accounts.map(app.accountLabel).join(', ')} — the app will follow this theme too.';
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
    final w = size.width < Bp.xs ? size.width : (size.width < Bp.sm ? 420.0 : 460.0);
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
                // head
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
                  decoration: BoxDecoration(gradient: LinearGradient(colors: [p.primary.withValues(alpha: 0.18), p.accent.withValues(alpha: 0.10)]), border: Border(bottom: BorderSide(color: p.border))),
                  child: Row(children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(gradient: p.primaryGradient, borderRadius: BorderRadius.circular(12)),
                      alignment: Alignment.center,
                      child: Fa('fa-palette', size: 16, color: p.onPrimary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Theme Studio', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: p.text)),
                        Text('$accLabel · saved in Firebase, shared with the app', style: TextStyle(fontSize: 11.5, color: p.muted)),
                      ]),
                    ),
                    ZIconButton('fa-times', tooltip: 'Close', onPressed: _close),
                  ]),
                ),
                // body
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _label('Presets'),
                      const SizedBox(height: 8),
                      _presets(p),
                      const SizedBox(height: 18),
                      _label('Custom colors', right: _presetKey == null ? 'custom palette' : ''),
                      const SizedBox(height: 8),
                      for (final c in _kColorRows) _ColorRow(label: c[1], hex: _hexOf(c[0]), onChanged: (v) {
                        _setHex(c[0], v);
                        _preview();
                      }),
                      const SizedBox(height: 14),
                      _label('Font size', right: '${(_draft.fontScale * 100).round()}%'),
                      Slider(
                        value: (_draft.fontScale * 100).roundToDouble().clamp(80.0, 130.0).toDouble(),
                        min: 80,
                        max: 130,
                        divisions: 10,
                        onChanged: (v) {
                          _draft.fontScale = v / 100;
                          _preview();
                        },
                      ),
                      _label('Corner radius', right: '${(_draft.radius * 100).round()}%'),
                      Slider(
                        value: (_draft.radius * 100).roundToDouble().clamp(0.0, 160.0).toDouble(),
                        min: 0,
                        max: 160,
                        divisions: 16,
                        onChanged: (v) {
                          _draft.radius = v / 100;
                          _preview();
                        },
                      ),
                      const SizedBox(height: 6),
                      _label('Density'),
                      const SizedBox(height: 8),
                      Segmented<String>(
                        options: const [('comfortable', 'Comfortable'), ('compact', 'Compact')],
                        value: _draft.density,
                        onChanged: (v) {
                          _draft.density = v;
                          _preview();
                        },
                      ),
                      const SizedBox(height: 18),
                      _label('Element colors', right: 'header · sidebar · cards · buttons · ticker · badges'),
                      const SizedBox(height: 8),
                      for (final k in kThemeElementKeys)
                        _ElementRow(
                          name: k[1],
                          hex: _draft.elements[k[0]],
                          autoColor: _autoColorFor(k[0], p),
                          onChanged: (v) {
                            if (v == null) {
                              _draft.elements.remove(k[0]);
                            } else {
                              _draft.elements[k[0]] = v;
                            }
                            _preview();
                          },
                        ),
                      const SizedBox(height: 14),
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
                      const SizedBox(height: 8),
                      Text(
                        'Changes preview live. Close without saving to go back to the saved theme. Element colours are stored per account on this device (zedgeThemeEl:v27) and travel with the theme to Firebase.',
                        style: TextStyle(fontSize: 11.5, color: p.muted, height: 1.4),
                      ),
                    ]),
                  ),
                ),
                // foot
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                  decoration: BoxDecoration(color: p.tintSoft, border: Border(top: BorderSide(color: p.border))),
                  child: Row(children: [
                    ZButton('Reset', kind: ZBtnKind.ghost, small: true, onPressed: () {
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

  String _hexOf(String k) => switch (k) {
        'primary' => _draft.primary,
        'accent' => _draft.accent,
        'bg' => _draft.bg,
        'surface' => _draft.surface,
        _ => _draft.text,
      };

  void _setHex(String k, String v) {
    switch (k) {
      case 'primary':
        _draft.primary = v;
      case 'accent':
        _draft.accent = v;
      case 'bg':
        _draft.bg = v;
      case 'surface':
        _draft.surface = v;
      default:
        _draft.text = v;
    }
  }

  /// Fallback shown for "Auto" (what the element gets from the theme).
  Color _autoColorFor(String key, ZedgePalette p) => switch (key) {
        'button' || 'navActive' || 'badge' => p.primary,
        'ticker' => p.surface,
        _ => p.surface,
      };

  Widget _label(String left, {String right = ''}) {
    final p = context.pal;
    return Row(children: [
      Expanded(child: Text(left.toUpperCase(), style: TextStyle(fontSize: 11, letterSpacing: 1.1, fontWeight: FontWeight.w800, color: p.muted))),
      if (right.isNotEmpty) Text(right, style: TextStyle(fontSize: 11, color: p.muted, fontStyle: FontStyle.italic)),
    ]);
  }

  Widget _presets(ZedgePalette p) {
    final cur = _presetKey;
    return AutoGrid(
      minTile: 120,
      gap: 8,
      maxCols: 3,
      minCols: 2,
      children: kThemePresets.map((pr) {
        final on = cur == pr.key;
        return InkWell(
          onTap: () {
            _draft.applyPreset(pr);
            _preview();
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorFromHex(pr.surface),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: on ? p.primary : p.border, width: on ? 2 : 1),
              boxShadow: on ? [BoxShadow(color: p.primary.withValues(alpha: 0.35), blurRadius: 14)] : null,
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                for (final h in [pr.primary, pr.accent, pr.bg, pr.text])
                  Container(width: 14, height: 14, margin: const EdgeInsets.only(right: 4), decoration: BoxDecoration(color: colorFromHex(h), shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.25)))),
                const Spacer(),
                if (on) Fa('fa-check', size: 11, color: colorFromHex(pr.text)),
              ]),
              const SizedBox(height: 8),
              Text(pr.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: colorFromHex(pr.text))),
              Text(pr.mode, style: TextStyle(fontSize: 10.5, color: colorFromHex(pr.text).withValues(alpha: 0.6))),
            ]),
          ),
        );
      }).toList(),
    );
  }
}

/// `<input type="color"> + <input type="text">` row.
class _ColorRow extends StatefulWidget {
  const _ColorRow({required this.label, required this.hex, required this.onChanged});
  final String label;
  final String hex;
  final ValueChanged<String> onChanged;

  @override
  State<_ColorRow> createState() => _ColorRowState();
}

class _ColorRowState extends State<_ColorRow> {
  late final TextEditingController _c = TextEditingController(text: widget.hex);

  @override
  void didUpdateWidget(covariant _ColorRow old) {
    super.didUpdateWidget(old);
    if (old.hex != widget.hex && _c.text.toLowerCase() != widget.hex) _c.text = widget.hex;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        SizedBox(width: 92, child: Text(widget.label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.text))),
        _Swatch(hex: widget.hex, onPicked: (v) {
          _c.text = v;
          widget.onChanged(v);
        }),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _c,
            maxLength: 7,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
            decoration: const InputDecoration(counterText: '', hintText: '#rrggbb', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
            onChanged: (t) {
              final v = normHex(t, null);
              if (v != null) widget.onChanged(v);
            },
          ),
        ),
      ]),
    );
  }
}

/// Element colour row (v27.8): name · value/Auto · swatch · "back to automatic" wand.
class _ElementRow extends StatelessWidget {
  const _ElementRow({required this.name, required this.hex, required this.autoColor, required this.onChanged});
  final String name;
  final String? hex;
  final Color autoColor;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: p.tintCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.border)),
      child: Row(children: [
        Expanded(child: Text(name, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.text))),
        Text(hex ?? 'Auto', style: TextStyle(fontSize: 11.5, fontFamily: hex == null ? null : 'monospace', color: p.muted)),
        const SizedBox(width: 8),
        _Swatch(hex: hex ?? hexFromColor(autoColor), onPicked: onChanged, dim: hex == null),
        const SizedBox(width: 4),
        ZIconButton('fa-wand-magic-sparkles', size: 28, tooltip: 'Back to automatic theme color', onPressed: hex == null ? null : () => onChanged(null)),
      ]),
    );
  }
}

/// Clickable colour swatch → opens the colour picker sheet.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.hex, required this.onPicked, this.dim = false});
  final String hex;
  final ValueChanged<String> onPicked;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Tooltip(
      message: 'Pick a color',
      child: InkWell(
        onTap: () async {
          final v = await _pickColor(context, hex);
          if (v != null) onPicked(v);
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 34,
          height: 30,
          decoration: BoxDecoration(
            color: colorFromHex(hex).withValues(alpha: dim ? 0.45 : 1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: p.border),
          ),
        ),
      ),
    );
  }
}

/// Simple HSV colour picker dialog (no extra package needed).
Future<String?> _pickColor(BuildContext context, String hex) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _ColorPickerDialog(initial: hex),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.initial});
  final String initial;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(colorFromHex(widget.initial));
  late final TextEditingController _hex = TextEditingController(text: widget.initial);

  String get _current => hexFromColor(_hsv.toColor());

  void _sync() {
    _hex.text = _current;
    setState(() {});
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    const quick = ['#7c5cff', '#22d3ee', '#34d399', '#60a5fa', '#fb7185', '#f59e0b', '#ffd400', '#a78bfa', '#38bdf8', '#ef4444', '#ffffff', '#000000', '#111829', '#0e1d31', '#fffdf6', '#e6ebff'];
    return AlertDialog(
      title: Text('Pick a color', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: p.text)),
      content: SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // saturation / value plane
          SizedBox(
            height: 170,
            child: LayoutBuilder(builder: (ctx, c) {
              void handle(Offset local) {
                final s = (local.dx / c.maxWidth).clamp(0.0, 1.0).toDouble();
                final v = 1 - (local.dy / c.maxHeight).clamp(0.0, 1.0).toDouble();
                _hsv = _hsv.withSaturation(s).withValue(v);
                _sync();
              }
              return GestureDetector(
                onPanDown: (d) => handle(d.localPosition),
                onPanUpdate: (d) => handle(d.localPosition),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(fit: StackFit.expand, children: [
                    DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.white, HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor()]))),
                    const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black]))),
                    Positioned(
                      left: _hsv.saturation * c.maxWidth - 8,
                      top: (1 - _hsv.value) * c.maxHeight - 8,
                      child: Container(width: 16, height: 16, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2), boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)])),
                    ),
                  ]),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          // hue strip
          SizedBox(
            height: 22,
            child: LayoutBuilder(builder: (ctx, c) {
              void handle(Offset local) {
                _hsv = _hsv.withHue((local.dx / c.maxWidth).clamp(0.0, 1.0).toDouble() * 360);
                _sync();
              }
              return GestureDetector(
                onPanDown: (d) => handle(d.localPosition),
                onPanUpdate: (d) => handle(d.localPosition),
                child: Stack(children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: LinearGradient(colors: [for (var h = 0; h <= 360; h += 30) HSVColor.fromAHSV(1, h.toDouble() % 360, 1, 1).toColor()]),
                    ),
                  ),
                  Positioned(
                    left: (_hsv.hue / 360) * c.maxWidth - 6,
                    top: 1,
                    child: Container(width: 12, height: 20, decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.white, width: 2), boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)])),
                  ),
                ]),
              );
            }),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Container(width: 44, height: 36, decoration: BoxDecoration(color: _hsv.toColor(), borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border))),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _hex,
                maxLength: 7,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: const InputDecoration(counterText: '', isDense: true, hintText: '#rrggbb'),
                onChanged: (t) {
                  final v = normHex(t, null);
                  if (v != null) setState(() => _hsv = HSVColor.fromColor(colorFromHex(v)));
                },
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: quick
                .map((h) => InkWell(
                      onTap: () {
                        _hsv = HSVColor.fromColor(colorFromHex(h));
                        _sync();
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(width: 24, height: 24, decoration: BoxDecoration(color: colorFromHex(h), borderRadius: BorderRadius.circular(6), border: Border.all(color: p.border))),
                    ))
                .toList(),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(_current), child: const Text('Use color')),
      ],
    );
  }
}
