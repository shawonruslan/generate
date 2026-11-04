import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';

/// Announcements screen (admin) — mirrors the web app's Announcements view.
///
/// Inline composer card: MESSAGE textarea (300 chars, counter), TYPE pills
/// (Info / Good news / Notice / Urgent), SHOW FOR expiry dropdown, live
/// PREVIEW marquee bar, full-width "Publish to everyone" button.
/// Below: "All announcements" card with the list + empty state.
///
/// Active announcements are also embedded in every GET /api/data response, so
/// all users see them — no extra sync work is needed here.
class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  /// Wired by the home shell's "+ New" button / FAB.
  static VoidCallback? requestNew;

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

/// Announcement types — mirrors the web's ANN_T.
class _AnnType {
  final String key;
  final String label;
  final IconData icon;
  final Color color;
  const _AnnType(this.key, this.label, this.icon, this.color);
}

const _annTypes = [
  _AnnType('info', 'Info', Icons.campaign_outlined, Color(0xFF3730A3)),
  _AnnType('success', 'Good news', Icons.check_circle_outline,
      Color(0xFF065F46)),
  _AnnType('warning', 'Notice', Icons.warning_amber_outlined,
      Color(0xFF92400E)),
  _AnnType('urgent', 'Urgent', Icons.notifications_outlined,
      Color(0xFF991B1B)),
];

/// Ticker bar colors per type — mirrors the web's .ticker styles.
class _TickerColors {
  final Color bg;
  final Color fg;
  const _TickerColors(this.bg, this.fg);
}

_TickerColors _tickerColors(String type, bool night) {
  switch (type) {
    case 'success':
      return night
          ? const _TickerColors(Color(0xFF0F2E22), Color(0xFF4ADE80))
          : const _TickerColors(Color(0xFFECFDF5), Color(0xFF065F46));
    case 'warning':
      return night
          ? const _TickerColors(Color(0xFF3A2A0B), Color(0xFFFCD34D))
          : const _TickerColors(Color(0xFFFFF7ED), Color(0xFF92400E));
    case 'urgent':
      return night
          ? const _TickerColors(Color(0xFF3B1111), Color(0xFFFCA5A5))
          : const _TickerColors(Color(0xFFFEF2F2), Color(0xFF991B1B));
    case 'info':
    default:
      return night
          ? const _TickerColors(Color(0xFF2B3242), Color(0xFFC7D2FE))
          : const _TickerColors(Color(0xFFEEF2FF), Color(0xFF3730A3));
  }
}

/// Simple auto-scrolling marquee for the announcement preview bar.
class _Marquee extends StatefulWidget {
  final String text;
  final TextStyle style;
  const _Marquee({required this.text, required this.style});

