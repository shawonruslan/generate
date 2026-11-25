import 'dart:convert';
import 'dart:math';

import '../gemini_session_manager.dart';
import '../gemini_web.dart';
import '../secure_store.dart';
import '../browser/image_prompt_service.dart';
import 'ringtone_constants.dart';
import 'ringtone_data.dart';

/// Loads the Gemini web client the same way the Batch screen does
/// (v1.16): the LIVE signed-in browser session first, the saved cookie
/// export only as fallback. Returns (client, note).
Future<(GeminiWebClient?, String)> loadGeminiClient() async {
  try {
    final svc = ImagePromptService.instance;
    await svc.load();
    final live = await svc.geminiClient();
    return (live, svc.geminiNote);
  } catch (_) {}
  try {
    final raw = await GeminiWebStore.load();
    if (raw.trim().isNotEmpty) {
      final session = GeminiWebSession.parse(raw);
      return (GeminiSessionManager.clientFor(session), session.summary);
    }
  } on GeminiWebException catch (e) {
    return (null, e.message);
  } catch (e) {
    return (null, 'Gemini web session could not be read: $e');
  }
  return (null, '');
}

// ─── Tolerant tagged-reply extraction (workflow getTagValue) ─────
String tagValue(String text, String tag,
    {List<String> boundaries = const [
      'ENHANCED_PROMPT', 'TITLE', 'KEYWORDS', 'CATEGORY', 'DESCRIPTION', 'POLICY'
    ]}) {
  final t = tag.replaceAll('_', r'[_\s\-]?');
  final open = RegExp(r'\[\s*' + t + r'\s*\]\s*:?', caseSensitive: false);
  final m = open.firstMatch(text);
  if (m == null) return '';
  var rest = text.substring(m.end);
  final close =
      RegExp(r'\[\s*/\s*' + t + r'\s*\]', caseSensitive: false).firstMatch(rest);
  if (close != null) {
    rest = rest.substring(0, close.start);
  } else {
    final names = boundaries.map((b) => b.replaceAll('_', r'[_\s\-]?')).join('|');
    final nx = RegExp(r'\[\s*/?\s*(' + names + r')\s*\]', caseSensitive: false)
        .firstMatch(rest);
    if (nx != null) rest = rest.substring(0, nx.start);
  }
  rest = rest
      .replaceAll('**', '')
      .replaceAll(RegExp(r'^`+|`+$'), '')
      .replaceAll(RegExp(r'^\s*:\s*'), '')
      .trim();
  if (rest == '...' || rest == '…') return '';
  return rest;
}

// ─── Cleaners (workflow cleanTitle/cleanKeywords/…) ──────────────
String cleanRingtoneTitle(String raw) {
  var t = raw.trim();
  if (t.isEmpty) return '';
  t = t.replaceAll(
      RegExp(r'^(here is a title:|title:|the title is:|suggested title:)',
          caseSensitive: false),
      '');
  t = t.replaceAll(RegExp(r'["*]'), '').trim();
  t = t.replaceAll(
      RegExp(r'\s+(v|take|part|mix|version)\s*\d+$', caseSensitive: false), '');
  t = t.replaceAll(RegExp(r'\s+#\d+$'), '');
  t = t.replaceAll(RegExp(r'\s+\d+$'), '');
  t = t.trim();
  if (t.length > 28) t = t.substring(0, 28).trim();
  return t;
}

String cleanRingtoneKeywords(String raw) {
  const stop = {
    'here', 'are', 'the', 'keywords', 'based', 'on', 'this', 'image',
    'and', 'for', 'with', 'your', 'ringtone', 'title', 'tags', 'single',
    'word'
  };
  final words = RegExp(r'[a-zA-Z0-9]{2,20}')
      .allMatches(raw)
      .map((m) => m.group(0)!.toLowerCase())
      .where((w) => !stop.contains(w));
  final out = <String>[];
  for (final w in words) {
    if (!out.contains(w)) out.add(w);
    if (out.length >= 10) break;
  }
  return out.join(', ');
}

String cleanRingtoneCategory(String raw) {
  final upper = raw.toUpperCase();
  for (final c in kRingtoneCategories) {
    if (c != 'OTHER' && upper.contains(c)) return c;
  }
  return 'OTHER';
}

