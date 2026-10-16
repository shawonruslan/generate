import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/constants.dart';

/// v22 AI METADATA SIDECAR JSON.
/// Drop a .json next to your media (or load it via the bar). Every uploaded
/// file whose name matches an entry gets title/tags/category/description
/// saved into Firebase immediately, so generator.yml skips Gemini for it.
class MetaEntry {
  MetaEntry({required this.file, required this.title, required this.tags, required this.category, required this.description});
  final String file;
  final String title;
  final String tags;
  final String category;
  final String description;
  int used = 0;
  final Set<String> keys = {};
}

class MetaParseResult {
  const MetaParseResult(this.added, this.problems);
  final int added;
  final List<String> problems;
}

/// Metadata fields returned for a queue record (`zMetaFields`).
class MetaFields {
  const MetaFields({this.title = '', this.tags = '', this.category = '', this.description = '', this.matched = false, this.source, this.appliedAt});
  final String title, tags, category, description;
  final bool matched;
  final String? source;
  final int? appliedAt;

  Map<String, dynamic> toPayload() {
    final m = <String, dynamic>{'title': title, 'tags': tags, 'category': category, 'description': description};
    if (matched) {
      m['metadataSource'] = 'json';
      m['metadataFile'] = source ?? 'metadata.json';
      m['metadataAppliedAt'] = appliedAt ?? DateTime.now().millisecondsSinceEpoch;
    }
    return m;
  }
}

String zMetaNorm(String? name) {
  var s = (name ?? '').split(RegExp(r'[\\/]')).last.toLowerCase();
  s = s.replaceFirst(RegExp(r'\.[a-z0-9]{2,5}$'), '');
  s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  return s.replaceAll(RegExp(r'^_+|_+$'), '');
}

String zMetaPathNorm(String? p) {
  var s = (p ?? '').replaceAll('\\', '/').replaceFirst(RegExp(r'^\.?/+'), '').toLowerCase();
  s = s.replaceFirst(RegExp(r'\.[a-z0-9]{2,5}$'), '');
  s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  return s.replaceAll(RegExp(r'^_+|_+$'), '');
}

List<String> zMetaTags(dynamic t) {
  final arr = t is List ? t.map((e) => '$e').toList() : (t ?? '').toString().split(RegExp(r'[,;\n|]'));
  final seen = <String>{};
  final out = <String>[];
  for (var x in arr) {
    x = x.trim().replaceFirst(RegExp(r'^#'), '').replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    if (x.isEmpty || x.length > 30 || seen.contains(x)) continue;
    seen.add(x);
    out.add(x);
    if (out.length >= 10) break;
  }
  return out;
}

class MetaBook extends ChangeNotifier {
  final Map<String, MetaEntry> entries = {};
  final List<MetaEntry> list = [];
  final Set<String> dups = {};
  String source = '';
  final List<String> problems = [];
  int applied = 0;
  final List<String> missed = [];

  bool get isEmpty => list.isEmpty;

  MetaParseResult parse(String text, String sourceName) {
    dynamic data = jsonDecode(text);
    if (data is Map) {
      if (data['files'] is List) {
        data = data['files'];
      } else if (data['items'] is List) {
        data = data['items'];
      } else {
        data = data.entries.map((e) => {'file': e.key, ...(e.value is Map ? Map<String, dynamic>.from(e.value as Map) : <String, dynamic>{})}).toList();
      }
    }
    if (data is! List) throw const FormatException('JSON must be an array of { file, title, tags, category, description }');
    final probs = <String>[];
    var added = 0;
    for (var i = 0; i < data.length; i++) {
      final row = data[i];
      if (row is! Map) continue;
      final file = row['file'] ?? row['filename'] ?? row['fileName'] ?? row['name'];
      if (file == null || '$file'.isEmpty) {
        probs.add('#${i + 1}: missing "file"');
        continue;
      }
      var title = '${row['title'] ?? ''}'.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (title.length > 30) title = title.substring(0, 30);
      final tags = zMetaTags(row['tags']);
      final category = '${row['category'] ?? ''}'.trim().toUpperCase().replaceAll(RegExp(r'[\s&\-]+'), '_').replaceAll(RegExp(r'[^A-Z_]'), '');
      var description = '${row['description'] ?? ''}'.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (description.length > 200) description = description.substring(0, 200);
      final issues = <String>[];
      if (title.isEmpty) issues.add('title missing');
      if (tags.length < 2) issues.add('needs 2-10 tags');
      if (description.isEmpty) issues.add('description missing');
      if (kMetaPolicyRe.hasMatch('$title ${tags.join(' ')} $description')) issues.add('Zedge policy: promo/link/adult wording');
      if (issues.isNotEmpty) {
        probs.add('$file: ${issues.join(', ')}');
        continue;
      }
      final ent = MetaEntry(file: '$file', title: title, tags: tags.join(', '), category: category, description: description);
      ent.keys.add(zMetaNorm('$file'));
      final fp = '$file'.replaceAll('\\', '/');
      if (fp.contains('/')) {
        ent.keys.add(zMetaPathNorm(fp));
        final parts = fp.split('/');
        if (parts.length >= 2) ent.keys.add(zMetaNorm('${parts[parts.length - 2]}.x'));
      }
      final folder = row['folder'] ?? row['dir'] ?? row['directory'];
      if (folder != null && '$folder'.isNotEmpty) ent.keys.add(zMetaNorm('${'$folder'.replaceFirst(RegExp(r'[\\/]+$'), '')}.x'));
      final k = zMetaNorm('$file');
      if (entries.containsKey(k)) {
        dups.add(k);
      } else {
        entries[k] = ent;
      }
      list.add(ent);
      added++;
    }
    source = sourceName.isEmpty ? 'metadata.json' : sourceName;
    if (dups.isNotEmpty) probs.add('${dups.length} file name(s) repeated in JSON (e.g. "${dups.first}") - matched by folder name / order instead');
    problems.addAll(probs);
    notifyListeners();
    return MetaParseResult(added, probs);
  }

