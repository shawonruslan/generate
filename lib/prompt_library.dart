import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'secure_store.dart';

/// One prompt captured from a web image (Web browser -> image to prompt).
class PromptEntry {
  final String id;
  final String prompt;

  /// The image the prompt was written from.
  final String imageUrl;

  /// The page the image was found on.
  final String pageUrl;
  final int ts;

  const PromptEntry({
    required this.id,
    required this.prompt,
    required this.imageUrl,
    required this.pageUrl,
    required this.ts,
  });

  PromptEntry copyWith({String? prompt}) => PromptEntry(
        id: id,
        prompt: prompt ?? this.prompt,
        imageUrl: imageUrl,
        pageUrl: pageUrl,
        ts: ts,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'prompt': prompt,
        'imageUrl': imageUrl,
        'pageUrl': pageUrl,
        'ts': ts,
      };

  factory PromptEntry.fromJson(Map<String, dynamic> j) => PromptEntry(
        id: (j['id'] ?? '').toString(),
        prompt: (j['prompt'] ?? '').toString(),
        imageUrl: (j['imageUrl'] ?? '').toString(),
        pageUrl: (j['pageUrl'] ?? '').toString(),
        ts: (j['ts'] as num?)?.toInt() ?? 0,
      );
}

/// App-wide prompts list, kept on the device. The Web browser adds to it;
/// Batch Sets and Text to Image read from it.
class PromptLibrary extends ChangeNotifier {
  PromptLibrary._();
  static final PromptLibrary instance = PromptLibrary._();

  static const _key = 'prompt_library_v1';
  static const maxItems = 500;

  final List<PromptEntry> _items = [];
  bool _loaded = false;

  /// Newest first.
  List<PromptEntry> get items => List.unmodifiable(_items);
  int get length => _items.length;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await AppPrefs.prefs();
      final raw = p.getStringList(_key) ?? [];
      _items
        ..clear()
        ..addAll(raw.map((s) {
          try {
            return PromptEntry.fromJson(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        }).whereType<PromptEntry>());
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final p = await AppPrefs.prefs();
      await p.setStringList(
          _key, _items.map((e) => jsonEncode(e.toJson())).toList());
    } catch (_) {}
  }

  Future<PromptEntry> add(
      {required String prompt,
      required String imageUrl,
      required String pageUrl}) async {
    await load();
    final e = PromptEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      prompt: prompt.trim(),
      imageUrl: imageUrl,
      pageUrl: pageUrl,
      ts: DateTime.now().millisecondsSinceEpoch,
    );
    _items.insert(0, e);
    if (_items.length > maxItems) _items.removeRange(maxItems, _items.length);
    notifyListeners();
    await _save();
    return e;
  }

  Future<void> update(String id, String prompt) async {
    final i = _items.indexWhere((e) => e.id == id);
    if (i < 0) return;
    _items[i] = _items[i].copyWith(prompt: prompt.trim());
    notifyListeners();
    await _save();
  }

  Future<void> remove(String id) async {
    _items.removeWhere((e) => e.id == id);
    notifyListeners();
    await _save();
  }

  Future<void> removeAll(Iterable<String> ids) async {
    final set = ids.toSet();
    _items.removeWhere((e) => set.contains(e.id));
    notifyListeners();
    await _save();
  }

  Future<void> clear() async {
    _items.clear();
    notifyListeners();
    await _save();
  }
}