/// Ringtone description: exactly 2–3 words, max ~28 chars.
String cleanRingtoneDescription(String raw) {
  var t = raw
      .replaceAll(
          RegExp(r'^(here is a short description:|description:)',
              caseSensitive: false),
          '')
      .replaceAll(RegExp(r'[.,!?;:"\u2019\u2018()\[\]]'), ' ')
      .trim();
  final words = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  t = words.take(3).join(' ');
  if (t.length > 28) t = t.substring(0, 28).trim();
  return t;
}

// Image-mode cleaners (metadata workflow).
String cleanImageTitle(String raw) {
  if (raw.trim().isEmpty) return '';
  var t = raw
      .replaceAll(
          RegExp(r'^(here is a title:|title:|the title is:|suggested title:)',
              caseSensitive: false),
          '')
      .trim();
  final q = RegExp(r'"([^"\r\n]{3,60})"').firstMatch(t);
  if (q != null) return q.group(1)!.trim();
  final b = RegExp(r'\*\*([^\*\r\n]{3,60})\*\*').firstMatch(t);
  if (b != null) return b.group(1)!.trim();
  final lines = t
      .split('\n')
      .map((l) => l.trim())
      .where((l) {
        final lower = l.toLowerCase();
        return l.isNotEmpty &&
            !lower.startsWith('here') &&
            !lower.startsWith('sure') &&
            !lower.startsWith('based') &&
            !lower.startsWith('suggest') &&
            !lower.startsWith('the') &&
            !lower.startsWith('this');
      })
      .toList();
  String strip(String s) =>
      s.replaceAll(RegExp(r'''^["'\*\s]+|["'\*\s]+$'''), '').trim();
  if (lines.isNotEmpty) {
    final s = strip(lines.first);
    return s.length > 30 ? s.substring(0, 30) : s;
  }
  final s = strip(t);
  return s.length > 30 ? s.substring(0, 30) : s;
}

String cleanImageKeywords(String raw) {
  const stop = {
    'here', 'are', 'the', 'keywords', 'based', 'on', 'this', 'image',
    'and', 'for', 'with', 'your', 'wallpaper', 'title', 'tags', 'single',
    'word'
  };
  final out = <String>[];
  for (final m in RegExp(r'[a-zA-Z0-9]{2,20}').allMatches(raw)) {
    final w = m.group(0)!;
    if (!stop.contains(w.toLowerCase()) && !out.contains(w)) out.add(w);
    if (out.length >= 10) break;
  }
  return out.join(', ');
}

String cleanImageCategory(String raw) {
  if (raw.trim().isEmpty) return 'OTHER';
  final upper = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9_\s]'), ' ');
  for (final e in kImageCategoryAliases.entries) {
    if (e.value.any((a) => upper.contains(a))) return e.key;
  }
  return 'OTHER';
}

/// Image description: max 5 words, no punctuation/sentences.
String cleanImageDescription(String raw) {
  if (raw.trim().isEmpty) return '';
  final q = RegExp(r'"([^"\r\n]{3,100})"').firstMatch(raw);
  var t = q != null ? q.group(1)! : raw;
  t = t
      .replaceAll(
          RegExp(r'^(here is a short description:|description:)',
              caseSensitive: false),
          '')
      .trim();
  final words = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  return words.take(5).join(' ');
}

// ─── Zedge policy guard (workflow zedgePolicyIssues/Enforce) ────
class ZedgePolicy {
  static final RegExp _ip =
      RegExp(r'\b(?:' + kPolicyIpPattern + r')\b', caseSensitive: false);
  static final RegExp _adult =
      RegExp(r'\b(?:' + kPolicyAdultPattern + r')\b', caseSensitive: false);
  static final RegExp _harm =
      RegExp(r'\b(?:' + kPolicyHarmPattern + r')\b', caseSensitive: false);
  static final RegExp _promo =
      RegExp(r'\b(?:' + kPolicyPromoPattern + r')\b', caseSensitive: false);
  static final RegExp _link =
      RegExp(r'[#@]|https?:|www\.|\.(com|net|org|io|app)\b',
          caseSensitive: false);