  /// names: candidate file names (first match wins).
  MetaFields fields(List<String?> names, String? contentType) {
    if (list.isEmpty) return const MetaFields();
    final cands = names.where((n) => n != null && n.isNotEmpty).map((n) => n!).toList();
    MetaEntry? e;
    // 1) unique file name
    for (final n in cands) {
      final k = zMetaNorm(n);
      if (!dups.contains(k) && entries[k] != null) {
        e = entries[k];
        break;
      }
    }
    // 2) full path / parent folder name
    if (e == null) {
      for (final n in cands) {
        final fp = n.replaceAll('\\', '/');
        final pk = zMetaPathNorm(fp);
        final parts = fp.split('/');
        final dir = fp.contains('/') && parts.length >= 2 ? zMetaNorm('${parts[parts.length - 2]}.x') : '';
        e = list.cast<MetaEntry?>().firstWhere((x) => x!.used == 0 && (x.keys.contains(pk) || (dir.isNotEmpty && x.keys.contains(dir))), orElse: () => null);
        if (e == null && dir.length >= 3) {
          e = list.cast<MetaEntry?>().firstWhere((x) => x!.used == 0 && x.keys.any((k) => k.length >= 3 && (k.startsWith(dir) || dir.startsWith(k))), orElse: () => null);
        }
        if (e != null) break;
      }
    }
    // 3) repeated file names in JSON -> hand them out in JSON order
    if (e == null) {
      for (final n in cands) {
        final k = zMetaNorm(n);
        if (dups.contains(k)) {
          e = list.cast<MetaEntry?>().firstWhere((x) => x!.used == 0 && x.keys.contains(k), orElse: () => null);
          if (e != null) break;
        }
      }
    }
    if (e == null && dups.isNotEmpty && list.isNotEmpty && list.every((x) => dups.contains(zMetaNorm(x.file)))) {
      e = list.cast<MetaEntry?>().firstWhere((x) => x!.used == 0, orElse: () => null);
    }
    if (e == null) {
      if (cands.isNotEmpty) missed.add(cands.first);
      notifyListeners();
      return const MetaFields();
    }
    e.used++;
    final catList = contentType == 'RINGTONE' ? kZedgeRingtoneCategories : kZedgeImageCategories;
    final category = catList.contains(e.category) ? e.category : 'OTHER';
    if (category != e.category) {
      problems.add('${e.file}: category "${e.category.isEmpty ? '(empty)' : e.category}" not valid for ${contentType ?? 'this type'} -> OTHER');
    }
    applied++;
    notifyListeners();
    return MetaFields(
      title: e.title,
      tags: e.tags,
      category: category,
      description: e.description,
      matched: true,
      source: source,
      appliedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  void clear() {
    entries.clear();
    list.clear();
    dups.clear();
    source = '';
    problems.clear();
    applied = 0;
    missed.clear();
    notifyListeners();
  }

  /// Status line shown in the "AI metadata JSON" bar (`zMetaRender`).
  String get statusText {
    final n = list.length;
    if (n == 0) return 'none loaded · drop a .json together with your files, or Load JSON. Files without JSON still get Gemini metadata from generator.yml.';
    final b = StringBuffer('$source · $n file${n == 1 ? '' : 's'} ready');
    if (applied > 0) b.write(' · $applied applied');
    if (missed.isNotEmpty) b.write(' · ${missed.length} uploaded without JSON match');
    if (problems.isNotEmpty) b.write(' · ${problems.length} warning(s)');
    return b.toString();
  }

  static String promptText() => [
        'I will give you media files for Zedge (ringtones / wallpapers / live wallpapers / charging animations).',
        'For EACH file produce metadata and return ONE JSON array only (no prose, no markdown) in exactly this shape:',
        '[',
        '  { "file": "exact_file_name.mp3", "title": "Catchy Title (max 30 chars)", "tags": ["tag1","tag2","tag3","tag4","tag5"], "category": "CATEGORY", "description": "1-2 natural sentences describing the content" }',
        ']',
        'Rules (Zedge Content Policy - mandatory):',
        '- "file" must be the exact file name I upload (extension included) and UNIQUE per entry - never reuse the same file name. If files sit in sub-folders, use the relative path (e.g. 01_basalt_cross/wallpaper.jpg) or add a "folder" field. For a wallpaper set (24H / Dual / Battery) use the FIRST image\'s file name.',
        '- title: original, descriptive, max 30 characters, no emojis, no ALL CAPS, no artist/brand/movie/game/character names, no copyrighted names.',
        '- tags: 2 to 10 lowercase tags, each 1-3 words, accurate to the content only. No promo words, no links, no @handles, no unrelated trending words.',
        "- description: accurate, 1-2 sentences, no links, no social handles, no 'download/subscribe/follow', no pricing.",
        '- No sexual, suggestive, violent, hateful, illegal or misleading wording anywhere.',
        '- category for RINGTONES must be one of: ${kZedgeRingtoneCategories.where((c) => c != 'OTHER').join(', ')}',
        '- category for WALLPAPERS / LIVE WALLPAPERS / CHARGING ANIMATIONS must be one of: ${kZedgeImageCategories.where((c) => c != 'OTHER').join(', ')}',
        'Save the result as metadata.json.',
      ].join('\n');
}