  @override
  State<_Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<_Marquee>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(seconds: 14))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final tp = TextPainter(
                  text: TextSpan(text: widget.text, style: widget.style),
                  textDirection: TextDirection.ltr,
                  maxLines: 1)
                ..layout();
              final textW = tp.width;
              if (textW <= 0 || w <= 0) return child!;
              final dx = w - _c.value * (w + textW);
              return Transform.translate(
                  offset: Offset(dx, 0), child: child);
            },
          );
        },
        child: Text(widget.text,
            maxLines: 1, softWrap: false, style: widget.style),
      ),
    );
  }
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  List<Announcement> _items = [];
  bool _loading = true;
  String? _error;

  // Composer state.
  final _msgCtrl = TextEditingController();
  final _msgFocus = FocusNode();
  final _scrollCtrl = ScrollController();
  String _type = 'info';
  int _expHours = 24;
  bool _publishing = false;

  @override
  void initState() {
    super.initState();
    AnnouncementsScreen.requestNew = _onNew;
    _load();
  }

  @override
  void dispose() {
    AnnouncementsScreen.requestNew = null;
    _msgCtrl.dispose();
    _msgFocus.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  SessionProvider get _session =>
      Provider.of<SessionProvider>(context, listen: false);
  bool get _isAdmin => _session.isAdmin;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final items = await guard(context, () => _session.api.getAnnouncements());
    if (!mounted) return;
    if (items == null) {
      setState(() {
        _loading = false;
        _error = 'Could not load announcements.';
      });
      return;
    }
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  // ---------------- composer ----------------

  void _onNew() {
    if (!_isAdmin || !mounted) return;
    _scrollCtrl.animateTo(0,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    _msgFocus.requestFocus();
  }

  Future<void> _publish() async {
    if (_publishing) return;
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) {
      showMsg(context, 'Message likhun', error: true);
      return;
    }
    if (text.length > 300) {
      showMsg(context, 'Announcement must be 300 characters or less.',
          error: true);
      return;
    }
    setState(() => _publishing = true);
    try {
      final created = await guard(
          context,
          () => _session.api.createAnnouncement(
                text: text,
                type: _type,
                expiresHours: _expHours == 0 ? null : _expHours,
              ));
      if (!mounted) return;
      if (created != null) {
        _msgCtrl.clear();
        setState(() {});
        showMsg(context, 'Published — sobai top e dekhte pabe');
        await _load();
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Widget _capsLabel(String text, bool night) {
    return Text(text,
        style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.04 * 12,
            color: night ? AppColors.nightMuted : AppColors.dayMuted));
  }

  Widget _composerCard(ThemeData theme, bool night) {
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    final tick = _tickerColors(_type, night);
    final previewText = _msgCtrl.text.trim().isEmpty
        ? 'Apnar message ekhane scroll korbe…'
        : _msgCtrl.text.trim();
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _capsLabel('MESSAGE', night),
            const SizedBox(height: 6),
            TextField(
              controller: _msgCtrl,
              focusNode: _msgFocus,
              maxLength: 300,
              maxLines: null,
              minLines: 3,
              decoration: const InputDecoration(
                hintText: 'e.g. Friday office bondho thakbe…',
                counterText: '',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (_) => setState(() {}),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${_msgCtrl.text.length} / 300',
                    style: TextStyle(fontSize: 12, color: muted)),
              ),
            ),
            const SizedBox(height: 10),
            _capsLabel('TYPE', night),
            const SizedBox(height: 6),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.4,
              children: _annTypes.map((t) {
                final active = _type == t.key;
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => _type = t.key),
                  child: Container(
                    decoration: BoxDecoration(
                      color: active
                          ? t.color.withOpacity(0.10)
                          : (night
                              ? AppColors.nightPanel
                              : Colors.white),
                      border: Border.all(
                          color: active
                              ? t.color
                              : (night
                                  ? AppColors.nightLine
                                  : AppColors.dayLine),
                          width: active ? 1.6 : 1),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: active
                          ? [
                              BoxShadow(
                                  color:
                                      const Color(0xFF4F46E5).withOpacity(0.12),
                                  blurRadius: 0,
                                  spreadRadius: 3)
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(t.icon, size: 16, color: t.color),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(t.label,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: t.color)),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            _capsLabel('SHOW FOR', night),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              value: _expHours,
              decoration: const InputDecoration(
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: const [
                DropdownMenuItem(
                    value: 0, child: Text('Until I turn it off')),
                DropdownMenuItem(value: 6, child: Text('6 hours')),
                DropdownMenuItem(value: 24, child: Text('1 day')),
                DropdownMenuItem(value: 72, child: Text('3 days')),
                DropdownMenuItem(value: 168, child: Text('1 week')),
                DropdownMenuItem(value: 720, child: Text('30 days')),
              ],
              onChanged: (v) =>
                  setState(() => _expHours = v ?? 24),
            ),
            const SizedBox(height: 14),
            _capsLabel('PREVIEW', night),
            const SizedBox(height: 6),
            Container(
              height: 42,
              decoration: BoxDecoration(
                color: tick.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: night
                        ? AppColors.nightLine
                        : AppColors.dayLine),
              ),
              padding: const EdgeInsets.only(left: 14, right: 10),
              child: Row(
                children: [
                  Icon(Icons.campaign_outlined, size: 15, color: tick.fg),
                  const SizedBox(width: 8),
                  Text('ANNOUNCEMENT',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.05 * 12,
                          color: tick.fg)),
                  Container(
                    width: 1,
                    height: 22,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    color: tick.fg.withOpacity(0.25),
                  ),
                  Expanded(
                    child: _Marquee(
                      text: previewText,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: tick.fg),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 46,
              child: ElevatedButton.icon(
                onPressed: _publishing ? null : _publish,
                icon: _publishing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send, size: 18),
                label: const Text('Publish to everyone',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- row actions ----------------

  Future<void> _toggleActive(Announcement a) async {
    final next = !(a.active ?? true);
    final res = await guard(context, () async {
      await _session.api.setAnnouncementActive(id: a.id, active: next);
      return true;
    });
    if (res == true) {
      showMsg(
          context, next ? 'Announcement activated.' : 'Announcement deactivated.');
      _load();
    }
  }

  Future<void> _delete(Announcement a) async {
    final ok = await confirmDialog(context,
        title: 'Delete announcement',
        message: 'Delete this announcement for everyone?');
    if (!ok) return;
    final res = await guard(context, () async {
      await _session.api.deleteAnnouncement(a.id);
      return true;
    });
    if (res == true) {
      showMsg(context, 'Announcement deleted.');
      _load();
    }
  }

  // ---------------- type styling ----------------

  Color _typeColor(String type) {
    for (final t in _annTypes) {
      if (t.key == type) return t.color;
    }
    return _annTypes.first.color;
  }

  Widget _typeChip(String type) {
    final color = _typeColor(type);
    final label = type.isEmpty
        ? 'Info'
        : type[0].toUpperCase() + type.substring(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }

  // ---------------- build ----------------

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return const EmptyView(
          icon: Icons.campaign_outlined,
          message: 'Announcements are admin only.');
    }
    final theme = Theme.of(context);
    final night = theme.brightness == Brightness.dark;
    if (_loading) return const LoadingView(label: 'Loading announcements…');
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        controller: _scrollCtrl,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(0, 14, 0, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Row(
                children: [
                  const Text('Announcements',
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text(
                      '${_items.length} announcement${_items.length == 1 ? '' : 's'}',
                      style: TextStyle(fontSize: 13, color: muted)),
                ],
              ),
            ),
            _composerCard(theme, night),
            Card(
              margin: const EdgeInsets.fromLTRB(12, 14, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Text('All announcements',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                  if (_items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.campaign_outlined,
                              size: 44, color: muted),
                          const SizedBox(height: 12),
                          const Text('No announcements yet',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text(
                            'Published messages scroll at the top of everyone’s screen.',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(fontSize: 13, color: muted),
                          ),
                        ],
                      ),
                    )
                  else
                    for (var i = 0; i < _items.length; i++) ...[
                      _card(theme, night, _items[i]),
                      if (i < _items.length - 1)
                        Divider(
                            height: 1,
                            indent: 16,
                            endIndent: 16,
                            color: night
                                ? AppColors.nightLine2
                                : const Color(0xFFEDEAE2)),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(ThemeData theme, bool night, Announcement a) {
    final active = a.active ?? true;
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    final now = DateTime.now().millisecondsSinceEpoch;
    final expired = a.exp != null && a.exp! > 0 && a.exp! < now;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _typeChip(a.type),
              const SizedBox(width: 8),
              if (expired)
                Chip(
                  label: const Text('expired'),
                  visualDensity: VisualDensity.compact,
                  labelStyle:
                      TextStyle(color: theme.colorScheme.error),
                ),
              if (!active && !expired)
                Chip(
                  label: const Text('inactive'),
                  visualDensity: VisualDensity.compact,
                  labelStyle: TextStyle(color: muted),
                ),
              const Spacer(),
              Switch(
                value: active,
                onChanged: (_) => _toggleActive(a),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: 'Delete announcement',
                onPressed: () => _delete(a),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(a.text, style: const TextStyle(fontSize: 15)),
          const SizedBox(height: 8),
          Text(
            'Posted ${formatRelative(a.createdAt)}'
            '${a.exp != null && a.exp! > 0 ? ' · expires ${formatDateTime(a.exp!)}' : ' · no expiry'}',
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ],
      ),
    );
  }
}