  /// Returns human-readable issues for the given fields. The prompt
  /// field skips the promo/link checks, like the workflow.
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
      final ip = _ip.firstMatch(v);
      if (ip != null) out.add('$f: protected name "${ip.group(0)}"');
      final ad = _adult.firstMatch(v);
      if (ad != null) out.add('$f: adult term "${ad.group(0)}"');
      final hv = _harm.firstMatch(v);
      if (hv != null) out.add('$f: prohibited term "${hv.group(0)}"');
      if (f != 'prompt') {
        final pr = _promo.firstMatch(v);
        if (pr != null) out.add('$f: promotional/spam word "${pr.group(0)}"');
        if (_link.hasMatch(v)) out.add('$f: link/hashtag/handle');
      }
    });
    return out;
  }

  static List<String> cleanTags(String tags) {
    final words = tags
        .split(RegExp(r'[,\s]+'))
        .map((w) => w.trim().toLowerCase())
        .where((w) => RegExp(r'^[a-z0-9-]{2,20}$').hasMatch(w));
    final out = <String>[];
    for (final w in words) {
      if (!out.contains(w) &&
          !_ip.hasMatch(w) &&
          !_adult.hasMatch(w) &&
          !_harm.hasMatch(w) &&
          !_promo.hasMatch(w)) {
        out.add(w);
      }
      if (out.length >= 10) break;
    }
    return out;
  }

  /// Cleans tags and guarantees at least 2 (category word first, then
  /// the kind's fallback bank), exactly like the workflow.
  static ({List<String> issues, List<String> tags}) enforce({
    required String title,
    required String tags,
    required String description,
    required String prompt,
    required String category,
    required bool audio,
  }) {
    final iss = issues(
        title: title, tags: tags, description: description, prompt: prompt);
    final clean = cleanTags(tags);
    final cat = category.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (cat.isNotEmpty && cat != 'other' && !clean.contains(cat)) {
      clean.insert(0, cat);
    }
    final fallback = audio
        ? ['melody', 'tune', 'alert', 'phone', 'music', 'sound']
        : ['wallpaper', 'background', 'art', 'design', 'phone', 'screen'];
    for (final w in fallback) {
      if (clean.length >= 2) break;
      if (!clean.contains(w)) clean.add(w);
    }
    return (issues: iss, tags: clean.take(10).toList());
  }
}

// ─── Ringtone settings (the studio payload) ──────────────────────
class RingtoneSettings {
  String soundType; // 'Ringtone' | 'Notification' | 'Alarm'
  String audioShape; // 'track' | 'loop' | 'oneshot'
  int takesCount;
  String timeSignature;
  int lengthSeconds;
  bool useGeminiEnhancer;
  int? bpm; // null = Auto
  String instruments; // 'Auto' or comma-joined values
  String genre; // 'Auto' or value
  String mood; // 'Auto' or value
  String musicalKey; // 'Auto' or e.g. 'C Minor'
  String structure; // 'Auto' or phrase
  String production; // phrase
  String negativePrompt;
  String bannedWords;
  String masterPrompt;
  bool autoProcess;
  bool trimSilence;
  int volumeBoostPct;
  double silenceThreshold;
  int padMs;
  int fadeInMs;
  int fadeOutMs;
  String bitrate; // '192k' | '320k'
  int seed; // -1 = random

  RingtoneSettings({
    this.soundType = 'Ringtone',
    this.audioShape = 'track',
    this.takesCount = 4,
    this.timeSignature = '4/4',
    this.lengthSeconds = 20,
    this.useGeminiEnhancer = true,
    this.bpm = 120,
    this.instruments = 'Auto',
    this.genre = 'Auto',
    this.mood = 'Auto',
    this.musicalKey = 'Auto',
    this.structure = 'Auto',
    this.production =
        'crisp modern studio mastered production with clear mids',
    this.negativePrompt = kDefaultNegativePrompt,
    this.bannedWords = kDefaultBannedWords,
    this.masterPrompt = kDefaultMasterPrompt,
    this.autoProcess = true,
    this.trimSilence = true,
    this.volumeBoostPct = 200,
    this.silenceThreshold = 0.020,
    this.padMs = 100,
    this.fadeInMs = 30,
    this.fadeOutMs = 350,
    this.bitrate = '192k',
    this.seed = -1,
  });

