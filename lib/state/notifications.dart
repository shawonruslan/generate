import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v27 notification center (`zedgeNotif:v27`) - stored on this device.
class NotifItem {
  NotifItem({required this.id, required this.ts, required this.kind, required this.text, required this.acc, this.read = false});
  final String id;
  final int ts;
  final String kind; // ok | err | warn | info
  final String text;
  final String acc;
  bool read;

  Map<String, dynamic> toJson() => {'id': id, 'ts': ts, 'kind': kind, 'text': text, 'acc': acc, 'read': read};

  static NotifItem? fromJson(dynamic j) {
    if (j is! Map) return null;
    return NotifItem(
      id: '${j['id'] ?? ''}',
      ts: (j['ts'] as num?)?.toInt() ?? 0,
      kind: '${j['kind'] ?? 'info'}',
      text: '${j['text'] ?? ''}',
      acc: '${j['acc'] ?? ''}',
      read: j['read'] == true,
    );
  }
}

class NotificationCenter extends ChangeNotifier {
  static const String _key = 'zedgeNotif:v27';
  final List<NotifItem> items = [];
  String filter = 'all';
  int _bellRing = 0;
  int get bellRing => _bellRing;

  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_key);
      items.clear();
      if (raw != null && raw.isNotEmpty) {
        final l = jsonDecode(raw);
        if (l is List) items.addAll(l.map(NotifItem.fromJson).whereType<NotifItem>());
      }
      // v27 welcome cleanup
      items.removeWhere((i) => i.text.contains('Welcome to Automation Hub v27'));
    } catch (_) {}
    notifyListeners();
  }

  Future<void> save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_key, jsonEncode(items.take(300).map((i) => i.toJson()).toList()));
    } catch (_) {}
  }

  static String detectKind(String text, String? kind) {
    if (kind != null && RegExp(r'^(ok|err|warn|info)$').hasMatch(kind)) return kind;
    if (RegExp(r'fail|error|❌|denied|missing', caseSensitive: false).hasMatch(text)) return 'err';
    if (RegExp(r'warn|⚠|skip', caseSensitive: false).hasMatch(text)) return 'warn';
    return 'info';
  }

  void add(String rawText, String? kind, String acc) {
    final text = rawText.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return;
    final k = detectKind(text, kind);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (items.isNotEmpty && items.first.text == text && now - items.first.ts < 5000) return;
    final id = now.toRadixString(36) + Random().nextInt(1 << 20).toRadixString(36).padLeft(4, '0').substring(0, 4);
    items.insert(0, NotifItem(id: id, ts: now, kind: k, text: text, acc: acc));
    if (items.length > 300) items.removeRange(300, items.length);
    _bellRing++;
    save();
    notifyListeners();
  }

  int get unread => items.where((i) => !i.read).length;

  void markAll() {
    for (final i in items) {
      i.read = true;
    }
    save();
    notifyListeners();
  }

  void clear() {
    items.clear();
    save();
    notifyListeners();
  }

  void setFilter(String f) {
    filter = f;
    notifyListeners();
  }

  List<NotifItem> get filtered => items.where((i) => filter == 'all' || i.kind == filter).toList();

  /// `N.ago(ts)`
  static String ago(int ts) {
    final s = ((DateTime.now().millisecondsSinceEpoch - ts) / 1000).clamp(0, double.infinity);
    if (s < 60) return 'just now';
    if (s < 3600) return '${(s / 60).floor()} min ago';
    if (s < 86400) return '${(s / 3600).floor()} h ago';
    final d = DateTime.fromMillisecondsSinceEpoch(ts + 6 * 3600 * 1000, isUtc: true);
    const mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${mon[d.month - 1]}';
  }
}
