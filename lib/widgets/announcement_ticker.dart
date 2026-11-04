import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../providers/app_state.dart';
import '../utils/format.dart';

/// Web-parity announcement ticker banner.
///
/// Mirrors the web app's `.ticker` (index-12.html, v6): a flat colored strip
/// under the topbar showing the active announcements as an auto-scrolling
/// marquee, with a label, per-type icons, relative times, pause-on-hover,
/// an X dismiss button (persisted in SharedPreferences), and tap-to-open.
///
/// Severity rank (web ANN_RANK): urgent > warning > info > success — the
/// banner color follows the highest severity currently visible.
class AnnouncementTicker extends StatefulWidget {
  final VoidCallback? onTap;
  const AnnouncementTicker({super.key, this.onTap});

  @override
  State<AnnouncementTicker> createState() => _AnnouncementTickerState();
}

class _AnnouncementTickerState extends State<AnnouncementTicker> {
  static const _prefsKey = 'dismissed_announcements';
  // Web ANN_RANK = ['success','info','warning','urgent'] — higher wins.
  static const _rank = {'success': 0, 'info': 1, 'warning': 2, 'urgent': 3};

  Set<String> _dismissed = {};
  final ScrollController _ctrl = ScrollController();
  final GlobalKey _copyKey = GlobalKey();
  Timer? _timer;
  bool _paused = false;
  String _scrollIds = '';

  @override
  void initState() {
    super.initState();
    _loadDismissed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadDismissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        _dismissed = list.map((e) => e.toString()).toSet();
      }
    } catch (_) {
      // Corrupt prefs — start fresh.
    }
    if (mounted) setState(() {});
  }

  List<Announcement> _visible(List<Announcement> all) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return all
        .where((a) =>
            !_dismissed.contains(a.id) && (a.exp == null || a.exp! > now))
        .toList();
  }

  String _topType(List<Announcement> items) {
    var top = 'info';
    var topRank = -1;
    for (final a in items) {
      final r = _rank[a.type] ?? 1;
      if (r > topRank) {
        topRank = r;
        top = _rank.containsKey(a.type) ? a.type : 'info';
      }
    }
    return top;
  }

  /// Flat web-exact ticker colors (no gradients). (bg, fg).
  ({Color bg, Color fg}) _colors(String type, bool night) {
    switch (type) {
      case 'success':
        return night
            ? (bg: const Color(0xFF0F2E22), fg: const Color(0xFF86EFAC))
            : (bg: const Color(0xFFECFDF5), fg: const Color(0xFF065F46));
      case 'warning':
        return night
            ? (bg: const Color(0xFF3A2A06), fg: const Color(0xFFFCD34D))
            : (bg: const Color(0xFFFFFBEB), fg: const Color(0xFF92400E));
      case 'urgent':
        return night
            ? (bg: const Color(0xFF3B1111), fg: const Color(0xFFFCA5A5))
            : (bg: const Color(0xFFFEF2F2), fg: const Color(0xFF991B1B));
      case 'info':
      default:
        return night
            ? (bg: const Color(0xFF2B3242), fg: const Color(0xFFC7D2FE))
            : (bg: const Color(0xFFEEF2FF), fg: const Color(0xFF3730A3));
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'success':
        return Icons.check_circle_outline;
      case 'warning':
        return Icons.warning_amber_outlined;
      case 'urgent':
        return Icons.notifications_outlined;
      case 'info':
      default:
        return Icons.info_outline;
    }
  }

  Widget _item(Announcement a, Color fg) {
    return Padding(
      padding: const EdgeInsets.only(right: 56),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_typeIcon(a.type), size: 14, color: fg.withOpacity(0.8)),
          const SizedBox(width: 8),
          Text(a.text,
              style: TextStyle(
                  color: fg, fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          Text('· ${formatRelative(a.createdAt)}',
              style:
                  TextStyle(color: fg.withOpacity(0.65), fontSize: 12)),
        ],
      ),
    );
  }

  double? _copyWidth() {
    final box =
        _copyKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.size.width;
  }

  void _afterLayout(String idsKey) {
    if (!mounted || !_ctrl.hasClients) return;
    final copyWidth = _copyWidth();
    if (idsKey != _scrollIds) {
      _scrollIds = idsKey;
      _ctrl.jumpTo(0);
    }
    // Seamless loop needs the viewport to fit inside one copy.
    final maxExtent = _ctrl.position.maxScrollExtent;
    final seamless =
        copyWidth != null && copyWidth > 0 && maxExtent >= copyWidth;
    if (seamless) {
      _timer ??= Timer.periodic(
          const Duration(milliseconds: 30), (_) => _tick(copyWidth));
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _tick(double copyWidth) {
    if (!mounted || _paused || !_ctrl.hasClients) return;
    final next = _ctrl.offset + 1.8; // ~60 px/s
    if (next >= copyWidth) {
      _ctrl.jumpTo(next - copyWidth);
    } else {
      _ctrl.jumpTo(next);
    }
  }

  Future<void> _dismiss() async {
    final all =
        context.read<SessionProvider>().drive?.announcements ?? const <Announcement>[];
    final ids = _visible(all).map((a) => a.id).toList();
    if (ids.isEmpty) return;
    final merged = <String>[..._dismissed];
    for (final id in ids) {
      if (!merged.contains(id)) merged.add(id);
    }
    // Web keeps the last 100 dismissed ids.
    final capped =
        merged.length > 100 ? merged.sublist(merged.length - 100) : merged;
    if (mounted) setState(() => _dismissed = capped.toSet());
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(capped));
    } catch (_) {
      // Dismiss still applies for this session.
    }
  }

  @override
  Widget build(BuildContext context) {
    final night = Theme.of(context).brightness == Brightness.dark;
    final all =
        context.watch<SessionProvider>().drive?.announcements ?? const <Announcement>[];
    final items = _visible(all);
    if (items.isEmpty) {
      _timer?.cancel();
      _timer = null;
      return const SizedBox.shrink();
    }
    final top = _topType(items);
    final c = _colors(top, night);
    final idsKey = items.map((a) => a.id).join('|');
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterLayout(idsKey));

    final label =
        items.length > 1 ? 'Announcements (${items.length})' : 'Announcement';
    return Container(
      height: 42,
      color: c.bg,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 4),
            child: Container(
              padding: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                border: Border(
                    right: BorderSide(color: c.fg.withOpacity(0.25))),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                      top == 'urgent'
                          ? Icons.notifications_outlined
                          : Icons.campaign_outlined,
                      size: 14,
                      color: c.fg),
                  const SizedBox(width: 8),
                  Text(label.toUpperCase(),
                      style: TextStyle(
                          color: c.fg,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6)),
                ],
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: MouseRegion(
                onEnter: (_) => _paused = true,
                onExit: (_) => _paused = false,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  controller: _ctrl,
                  physics: const NeverScrollableScrollPhysics(),
                  child: Row(
                    children: [
                      Row(key: _copyKey, children: [
                        for (final a in items) _item(a, c.fg),
                      ]),
                      Row(children: [
                        for (final a in items) _item(a, c.fg),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: c.fg.withOpacity(0.6),
            tooltip: 'Dismiss',
            onPressed: _dismiss,
          ),
        ],
      ),
    );
  }
}
