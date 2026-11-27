import 'ringtone_models.dart';
import 'ringtone_texts.dart';

/// The workflow's text cleaners and Zedge content-policy guard, ported
/// function by function (generator.yml: cleanTitle, cleanKeywords,
/// cleanCategory, cleanDescription, zedgePolicyIssues, zedgeCleanTags,
/// zedgeEnforce).
class RingtonePolicy {
  RingtonePolicy._();

  static String _stripEdges(String s) => s
      .replaceAll(RegExp(r'''^["'*\s]+|["'*\s]+$'''), '')
      .trim();

  static String cleanTitle(String? input) {
    var raw = input ?? '';
    if (raw.isEmpty) return '';
    raw = raw
        .replaceFirst(
            RegExp(r'^(here is a title:|title:|the title is:|suggested title:)',
                caseSensitive: false),
            '')
        .trim();
    final quote = RegExp(r'"([^"\r\n]{3,60})"').firstMatch(raw);
    if (quote != null) return quote.group(1)!.trim();
    final bold = RegExp(r'\*\*([^\*\r\n]{3,60})\*\*').firstMatch(raw);
    if (bold != null) return bold.group(1)!.trim();
    final lines = raw.split('\n').map((l) => l.trim()).where((l) {
      final lower = l.toLowerCase();
      return l.isNotEmpty &&
          !lower.startsWith('here') &&
          !lower.startsWith('sure') &&
          !lower.startsWith('based') &&
          !lower.startsWith('suggest') &&
          !lower.startsWith('the') &&
          !lower.startsWith('this');
    }).toList();
    var out = lines.isNotEmpty ? _stripEdges(lines.first) : _stripEdges(raw);
    // Never V1/V2/Take 1/#1/Part 1/Mix 1 suffixes (duplicate-spam risk).
    out = out
        .replaceFirst(
            RegExp(
                r'(?:\s*[-–—:(]?\s*(?:v|ver|version|take|part|pt|mix|alt|edit|track|#)\s*\d+\)?)+$',
                caseSensitive: false),
            '')
        .replaceFirst(RegExp(r'\s+\d+$'), '')
        .trim();
    return (out.length > 28 ? out.substring(0, 28) : out).trim();
  }

  static const _stopWords = {
    'here', 'are', 'the', 'keywords', 'based', 'on', 'this', 'prompt', 'and',
    'for', 'with', 'your', 'ringtone', 'title', 'tags', 'single', 'word',
  };

  static String cleanKeywords(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final seen = <String>{};
    final out = <String>[];
    for (final m in RegExp(r'[a-zA-Z0-9]{2,20}').allMatches(raw)) {
      final w = m.group(0)!.trim();
      if (w.length <= 1 || _stopWords.contains(w.toLowerCase())) continue;
      if (seen.add(w)) out.add(w);
    }
    return out.take(10).join(', ');
  }

  static String cleanCategory(String? raw) {
    if (raw == null || raw.isEmpty) return 'OTHER';
    final upper = raw.toUpperCase();
    for (final cat in ringtoneCategories) {
      if (upper.contains(cat)) return cat;
    }
    return 'OTHER';
  }

  static String cleanDescription(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final quote = RegExp(r'"([^"\r\n]{3,100})"').firstMatch(raw);
    var text = quote != null ? quote.group(1)! : raw;
    text = text
        .replaceFirst(
            RegExp(r'^(here is a short description:|description:)',
                caseSensitive: false),
            '')
        .replaceAll(RegExp(r'''[.,!?;:"'()\[\]]+'''), ' ')
        .trim();
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final out = words.take(3).join(' ');
    return (out.length > 28 ? out.substring(0, 28) : out).trim();
  }

  static final _linkish = RegExp(
      r'[#@]|https?:|www\.|\.(com|net|org|io|app)\b',
      caseSensitive: false);

  /// Human-readable policy problems of a listing ([] = clean).
  static List<String> issues({
    String title = '',
    String tags = '',
    String description = '',
    String prompt = '',
  }) {
    final out = <String>[];
    final fields = {
      'title': title,
      'tags': tags,
      'description': description,
      'prompt': prompt,
    };
    fields.forEach((f, v) {
      if (v.isEmpty) return;
      final ip = policyIp.firstMatch(v);
      if (ip != null) out.add('$f: protected name "${ip.group(0)}"');
      final nm = policyNames.firstMatch(v);
      if (nm != null) out.add('$f: protected name "${nm.group(0)}"');
      final ad = policyAdult.firstMatch(v);
      if (ad != null) out.add('$f: adult term "${ad.group(0)}"');
      final hv = policyHarm.firstMatch(v);
      if (hv != null) out.add('$f: prohibited term "${hv.group(0)}"');
      if (f != 'prompt') {
        final pr = policyPromo.firstMatch(v);
        if (pr != null) out.add('$f: promotional/spam word "${pr.group(0)}"');
        if (_linkish.hasMatch(v)) out.add('$f: link/hashtag/handle');
      }
    });
    return out.toSet().toList();
  }

  static List<String> issuesOf(RingtoneMeta m) => issues(
      title: m.title,
      tags: m.tags,
      description: m.description,
      prompt: m.enhancedPrompt);

  static final _tagOk = RegExp(r'^[a-z0-9-]{2,20}$');

  static List<String> cleanTags(String? tags) {
    final out = <String>[];
    for (final raw in (tags ?? '').split(RegExp(r'[,\s]+'))) {
      final w = raw.trim().toLowerCase();
      if (!_tagOk.hasMatch(w)) continue;
      if (out.contains(w) ||
          policyIp.hasMatch(w) ||
          policyNames.hasMatch(w) ||
          policyAdult.hasMatch(w) ||
          policyHarm.hasMatch(w) ||
          policyPromo.hasMatch(w)) {
        continue;
      }
      out.add(w);
    }
    return out.take(10).toList();
  }

  /// Policy check + tag clean-up. Tags always end with 2..10 clean words
  /// (the category first, generic audio words as a last resort).
  static ({List<String> issues, RingtoneMeta meta}) enforce(RingtoneMeta meta) {
    final found = issuesOf(meta);
    final tags = cleanTags(meta.tags);
    const fallback = ['melody', 'tune', 'alert', 'phone', 'music', 'sound'];
    final cat = meta.category.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (cat.isNotEmpty && cat != 'other' && !tags.contains(cat)) {
      tags.insert(0, cat);
    }
    for (final w in fallback) {
      if (tags.length >= 2) break;
      if (!tags.contains(w)) tags.add(w);
    }
    return (
      issues: found,
      meta: meta.copyWith(tags: tags.take(10).join(', ')),
    );
  }
}