  RingtoneSettings copy() => RingtoneSettings(
        soundType: soundType,
        audioShape: audioShape,
        takesCount: takesCount,
        timeSignature: timeSignature,
        lengthSeconds: lengthSeconds,
        useGeminiEnhancer: useGeminiEnhancer,
        bpm: bpm,
        instruments: instruments,
        genre: genre,
        mood: mood,
        musicalKey: musicalKey,
        structure: structure,
        production: production,
        negativePrompt: negativePrompt,
        bannedWords: bannedWords,
        masterPrompt: masterPrompt,
        autoProcess: autoProcess,
        trimSilence: trimSilence,
        volumeBoostPct: volumeBoostPct,
        silenceThreshold: silenceThreshold,
        padMs: padMs,
        fadeInMs: fadeInMs,
        fadeOutMs: fadeOutMs,
        bitrate: bitrate,
        seed: seed,
      );
}

class RingtoneMeta {
  String enhancedPrompt;
  String title;
  String tags; // comma-separated
  String category;
  String description;
  RingtoneMeta({
    required this.enhancedPrompt,
    required this.title,
    required this.tags,
    required this.category,
    required this.description,
  });
}

// ─── Smart Variety / auto-discovery (workflow engine) ────────────
class AutoDiscovery {
  final Random _rng = Random();
  final Set<String> _used = {};
  final List<String> _pathDeck = [];
  final List<String> recentConcepts = [];

  String _pickFresh(List<String> pool, String name) {
    var fresh = pool.where((x) => !_used.contains('$name:$x')).toList();
    if (fresh.isEmpty) {
      for (final x in pool) {
        _used.remove('$name:$x');
      }
      fresh = pool;
    }
    final item = fresh[_rng.nextInt(fresh.length)];
    _used.add('$name:$item');
    return item;
  }

  String _drawPath(List<String> paths) {
    if (_pathDeck.isEmpty) {
      _pathDeck.addAll([...paths]..shuffle(_rng));
    }
    return _pathDeck.removeLast();
  }

  void rememberConcept(String title, String enhancedPrompt) {
    final p = enhancedPrompt.length > 70
        ? enhancedPrompt.substring(0, 70)
        : enhancedPrompt;
    recentConcepts.add('"$title" — $p');
    while (recentConcepts.length > 12) {
      recentConcepts.removeAt(0);
    }
  }

