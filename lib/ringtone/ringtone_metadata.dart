import 'dart:convert';
import 'dart:math';

import 'ringtone_models.dart';
import 'ringtone_policy.dart';
import 'ringtone_pools.dart';
import 'ringtone_texts.dart';

/// Sends one text prompt to Gemini and returns the reply.
typedef RingtoneAsker = Future<String> Function(String prompt);

/// Gemini answered, but without the tags the pipeline needs.
class RingtoneMetadataException implements Exception {
  final String message;
  const RingtoneMetadataException(this.message);
  @override
  String toString() => message;
}

/// The workflow's prompt + listing-text engine, ported from
/// generator.yml (`generateMetadataFromPrompt`,
/// `generateUniqueTakeMetadatas`, `drawPath`, `pickFresh`,
/// `rememberConcept`).
///
/// One engine lives for the whole app run so the variety state (theme
/// deck, used pool items, recent concepts) carries from one batch to
/// the next - that is what keeps a 100-tone run from repeating itself.
class RingtoneMetadataEngine {
  final RingtoneAsker ask;
  final Random _rnd;

  RingtoneMetadataEngine(this.ask, {Random? random})
      : _rnd = random ?? Random();

  final List<String> _pathDeck = [];
  final Set<String> _usedThemeItems = {};

  /// `"Title" — first 70 chars of the prompt`, newest last, max 12.
  final List<String> recentConcepts = [];

  /// Called with a line for the studio log.
  void Function(String line)? onLog;

  void _log(String s) => onLog?.call(s);

  static const themePaths = [
    'Musical', 'Animal', 'Comedy', 'SciFi', 'Situation', 'SmartTopic',
    'Horror', 'Sports', 'Romance', 'Cultural', 'Kids', 'ASMR', 'Epic',
    'Urban', 'Nature',
  ];

  String _drawPath() {
    if (_pathDeck.isEmpty) {
      _pathDeck.addAll([...themePaths]..shuffle(_rnd));
    }
    return _pathDeck.removeLast();
  }

  String _pickFresh(String poolName) {
    final pool = ringtonePools[poolName]!;
    var fresh = [
      for (final x in pool)
        if (!_usedThemeItems.contains('$poolName:$x')) x
    ];
    if (fresh.isEmpty) {
      for (final x in pool) {
        _usedThemeItems.remove('$poolName:$x');
      }
      fresh = pool;
    }
    final item = fresh[_rnd.nextInt(fresh.length)];
    _usedThemeItems.add('$poolName:$item');
    return item;
  }

  String _any(String poolName) {
    final pool = ringtonePools[poolName]!;
    return pool[_rnd.nextInt(pool.length)];
  }

  void rememberConcept(String title, String enhancedPrompt) {
    final cut =
        enhancedPrompt.length > 70 ? enhancedPrompt.substring(0, 70) : enhancedPrompt;
    recentConcepts.add('"$title" — $cut');
    if (recentConcepts.length > 12) recentConcepts.removeAt(0);
  }

  String _theme(String path) {
    final p = _pickFresh;
    switch (path) {
      case 'Musical':
        return 'Style: ${p('genres')} | Lead: ${p('instruments')} | Mood: ${p('moods')}';
      case 'Animal':
        return 'Type: Animal Sound (Musical Translation) | Focus: ${p('animals')} | Mood: ${p('moods')}';
      case 'Comedy':
        return 'Type: Comedy/Funny | Sound: ${p('comedy')} | Character: ${p('moods')}';
      case 'SciFi':
        return 'Type: Sci-Fi / Futuristic | Element: ${p('sciFi')} | Vibe: ${p('moods')}';
      case 'Situation':
        return 'Purpose: ${p('situations')} | Atmosphere: ${p('moods')}';
      case 'SmartTopic':
        return 'Creative Topic: ${p('adjectives')} ${p('topics')} ${p('actions')}';
      case 'Horror':
        return 'Type: Horror/Suspense | Sound: ${p('horror')} | Mood: ${p('moods')}';
      case 'Sports':
        return 'Type: Sports/Action | Sound: ${p('sports')} | Energy: ${p('moods')}';
      case 'Romance':
        return 'Type: Romantic/Emotional | Theme: ${p('romance')} | Mood: ${p('moods')}';
      case 'Cultural':
        return 'Type: World/Cultural Music | Style: ${p('cultural')} | Mood: ${p('moods')}';
      case 'Kids':
        return 'Type: Children/Playful | Theme: ${p('kids')} | Mood: Joyful and Energetic';
      case 'ASMR':
        return 'Type: ASMR/Relaxing Sounds | Sound: ${p('asmr')} | Texture: Ultra HD, highly detailed';
      case 'Epic':
        return 'Type: Epic/Cinematic | Theme: ${p('epic')} | Scale: Grand and Powerful';
      case 'Urban':
        return 'Type: Urban/Street | Vibe: ${p('urban')} | Mood: ${p('moods')}';
      default:
        return 'Type: Nature Soundscape | Element: ${p('nature')} | Intensity: High';
    }
  }