  /// Resolves all Auto settings into concrete choices for one prompt,
  /// mirroring the workflow's theme-path engine.
  ({
    String genre,
    String instruments,
    String mood,
    String bpm,
    String key,
    String structure,
    String production,
  }) resolve(RingtoneSettings s) {
    String themeFor(String path) {
      switch (path) {
        case 'Musical':
          return 'Style: ${_pickFresh(kPoolGenres, 'genres')} | Lead: ${_pickFresh(kPoolInstruments, 'instruments')} | Mood: ${_pickFresh(kPoolMoods, 'moods')}';
        case 'Animal':
          return 'Type: Animal Sound (Musical Translation) | Focus: ${_pickFresh(kPoolAnimals, 'animals')} | Mood: ${_pickFresh(kPoolMoods, 'moods')}';
        case 'Comedy':
          return 'Type: Comedy/Funny | Sound: ${_pickFresh(kPoolComedy, 'comedy')} | Character: ${_pickFresh(kPoolMoods, 'moods')}';
        case 'SciFi':
          return 'Type: Sci-Fi / Futuristic | Element: ${_pickFresh(kPoolSciFi, 'sciFi')} | Vibe: ${_pickFresh(kPoolMoods, 'moods')}';
        case 'Situation':
          return 'Purpose: ${_pickFresh(kPoolSituations, 'situations')} | Atmosphere: ${_pickFresh(kPoolMoods, 'moods')}';
        case 'SmartTopic':
          return 'Creative Topic: ${_pickFresh(kPoolAdjectives, 'adjectives')} ${_pickFresh(kPoolTopics, 'topics')} ${_pickFresh(kPoolActions, 'actions')}';
        case 'Horror':
          return 'Type: Horror/Suspense | Sound: ${_pickFresh(kPoolHorror, 'horror')} | Mood: ${_pickFresh(kPoolMoods, 'moods')}';
        case 'Sports':
          return 'Type: Sports/Action | Sound: ${_pickFresh(kPoolSports, 'sports')} | Energy: ${_pickFresh(kPoolMoods, 'moods')}';
        case 'Romance':
          return 'Type: Romantic/Emotional | Theme: ${_pickFresh(kPoolRomance, 'romance')} | Mood: ${_pickFresh(kPoolMoods, 'moods')}';
        case 'Cultural':
          return 'Type: World/Cultural Music | Style: ${_pickFresh(kPoolCultural, 'cultural')} | Mood: ${_pickFresh(kPoolMoods, 'moods')}';
        case 'Kids':
          return 'Type: Children/Playful | Theme: ${_pickFresh(kPoolKids, 'kids')} | Mood: Joyful and Energetic';
        case 'ASMR':
          return 'Type: ASMR/Relaxing Sounds | Sound: ${_pickFresh(kPoolAsmr, 'asmr')} | Texture: Ultra HD, highly detailed';
        case 'Epic':
          return 'Type: Epic/Cinematic | Theme: ${_pickFresh(kPoolEpic, 'epic')} | Scale: Grand and Powerful';
        case 'Urban':
          return 'Type: Urban/Street | Vibe: ${_pickFresh(kPoolUrban, 'urban')} | Mood: ${_pickFresh(kPoolMoods, 'moods')}';
        default:
          return 'Type: Nature Soundscape | Element: ${_pickFresh(kPoolNature, 'nature')} | Intensity: High';
      }
    }

    const paths = [
      'Musical', 'Animal', 'Comedy', 'SciFi', 'Situation', 'SmartTopic',
      'Horror', 'Sports', 'Romance', 'Cultural', 'Kids', 'ASMR', 'Epic',
      'Urban', 'Nature'
    ];
    final path = _drawPath(paths);
    final theme = themeFor(path);
    return (
      genre: s.genre != 'Auto' ? s.genre : '$path ($theme)',
      instruments: s.instruments != 'Auto'
          ? s.instruments
          : _pickFresh(kPoolInstruments, 'instruments'),
      mood: s.mood != 'Auto' ? s.mood : _pickFresh(kPoolMoods, 'moods'),
      bpm: s.bpm != null
          ? '${s.bpm} BPM'
          : kPoolTempos[_rng.nextInt(kPoolTempos.length)],
      key: s.musicalKey != 'Auto'
          ? s.musicalKey
          : 'Clean Harmonic Major/Minor Key',
      structure: s.structure != 'Auto'
          ? s.structure
          : kPoolStructures[_rng.nextInt(kPoolStructures.length)],
      production: s.production,
    );
  }
}

// ─── Gemini composer: master prompt -> enhanced prompt + meta ────
class RingtoneComposer {
  final GeminiWebClient web;
  final AutoDiscovery discovery;
  RingtoneComposer(this.web, this.discovery);

  /// One Gemini call: fills the master template and parses the five
  /// tagged blocks. Throws when the reply is incomplete (the caller
  /// retries, like the workflow).
  Future<RingtoneMeta> generate(String? userPrompt, RingtoneSettings s) async {
    final dur = s.lengthSeconds;
    final isShort = dur < 6 || s.soundType == 'Notification';
    final soundTypeLabel = isShort
        ? 'Short Notification/Alert Tone'
        : (s.soundType == 'Alarm'
            ? 'Progressive Wake-up Alarm Tone'
            : 'Full Melodic Ringtone');
    final r = discovery.resolve(s);

    final craftRules = isShort
        ? 'CRAFT RULES for a premium NOTIFICATION sound (${dur}s):\n'
            '- Design ONE memorable 2-4 note motif with a clean, bright attack and a smooth natural decay.\n'
            '- Pleasant to hear 100 times a day: no harsh, shrill, or startling frequencies.\n'
            '- ZERO IMITATION: Never imitate default iPhone, Samsung, Nokia, or Pixel tones.\n'
            '- Name the real instrument (${r.instruments}), exact articulation (plucked, struck, warm chime), and decay feel.'
        : 'CRAFT RULES for a chart-topping RINGTONE (${dur}s):\n'
            '- The melodic hook must be instantly recognizable within the FIRST 2 SECONDS.\n'
            '- Clear, musical melody at ${r.bpm} featuring ${r.instruments} in ${r.key}.\n'
            '- ZERO IMITATION: Never imitate stock phone ringtones from Apple, Samsung, Nokia, or Motorola.\n'
            '- CRITICAL FULL DURATION: Music MUST start immediately at 0.0s and stay active continuously for the ENTIRE ${dur}s — NO silent intro, NO early fade-out, NO trailing silence.\n'
            '- Must cut through on a phone speaker (strong clear mids, crisp highs, no muddy sub-bass).';

    final rendererRules =
        'AUDIO RENDERER FACTS (the ENHANCED_PROMPT is sent to Stable Audio 2.5 text-to-music model for ${dur}s):\n'
        '- Renders musical instruments, genres, rhythm, BPM, harmony, and studio textures with high fidelity.\n'
        '- Cannot render realistic human speech, lyrics, or raw unmusical foley — always translate concepts into musical instruments.\n'
        '- TITLE, KEYWORDS and DESCRIPTION must describe ONLY what the ENHANCED_PROMPT literally sounds like.';

    final salt =
        Random().nextInt(1 << 32).toRadixString(36);
    final novelty = discovery.recentConcepts.isEmpty
        ? ''
        : 'ALREADY GENERATED IN THIS SESSION (make your new concept completely distinct):\n'
            '${discovery.recentConcepts.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n')}\n';
    final idea = (userPrompt != null && userPrompt.trim().isNotEmpty)
        ? 'User Prompt Idea: "${userPrompt.trim()}"\n'
            'Rewrite and enrich this idea into a vivid, studio-grade 25-to-35-word text-to-music prompt incorporating the Featured Instruments (${r.instruments}), Tempo (${r.bpm}), Mood (${r.mood}), Key (${r.key}), and Production (${r.production}). [Salt: $salt]'
        : 'Invent a fresh, sellable 25-to-35-word text-to-music prompt for a $soundTypeLabel featuring ${r.instruments} in a ${r.genre} style with a ${r.mood} mood at ${r.bpm} in ${r.key}, built around ${r.structure} with ${r.production}.\n'
            '$novelty[Salt: $salt]';

    final template =
        s.masterPrompt.trim().isNotEmpty ? s.masterPrompt : kDefaultMasterPrompt;
    final validCats =
        kRingtoneCategories.where((c) => c != 'OTHER').join(', ');
    var prompt = template
        .replaceAll('{{ZEDGE_POLICY_RULES}}', kZedgePolicyRulesAudio)
        .replaceAll('{{RENDERER_RULES}}', rendererRules)
        .replaceAll('{{CRAFT_RULES}}', craftRules)
        .replaceAll('{{SOUND_TYPE}}', soundTypeLabel)
        .replaceAll('{{DURATION}}', '$dur')
        .replaceAll('{{BPM}}', r.bpm)
        .replaceAll('{{INSTRUMENTS}}', r.instruments)
        .replaceAll('{{GENRE}}', r.genre)
        .replaceAll('{{MOOD}}', r.mood)
        .replaceAll('{{KEY}}', r.key)
        .replaceAll('{{STRUCTURE}}', r.structure)
        .replaceAll('{{PRODUCTION}}', r.production)
        .replaceAll('{{NEGATIVE_PROMPT}}', s.negativePrompt)
        .replaceAll('{{BANNED_WORDS}}', s.bannedWords)
        .replaceAll('{{VALID_CATEGORIES}}', validCats)
        .replaceAll('{{IDEA}}', idea);

    final reply = await web.ask(prompt, attempts: 2);
    final ep = tagValue(reply, 'ENHANCED_PROMPT');
    final ti = tagValue(reply, 'TITLE');
    final kw = tagValue(reply, 'KEYWORDS');
    final ca = tagValue(reply, 'CATEGORY');
    final de = tagValue(reply, 'DESCRIPTION');
    final missing = <String>[
      if (ep.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length < 4)
        'ENHANCED_PROMPT',
      if (ti.isEmpty) 'TITLE',
      if (kw.isEmpty) 'KEYWORDS',
    ];
    if (missing.isNotEmpty) {
      throw Exception(
          'Gemini reply incomplete (missing ${missing.join(', ')}) — regenerating');
    }

    var enhanced = ep.replaceAll(RegExp(r'''^["']|["']$'''), '').trim();
    if (userPrompt != null &&
        userPrompt.trim().isNotEmpty &&
        !s.useGeminiEnhancer) {
      final extras = [
        if (r.instruments != 'Auto') r.instruments,
        r.bpm,
        if (r.key != 'Auto') r.key,
        r.production,
      ].join(', ');
      enhanced = '${userPrompt.trim()}, $extras';
    }
    final cleanedTitle = cleanRingtoneTitle(ti);
    final fallbackTitle =
        (userPrompt ?? 'Studio Tone').split(' ').take(4).join(' ');
    final title = cleanedTitle.isNotEmpty
        ? cleanedTitle
        : fallbackTitle.substring(0, min(28, fallbackTitle.length));
    final meta = RingtoneMeta(
      enhancedPrompt: enhanced,
      title: title,
      tags: cleanRingtoneKeywords(kw),
      category: cleanRingtoneCategory(ca),
      description:
          cleanRingtoneDescription(de).isNotEmpty ? cleanRingtoneDescription(de) : title,
    );
    discovery.rememberConcept(meta.title, meta.enhancedPrompt);
    return meta;
  }

  /// Per-take unique metadata (workflow generateUniqueTakeMetadatas):
  /// take 1 keeps the base; the rest come from one Gemini JSON call,
  /// topped up / replaced by deterministic local banks when needed.
  Future<List<RingtoneMeta>> uniqueTakeMetas(
      RingtoneMeta base, int totalTakes, RingtoneSettings s) async {
    final out = <RingtoneMeta>[
      RingtoneMeta(
        enhancedPrompt: base.enhancedPrompt,
        title: cleanRingtoneTitle(base.title).isNotEmpty
            ? cleanRingtoneTitle(base.title)
            : 'Fresh Studio Tone',
        tags: base.tags,
        category: base.category,
        description: base.description,
      )
    ];
    if (totalTakes <= 1) return out;
    final need = totalTakes - 1;
    final usedTitles = <String>{out.first.title.toLowerCase()};
    final usedDescs = <String>{out.first.description.toLowerCase()};
    var usedTags = out.first.tags
        .split(',')
        .map((t) => t.trim().toLowerCase())
        .where((t) => t.isNotEmpty)
        .toSet();

    List<Map<String, dynamic>>? ai;
    for (var attempt = 0; attempt < 3 && ai == null; attempt++) {
      try {
        final prompt = 'You are a Zedge marketplace audio metadata expert. '
            'We generated $totalTakes separate audio variations of one ringtone concept. '
            'Zedge SUSPENDS accounts if uploads share titles, numbered suffixes (V1/V2/V3/V4/#1/Take 1), similar tag lists, or similar descriptions.\n\n'
            'Base concept prompt: ${base.enhancedPrompt}\n'
            'ALREADY USED — do not repeat or closely imitate:\n'
            'Titles: ${usedTitles.join(' | ')}\n'
            'Descriptions: ${usedDescs.join(' | ')}\n'
            'Tags: ${usedTags.join(', ')}\n\n'
            'Write metadata for the remaining $need variations. For EACH: a unique title of 2-3 words (max 25 chars, no banned words: ${s.bannedWords}), '
            '8-10 single-word keywords DIFFERENT from the used tags, a category from this list ONLY: ${kRingtoneCategories.where((c) => c != 'OTHER').join(', ')}, '
            'and a description of exactly 2-3 words (max 24 chars) different from the used ones.\n'
            'Output ONLY a raw JSON array of $need objects like '
            '[{"title":"...","keywords":"word, word","category":"POP","description":"..."}]. No other text.';
        final reply = await web.ask(prompt, attempts: 1);
        final start = reply.indexOf('[');
        final end = reply.lastIndexOf(']');
        if (start >= 0 && end > start) {
          final parsed = jsonDecode(reply.substring(start, end + 1));
          if (parsed is List) {
            ai = parsed
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
        }
      } catch (_) {}
    }

    final rng = Random();
    for (var i = 0; i < need; i++) {
      Map<String, dynamic>? cand = (ai != null && i < ai.length) ? ai[i] : null;
      var title = cleanRingtoneTitle((cand?['title'] ?? '').toString());
      var desc =
          cleanRingtoneDescription((cand?['description'] ?? '').toString());
      var tags = cleanRingtoneKeywords((cand?['keywords'] ?? '').toString());
      var cat = cleanRingtoneCategory((cand?['category'] ?? '').toString());
      if (title.isEmpty ||
          usedTitles.contains(title.toLowerCase()) ||
          desc.isEmpty ||
          usedDescs.contains(desc.toLowerCase())) {
        // Deterministic local fallback banks, like the workflow.
        for (var tries = 0; tries < 24; tries++) {
          final t =
              '${kFallbackTitleAdjectives[rng.nextInt(kFallbackTitleAdjectives.length)]} ${kFallbackTitleNouns[rng.nextInt(kFallbackTitleNouns.length)]}';
          if (!usedTitles.contains(t.toLowerCase())) {
            title = t;
            break;
          }
        }
        if (desc.isEmpty || usedDescs.contains(desc.toLowerCase())) {
          desc = kFallbackDescriptions[
              rng.nextInt(kFallbackDescriptions.length)];
        }
        if (tags.isEmpty) tags = '';
      }
      // Enforce tag distinctness: at most 2 shared with earlier takes,
      // topped up to 9-10 from the rotating descriptor banks.
      var tagList = tags
          .split(',')
          .map((t) => t.trim().toLowerCase())
          .where((t) => t.isNotEmpty)
          .toList();
      final shared = tagList.where((t) => usedTags.contains(t)).length;
      if (shared > 2) {
        tagList = tagList.where((t) => !usedTags.contains(t)).toList();
      }
      final bank = kTagDescriptorBanks[i % kTagDescriptorBanks.length];
      var bi = rng.nextInt(bank.length);
      while (tagList.length < 9) {
        final w = bank[bi % bank.length];
        bi++;
        if (!tagList.contains(w) && !usedTags.contains(w)) tagList.add(w);
        if (bi > bank.length * 2) break;
      }
      tags = tagList.take(10).join(', ');
      usedTitles.add(title.toLowerCase());
      usedDescs.add(desc.toLowerCase());
      usedTags = {...usedTags, ...tagList};
      out.add(RingtoneMeta(
        enhancedPrompt: base.enhancedPrompt,
        title: title.isEmpty ? 'Fresh Studio Tone' : title,
        tags: tags,
        category: cat,
        description: desc.isEmpty ? title : desc,
      ));
    }
    return out;
  }
}

/// Final Stable Audio prompt munging (workflow buildStableAudioPrompt):
/// strips any BPM Gemini wrote, appends the exact BPM, the shape word,
/// the key and the full-duration clause.
String buildStableAudioPrompt(String enhanced, RingtoneSettings s,
    {String? resolvedBpm}) {
  var p = enhanced.trim();
  p = p.replaceAll(RegExp(r',?\s*\d{2,3}\s*BPM', caseSensitive: false), '');
  p = p.replaceAll(RegExp(r'\s+'), ' ').trim();
  final bpmVal = s.bpm;
  if (bpmVal != null) p = '$p, $bpmVal BPM';
  if (s.audioShape == 'loop') {
    p = '$p, loop';
  } else if (s.audioShape == 'oneshot') {
    p = '$p, one-shot';
  } else {
    p = '$p, continuous full-length music with no silence';
  }
  if (s.musicalKey != 'Auto') p = '$p, in ${s.musicalKey}';
  if (!p.endsWith('.')) p = '$p.';
  return p;
}