  static bool _set(String v) => v.trim().isNotEmpty && v.trim() != 'Auto';

  static String get validCategories =>
      ringtoneCategories.where((c) => c != 'OTHER').join(', ');

  String _salt() =>
      _rnd.nextInt(1 << 31).toRadixString(36).padLeft(6, '0').substring(0, 6);

  /// The full text sent to Gemini for [prompt] ('' = invent a concept).
  /// Split out of [generate] so tests can inspect it.
  ({String text, RingtoneChosen chosen}) buildPrompt(String prompt, RingtoneConfig cfg) {
    final durSec = cfg.lengthSeconds.clamp(1, 60);
    final isShort = cfg.isShort;
    final soundTypeLabel = isShort
        ? 'Short Notification/Alert Tone'
        : (cfg.soundType == 'Alarm'
            ? 'Progressive Wake-up Alarm Tone'
            : 'Full Melodic Ringtone');

    final selectedPath = _drawPath();
    final mandatoryTheme = _theme(selectedPath);
    final genre =
        _set(cfg.genre) ? cfg.genre : '$selectedPath ($mandatoryTheme)';
    final inst =
        _set(cfg.instruments) ? cfg.instruments : _pickFresh('instruments');
    final mood = _set(cfg.mood) ? cfg.mood : _pickFresh('moods');
    final bpm = cfg.bpm > 0 ? '${cfg.bpm} BPM' : _any('tempos');
    final key =
        _set(cfg.musicalKey) ? cfg.musicalKey : 'Clean Harmonic Major/Minor Key';
    final struct = _set(cfg.structure) ? cfg.structure : _any('structures');
    final prod = cfg.production.trim().isNotEmpty
        ? cfg.production.trim()
        : _any('productions');
    final neg = cfg.negativePrompt.trim().isNotEmpty
        ? cfg.negativePrompt
        : defaultNegativePrompt;
    final banned = cfg.bannedWords.trim().isNotEmpty
        ? cfg.bannedWords
        : defaultBannedWords;
    final salt = _salt();

    final craftRules = isShort
        ? 'CRAFT RULES for a premium NOTIFICATION sound (${durSec}s):\n'
            '- Design ONE memorable 2-4 note motif with a clean, bright attack and a smooth natural decay.\n'
            '- Pleasant to hear 100 times a day: no harsh, shrill, or startling frequencies.\n'
            '- ZERO IMITATION: Never imitate default iPhone, Samsung, Nokia, or Pixel tones.\n'
            '- Name the real instrument ($inst), exact articulation (plucked, struck, warm chime), and decay feel.'
        : 'CRAFT RULES for a chart-topping RINGTONE (${durSec}s):\n'
            '- The melodic hook must be instantly recognizable within the FIRST 2 SECONDS.\n'
            '- Clear, musical melody at $bpm featuring $inst in $key.\n'
            '- ZERO IMITATION: Never imitate stock phone ringtones from Apple, Samsung, Nokia, or Motorola.\n'
            '- CRITICAL FULL DURATION: Music MUST start immediately at 0.0s and stay active continuously for the ENTIRE ${durSec}s — NO silent intro, NO early fade-out, NO trailing silence.\n'
            '- Must cut through on a phone speaker (strong clear mids, crisp highs, no muddy sub-bass).';

    final rendererRules =
        'AUDIO RENDERER FACTS (the ENHANCED_PROMPT is sent to Stable Audio 2.5 text-to-music model for ${durSec}s):\n'
        '- Renders musical instruments, genres, rhythm, BPM, harmony, and studio textures with high fidelity.\n'
        '- Cannot render realistic human speech, lyrics, or raw unmusical foley — always translate concepts into musical instruments.\n'
        '- TITLE, KEYWORDS and DESCRIPTION must describe ONLY what the ENHANCED_PROMPT literally sounds like.';

    final noveltyBlock = recentConcepts.isNotEmpty
        ? 'ALREADY GENERATED IN THIS SESSION (make your new concept completely distinct):\n'
            '${[
            for (var i = 0; i < recentConcepts.length; i++)
              '${i + 1}. ${recentConcepts[i]}'
          ].join('\n')}\n'
        : '';

    final ideaBlock = prompt.isNotEmpty
        ? 'User Prompt Idea: "$prompt"\nRewrite and enrich this idea into a vivid, studio-grade 25-to-35-word text-to-music prompt incorporating the Featured Instruments ($inst), Tempo ($bpm), Mood ($mood), Key ($key), and Production ($prod). [Salt: $salt]'
        : 'Invent a fresh, sellable 25-to-35-word text-to-music prompt for a $soundTypeLabel featuring $inst in a $genre style with a $mood mood at $bpm in $key, built around $struct with $prod.\n$noveltyBlock[Salt: $salt]';

    final template =
        cfg.masterPrompt.trim().isNotEmpty ? cfg.masterPrompt : defaultMasterPrompt;
    final values = {
      'ZEDGE_POLICY_RULES': zedgePolicyRules,
      'RENDERER_RULES': rendererRules,
      'CRAFT_RULES': craftRules,
      'SOUND_TYPE': soundTypeLabel,
      'DURATION': '$durSec',
      'BPM': bpm,
      'INSTRUMENTS': inst,
      'GENRE': genre,
      'MOOD': mood,
      'KEY': key,
      'STRUCTURE': struct,
      'PRODUCTION': prod,
      'NEGATIVE_PROMPT': neg,
      'BANNED_WORDS': banned,
      'VALID_CATEGORIES': validCategories,
      'IDEA': ideaBlock,
    };
    // Single pass, so a value that happens to contain `{{...}}` (a user
    // prompt, say) is never expanded a second time.
    final text = template.replaceAllMapped(RegExp(r'\{\{([A-Z_]+)\}\}'),
        (m) => values[m.group(1)] ?? m.group(0)!);
    return (
      text: text,
      chosen: RingtoneChosen(inst: inst, bpm: bpm, key: key, prod: prod),
    );
  }

  /// Tolerant `[TAG] value [/TAG]` reader (workflow `getTagValue`).
  static String tagValue(String text, String tag) {
    final t = tag.replaceAll('_', r'[_ \-]?');
    final open =
        RegExp('\\[\\s*$t\\s*\\]\\s*:?', caseSensitive: false).firstMatch(text);
    if (open == null) return '';
    var rest = text.substring(open.end);
    final close = RegExp('\\[\\s*/\\s*$t\\s*\\]', caseSensitive: false)
        .firstMatch(rest);
    if (close != null) {
      rest = rest.substring(0, close.start);
    } else {
      final nx = RegExp(
              r'\[\s*/?\s*(ENHANCED[_ -]?PROMPT|TITLE|KEYWORDS|CATEGORY|DESCRIPTION|POLICY)\s*\]',
              caseSensitive: false)
          .firstMatch(rest);
      if (nx != null) rest = rest.substring(0, nx.start);
    }
    rest = rest
        .replaceAll('**', '')
        .replaceAll(RegExp(r'^`+|`+$'), '')
        .replaceFirst(RegExp(r'^\s*:\s*'), '')
        .trim();
    return RegExp(r'^(\.{3}|\u2026)$').hasMatch(rest) ? '' : rest;
  }

  /// One Gemini round: enhanced Stable Audio prompt + title, tags,
  /// category and description for [prompt] ('' = smart auto concept).
  Future<RingtoneMeta> generate(String prompt, RingtoneConfig cfg) async {
    prompt = prompt.trim();
    final built = buildPrompt(prompt, cfg);
    final reply = await ask(built.text);

    final r0 = tagValue(reply, 'ENHANCED_PROMPT');
    final r1 = tagValue(reply, 'TITLE');
    final r2 = tagValue(reply, 'KEYWORDS');
    final r3 = tagValue(reply, 'CATEGORY');
    final r4 = tagValue(reply, 'DESCRIPTION');

    final missing = <String>[];
    if (r0.isEmpty ||
        r0.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length < 4) {
      missing.add('ENHANCED_PROMPT');
    }
    if (r1.isEmpty) missing.add('TITLE');
    if (r2.isEmpty) missing.add('KEYWORDS');
    if (missing.isNotEmpty) {
      throw RingtoneMetadataException(
          'Gemini reply incomplete (missing ${missing.join(', ')}) - regenerating');
    }

    var enhanced = r0.replaceAll(RegExp(r'''^["']|["']$'''), '').trim();
    if (prompt.isNotEmpty && !cfg.useGeminiEnhancer) {
      final c = built.chosen;
      final extras = [c.inst, c.bpm, c.key, c.prod]
          .where((s) => s.isNotEmpty && s != 'Auto')
          .join(', ');
      enhanced = extras.isNotEmpty ? '$prompt, $extras' : prompt;
    }

    var title = RingtonePolicy.cleanTitle(r1);
    if (title.isEmpty) {
      final words =
          (prompt.isNotEmpty ? prompt : 'Studio Tone').split(' ').take(4).join(' ');
      title = words.length > 28 ? words.substring(0, 28) : words;
    }
    final desc = RingtonePolicy.cleanDescription(r4);
    rememberConcept(title, enhanced);
    return RingtoneMeta(
      enhancedPrompt: enhanced,
      title: title,
      tags: RingtonePolicy.cleanKeywords(r2),
      category: RingtonePolicy.cleanCategory(r3),
      description: desc.isNotEmpty ? desc : title,
    );
  }

  /// [generate] with the workflow's three policy-checked attempts.
  Future<RingtoneMeta> generateCompliant(String prompt, RingtoneConfig cfg,
      {void Function(int attempt)? onAttempt, bool Function()? cancelled}) async {
    Object? last;
    for (var attempt = 1; attempt <= 3; attempt++) {
      if (cancelled?.call() ?? false) break;
      onAttempt?.call(attempt);
      try {
        final candidate = await generate(prompt, cfg);
        final check = RingtonePolicy.enforce(candidate);
        if (check.issues.isNotEmpty) {
          last = 'policy: ${check.issues.join('; ')}';
          _log('Policy check (attempt $attempt/3): ${check.issues.join('; ')} - regenerating');
          continue;
        }
        return check.meta;
      } on RingtoneMetadataException catch (e) {
        last = e;
        _log('Metadata attempt $attempt/3 failed: $e');
      } catch (e) {
        // A session / network failure will not heal by asking again
        // with the same broken session - surface it as it is.
        if (attempt == 3 || _isFatal(e)) rethrow;
        last = e;
        _log('Metadata attempt $attempt/3 failed: $e');
      }
    }
    throw RingtoneMetadataException(
        'Could not generate policy-compliant metadata after 3 attempts'
        '${last == null ? '' : ' ($last)'}');
  }

  static bool _isFatal(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('sign in') ||
        s.contains('signed in') ||
        s.contains('session') ||
        s.contains('cookie');
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();

  static List<String> _wordsOf(String s) =>
      _norm(s).split(' ').where((w) => w.length > 2).toList();

  static List<String> _tagList(String s) => s
      .split(',')
      .map((w) => w.trim().toLowerCase())
      .where((w) => w.isNotEmpty)
      .toList();

  /// A different title, tag list and 2-3 word description for every
  /// take of one render (marketplaces reject near-identical listings).
  /// Never fails: slots Gemini could not fill get deterministic,
  /// duplicate-free fallbacks.
  Future<List<RingtoneMeta>> uniqueTakes(
      RingtoneMeta base, int totalTakes, RingtoneConfig cfg) async {
    final firstTitle = RingtonePolicy.cleanTitle(base.title);
    final firstDesc = RingtonePolicy.cleanDescription(base.description);
    final first = base.copyWith(
      title: firstTitle.isNotEmpty ? firstTitle : 'Fresh Studio Tone',
      description: firstDesc.isNotEmpty
          ? firstDesc
          : firstTitle.split(' ').take(3).join(' '),
    );
    if (totalTakes <= 1) return [first];

    final banned = cfg.bannedWords.trim().isNotEmpty
        ? cfg.bannedWords
        : defaultBannedWords;
    final shape = cfg.audioShape.toLowerCase();
    final musicalKey = cfg.musicalKey.trim();
    final recentTitles = [
      for (final c in recentConcepts) c.split(' — ').first
    ].where((t) => t.isNotEmpty);

    final results = <RingtoneMeta>[first];
    // Insertion-ordered (LinkedHashSet), like the JS Set.
    final usedTitles = <String>{_norm(first.title), ...recentTitles.map(_norm)};
    final usedDescs = <String>{_norm(first.description)};
    final usedDescWords = <String>{..._wordsOf(first.description)};
    final usedTags = <String>{..._tagList(first.tags)};

    String distinctTags(String raw, int takeIdx, String category) {
      final catTag = category.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
      final incoming = _tagList(raw);
      final picked = <String>[];
      for (final w in incoming) {
        if (picked.length >= 10) break;
        if (!usedTags.contains(w) && !picked.contains(w)) picked.add(w);
      }
      var shared = 0;
      for (final w in incoming) {
        if (picked.length >= 10 || shared >= 2) break;
        if (!picked.contains(w)) {
          picked.add(w);
          shared++;
        }
      }
      final bank = [
        ...freshTagBanks[takeIdx % freshTagBanks.length],
        ...freshTagBanks[(takeIdx + 1) % freshTagBanks.length],
      ]..shuffle(_rnd);
      for (final w in bank) {
        if (picked.length >= 9) break;
        if (!picked.contains(w) && !usedTags.contains(w)) picked.add(w);
      }
      if (catTag.isNotEmpty &&
          catTag != 'other' &&
          !picked.contains(catTag) &&
          picked.length < 10) {
        picked.insert(0, catTag);
      }
      final out = picked.take(10).toList();
      usedTags.addAll(out);
      return out.join(', ');
    }

    bool descTooSimilar(String desc) {
      final n = _norm(desc);
      if (n.isEmpty || usedDescs.contains(n)) return true;
      final ws = _wordsOf(desc);
      final shared = ws.where(usedDescWords.contains).length;
      return ws.isNotEmpty && shared >= max(2, ws.length);
    }

    void accept(RingtoneMeta m) {
      usedTitles.add(_norm(m.title));
      usedDescs.add(_norm(m.description));
      usedDescWords.addAll(_wordsOf(m.description));
      rememberConcept(m.title, base.enhancedPrompt);
      results.add(m);
    }

    List<T> lastN<T>(Iterable<T> it, int n) {
      final l = it.toList();
      return l.length > n ? l.sublist(l.length - n) : l;
    }

    for (var attempt = 1; attempt <= 3 && results.length < totalTakes; attempt++) {
      final remaining = totalTakes - results.length;
      final multiPrompt = [
        'You are a Zedge marketplace audio metadata expert.',
        'We generated $totalTakes separate audio variations. Zedge SUSPENDS accounts if uploads share titles, numbered suffixes (V1/V2/V3/V4/#1/Take 1), similar tag lists, or similar descriptions.',
        '',
        zedgePolicyRules,
        '',
        'AUDIO CONCEPT:',
        '- Prompt: ${base.enhancedPrompt}',
        '- Shape: $shape | Key: $musicalKey | Primary Category: ${base.category}',
        '- ALREADY USED TITLES (ZERO overlap allowed): ${lastN(usedTitles, 12).join(', ')}',
        '- ALREADY USED DESCRIPTIONS (ZERO overlap allowed): ${lastN(usedDescs, 8).join(', ')}',
        '- ALREADY USED TAGS (AVOID repeating these — invent fresh synonyms, moods, textures, instruments): ${usedTags.take(28).join(', ')}',
        '',
        'TASK: Return ONLY a valid JSON array with EXACTLY $remaining objects. Each object MUST have completely different "title", "keywords", "category", and "description":',
        '- "title": Unique creative 2-3 word title (max 25 chars). NO numbers, NO V1/V2/V3/V4, NO banned words ($banned).',
        '- "keywords": 8-10 SINGLE-WORD comma-separated tags that are DIFFERENT from the already used tags above.',
        '- "category": ONE exact value from: $validCategories.',
        '- "description": ULTRA-SHORT, EXACTLY 2 TO 3 WORDS (max 24 chars), no punctuation, completely different wording from all other descriptions.',
        '',
        'Output ONLY the raw JSON array, e.g.: [{"title":"...","keywords":"w1, w2, ...","category":"...","description":"..."}]',
      ].join('\n');

      try {
        final reply = await ask(multiPrompt);
        for (final item in parseTakeItems(reply)) {
          if (results.length >= totalTakes) break;
          final kw = item['keywords'] ?? item['tags'];
          final title = RingtonePolicy.cleanTitle(item['title']?.toString() ?? '');
          final tags = RingtonePolicy.cleanKeywords(
              kw is List ? kw.join(', ') : (kw?.toString() ?? ''));
          final rawCat = item['category']?.toString() ?? '';
          final cat = RingtonePolicy.cleanCategory(
              rawCat.isNotEmpty ? rawCat : base.category);
          final desc = RingtonePolicy.cleanDescription(
              item['description']?.toString() ?? '');
          if (title.length < 3 || tags.isEmpty || desc.isEmpty) continue;
          if (usedTitles.contains(_norm(title)) || descTooSimilar(desc)) {
            continue;
          }
          final checked = RingtonePolicy.enforce(RingtoneMeta(
            enhancedPrompt: base.enhancedPrompt,
            title: title,
            tags: tags,
            category: cat,
            description: desc,
          ));
          if (checked.issues.isNotEmpty) continue;
          accept(checked.meta.copyWith(
              tags: distinctTags(
                  checked.meta.tags, results.length, checked.meta.category)));
        }
      } catch (e) {
        _log('Unique take metadata attempt $attempt/3 failed: $e');
      }
    }

    while (results.length < totalTakes) {
      final slot = results.length;
      var title = '';
      for (var tries = 0; tries < 30; tries++) {
        final cand =
            '${fallbackTitleAdjs[_rnd.nextInt(fallbackTitleAdjs.length)]} ${fallbackTitleNouns[_rnd.nextInt(fallbackTitleNouns.length)]}';
        if (!usedTitles.contains(_norm(cand))) {
          title = cand;
          break;
        }
      }
      if (title.isEmpty) {
        // Letters only: listing titles must not carry numbers.
        const az = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
        do {
          title =
              'Studio Motif ${List.generate(3, (_) => az[_rnd.nextInt(26)]).join()}';
        } while (usedTitles.contains(_norm(title)));
      }
      var desc = '';
      for (final raw in [...fallbackDescPairs]..shuffle(_rnd)) {
        final cand = RingtonePolicy.cleanDescription(raw);
        if (!descTooSimilar(cand)) {
          desc = cand;
          break;
        }
      }
      if (desc.isEmpty) desc = RingtonePolicy.cleanDescription(title);
      final tags = distinctTags(
          freshTagBanks[slot % freshTagBanks.length].join(', '),
          slot,
          base.category);
      final checked = RingtonePolicy.enforce(RingtoneMeta(
        enhancedPrompt: base.enhancedPrompt,
        title: title,
        tags: tags,
        category: base.category,
        description: desc,
      ));
      accept(checked.meta);
    }
    return results;
  }

  /// Reads the take list out of a Gemini reply: a JSON array first,
  /// `[SET_n]` tagged blocks as the fallback.
  static List<Map<String, dynamic>> parseTakeItems(String reply) {
    final out = <Map<String, dynamic>>[];
    // Lazy match first (the workflow's pattern), then the widest
    // bracket span: a reply whose values contain "]" needs the latter.
    final candidates = <String>[];
    final lazy = RegExp(r'\[\s*\{[\s\S]*?\}\s*\]').firstMatch(reply);
    if (lazy != null) candidates.add(lazy.group(0)!);
    final a = reply.indexOf('[');
    final b = reply.lastIndexOf(']');
    if (a >= 0 && b > a) candidates.add(reply.substring(a, b + 1));
    for (final c in candidates) {
      try {
        final arr = jsonDecode(c);
        if (arr is List) {
          for (final e in arr) {
            if (e is Map) out.add(Map<String, dynamic>.from(e));
          }
          if (out.isNotEmpty) return out;
        }
      } catch (_) {}
    }
    final blocks = reply.split(RegExp(r'\[\s*SET_\d+\s*\]', caseSensitive: false));
    for (final b in blocks.skip(1)) {
      String f(String tag) {
        final m = RegExp(
                '\\[\\s*$tag\\s*\\]\\s*:?([\\s\\S]*?)(?:\\[\\s*/\\s*$tag\\s*\\]|\\[|\$)',
                caseSensitive: false)
            .firstMatch(b);
        return m == null ? '' : m.group(1)!.trim();
      }

      out.add({
        'title': f('TITLE'),
        'keywords': f('KEYWORDS'),
        'category': f('CATEGORY'),
        'description': f('DESCRIPTION'),
      });
    }
    return out;
  }
}

class RingtoneChosen {
  final String inst, bpm, key, prod;
  const RingtoneChosen(
      {required this.inst,
      required this.bpm,
      required this.key,
      required this.prod});
}
