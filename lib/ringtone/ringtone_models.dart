import 'dart:convert';

import 'ringtone_texts.dart';

/// Zedge ringtone categories (workflow `VALID_RT_CATS`).
const List<String> ringtoneCategories = [
  'LATIN', 'MESSAGE_TONES', 'OTHER', 'POP', 'RNB_SOUL', 'REGGAE', 'RELIGIOUS',
  'ROCK', 'SAYINGS', 'ALTERNATIVE', 'ANIMALS', 'BLUES', 'BOLLYWOOD',
  'CHILDREN', 'CLASSICAL', 'SOUND_EFFECTS', 'WORLD', 'COMEDY',
  'CONTACT_RINGTONES', 'COUNTRY', 'DANCE', 'ELECTRONICA', 'GAMES', 'HIP_HOP',
  'HOLIDAYS', 'JAZZ',
];

/// The choices of the workflow's studio page (studio.html).
class RingtoneOptions {
  RingtoneOptions._();

  static const soundTypes = ['Ringtone', 'Notification', 'Alarm'];
  static const shapes = ['track', 'loop', 'oneshot'];
  static const shapeLabels = {
    'track': 'Full track',
    'loop': 'Seamless loop',
    'oneshot': 'One-shot',
  };
  static const timeSignatures = ['4/4', '3/4', '6/8', '2/4'];
  static const bitrates = ['192k', '320k'];
  static const bpmPresets = {
    80: 'Slow',
    95: 'Chill',
    110: 'Groove',
    120: 'Upbeat',
    128: 'Club',
    145: 'Fast',
  };
  static const instruments = [
    'Grand Piano', 'Kalimba', 'Marimba', 'Vibraphone', 'Acoustic Guitar',
    'Nylon Spanish Guitar', 'Solo Violin', 'Warm Cello', 'Pizzicato Strings',
    'Concert Flute', 'Hang Drum', 'Japanese Koto', 'Celtic Harp', 'Music Box',
    'Tenor Saxophone', 'Muted Trumpet', 'Rhodes Electric Piano',
    'Analog Pluck Synth', 'Steel Pan', 'Djembe Percussion',
    'Indian Sitar & Tabla', 'Crystal Glass Chimes',
  ];
  static const genres = [
    'Auto', 'Classical', 'Cinematic Orchestral', 'Acoustic Folk', 'Jazz',
    'Lofi Hip-Hop', 'World Cultural', 'Bossa Nova', 'Ambient Nature',
    'Neo Soul', 'Synthwave', 'Minimalist', 'Afrobeat',
  ];
  static const moods = [
    'Auto', 'Peaceful & Serene', 'Upbeat & Joyful', 'Energetic & Punchy',
    'Mysterious & Intriguing', 'Warm & Nostalgic', 'Heroic & Epic',
    'Playful & Whimsical', 'Crisp & Futuristic', 'Romantic & Gentle',
  ];
  static const keys = [
    'Auto', 'C Minor', 'C# Minor', 'D Minor', 'Eb Minor', 'E Minor',
    'F Minor', 'F# Minor', 'G Minor', 'Ab Minor', 'A Minor', 'Bb Minor',
    'B Minor', 'C Major', 'Db Major', 'D Major', 'Eb Major', 'E Major',
    'F Major', 'Gb Major', 'G Major', 'Ab Major', 'A Major', 'Bb Major',
    'B Major',
  ];
  static const structures = [
    'Auto',
    'a catchy 3-note hook that repeats and resolves cleanly',
    'a seamless rhythmic loop with a memorable melodic phrase',
    'a rising harmonic build that peaks into a bright motif',
    'a playful call-and-response between lead and rhythm',
    'a crisp plucked arpeggio pattern with natural decay',
  ];
  static const productions = [
    'crisp modern studio mastered production with clear mids',
    'warm analog tape studio polish',
    'intimate close-mic organic acoustic recording',
    'lush wide stereo depth with natural room acoustics',
    'airy minimalist pure tone with clean decay',
  ];
}

/// Everything the studio form sets - the workflow's `STUDIO_CONFIG`.
class RingtoneConfig {
  String masterPrompt;
  String negativePrompt;
  String bannedWords;
  String soundType; // Ringtone | Notification | Alarm
  String audioShape; // track | loop | oneshot
  int takesCount; // 1..4
  String timeSignature;
  int lengthSeconds; // 1..60
  String targetAccount; // account name | all_accounts
  bool useGeminiEnhancer;

  /// 0 = Auto (Gemini / Stable Audio pick the tempo).
  int bpm;
  String instruments; // 'Auto' or comma list
  String genre;
  String mood;
  String musicalKey;
  String structure;
  String production;
  bool autoProcess;
  bool trimSilence;
  int volumeBoostPct;
  double silenceThreshold;
  int padMs;
  int fadeInMs;
  int fadeOutMs;
  String bitrate;
  int seed; // -1 = random

  /// Push every finished take to R2 + the Firebase queue right away,
  /// like the workflow. Off: takes stay local until "Publish".
  bool autoPublish;

  /// Automatically renew the WorkOS access token in the background and on
  /// startup when a refresh token is saved.
  bool autoRefreshToken;

  /// Automatically rotate to the next saved account (or create a fresh
  /// 50-credit account) when credits run low or auth fails.
  bool autoRotateAccount;

  RingtoneConfig({
    this.masterPrompt = defaultMasterPrompt,
    this.negativePrompt = defaultNegativePrompt,
    this.bannedWords = defaultBannedWords,
    this.soundType = 'Ringtone',
    this.audioShape = 'track',
    this.takesCount = 4,
    this.timeSignature = '4/4',
    this.lengthSeconds = 20,
    this.targetAccount = '',
    this.useGeminiEnhancer = true,
    this.bpm = 120,
    this.instruments = 'Auto',
    this.genre = 'Auto',
    this.mood = 'Auto',
    this.musicalKey = 'Auto',
    this.structure = 'Auto',
    this.production = 'crisp modern studio mastered production with clear mids',
    this.autoProcess = true,
    this.trimSilence = true,
    this.volumeBoostPct = 200,
    this.silenceThreshold = 0.004,
    this.padMs = 150,
    this.fadeInMs = 30,
    this.fadeOutMs = 350,
    this.bitrate = '192k',
    this.seed = -1,
    this.autoPublish = true,
    this.autoRefreshToken = true,
    this.autoRotateAccount = true,
  });

  bool get isShort => lengthSeconds < 6 || soundType == 'Notification';

  /// "120" / "Auto", the way the prompt templates want it.
  String get bpmLabel => bpm > 0 ? '$bpm' : 'Auto';

  RingtoneConfig copy() => RingtoneConfig.fromJson(toJson());

  /// Clamps every number into the range the workflow accepts.
  void normalize() {
    if (masterPrompt.trim().isEmpty) masterPrompt = defaultMasterPrompt;
    if (!RingtoneOptions.soundTypes.contains(soundType)) soundType = 'Ringtone';
    if (!RingtoneOptions.shapes.contains(audioShape)) audioShape = 'track';
    takesCount = takesCount.clamp(1, 4);
    lengthSeconds = lengthSeconds.clamp(1, 60);
    if (timeSignature.trim().isEmpty) timeSignature = '4/4';
    if (bpm != 0) bpm = bpm.clamp(40, 240);
    volumeBoostPct = volumeBoostPct.clamp(50, 400);
    silenceThreshold = silenceThreshold.clamp(0.0005, 0.2);
    padMs = padMs.clamp(0, 500);
    fadeInMs = fadeInMs.clamp(0, 2000);
    fadeOutMs = fadeOutMs.clamp(0, 3000);
    if (!RingtoneOptions.bitrates.contains(bitrate)) bitrate = '192k';
    if (instruments.trim().isEmpty) instruments = 'Auto';
    if (genre.trim().isEmpty) genre = 'Auto';
    if (mood.trim().isEmpty) mood = 'Auto';
    if (musicalKey.trim().isEmpty) musicalKey = 'Auto';
    if (structure.trim().isEmpty) structure = 'Auto';
  }

  Map<String, dynamic> toJson() => {
        'masterPrompt': masterPrompt,
        'negativePrompt': negativePrompt,
        'bannedWords': bannedWords,
        'soundType': soundType,
        'audioShape': audioShape,
        'takesCount': takesCount,
        'timeSignature': timeSignature,
        'lengthSeconds': lengthSeconds,
        'targetAccount': targetAccount,
        'useGeminiEnhancer': useGeminiEnhancer,
        'bpm': bpm,
        'instruments': instruments,
        'genre': genre,
        'mood': mood,
        'musicalKey': musicalKey,
        'structure': structure,
        'production': production,
        'autoProcess': autoProcess,
        'trimSilence': trimSilence,
        'volumeBoostPct': volumeBoostPct,
        'silenceThreshold': silenceThreshold,
        'padMs': padMs,
        'fadeInMs': fadeInMs,
        'fadeOutMs': fadeOutMs,
        'bitrate': bitrate,
        'seed': seed,
        'autoPublish': autoPublish,
        'autoRefreshToken': autoRefreshToken,
        'autoRotateAccount': autoRotateAccount,
      };

  static RingtoneConfig fromJson(Map<String, dynamic> m) {
    final d = RingtoneConfig();
    String s(String k, String def) {
      final v = m[k];
      return v == null ? def : v.toString();
    }

    int i(String k, int def) {
      final v = m[k];
      if (v is num) return v.round();
      return int.tryParse('${v ?? ''}') ?? def;
    }

    bool b(String k, bool def) => m[k] is bool ? m[k] as bool : def;
    final c = RingtoneConfig(
      masterPrompt: s('masterPrompt', d.masterPrompt),
      negativePrompt: s('negativePrompt', d.negativePrompt),
      bannedWords: s('bannedWords', d.bannedWords),
      soundType: s('soundType', d.soundType),
      audioShape: s('audioShape', d.audioShape),
      takesCount: i('takesCount', d.takesCount),
      timeSignature: s('timeSignature', d.timeSignature),
      lengthSeconds: i('lengthSeconds', d.lengthSeconds),
      targetAccount: s('targetAccount', d.targetAccount),
      useGeminiEnhancer: b('useGeminiEnhancer', d.useGeminiEnhancer),
      bpm: i('bpm', d.bpm),
      instruments: s('instruments', d.instruments),
      genre: s('genre', d.genre),
      mood: s('mood', d.mood),
      musicalKey: s('musicalKey', d.musicalKey),
      structure: s('structure', d.structure),
      production: s('production', d.production),
      autoProcess: b('autoProcess', d.autoProcess),
      trimSilence: b('trimSilence', d.trimSilence),
      volumeBoostPct: i('volumeBoostPct', d.volumeBoostPct),
      silenceThreshold: (m['silenceThreshold'] is num)
          ? (m['silenceThreshold'] as num).toDouble()
          : d.silenceThreshold,
      padMs: i('padMs', d.padMs),
      fadeInMs: i('fadeInMs', d.fadeInMs),
      fadeOutMs: i('fadeOutMs', d.fadeOutMs),
      bitrate: s('bitrate', d.bitrate),
      seed: i('seed', d.seed),
      autoPublish: b('autoPublish', d.autoPublish),
      autoRefreshToken: b('autoRefreshToken', d.autoRefreshToken),
      autoRotateAccount: b('autoRotateAccount', d.autoRotateAccount),
    );
    c.normalize();
    return c;
  }
}

/// Listing text of one tone.
class RingtoneMeta {
  final String enhancedPrompt;
  final String title;
  final String tags; // "w1, w2, ..."
  final String category;
  final String description;

  const RingtoneMeta({
    required this.enhancedPrompt,
    required this.title,
    required this.tags,
    required this.category,
    required this.description,
  });

  RingtoneMeta copyWith({
    String? enhancedPrompt,
    String? title,
    String? tags,
    String? category,
    String? description,
  }) =>
      RingtoneMeta(
        enhancedPrompt: enhancedPrompt ?? this.enhancedPrompt,
        title: title ?? this.title,
        tags: tags ?? this.tags,
        category: category ?? this.category,
        description: description ?? this.description,
      );
}

/// One finished take in the library (workflow `STUDIO_AUDIOS` entry).
class RingtoneItem {
  String id;

  /// Distribution account + Firebase key once published ('' = local only).
  String dbName;
  String firebaseKey;
  String fileUrl;

  String title;
  String tags;
  String category;
  String description;
  String prompt;
  String enhancedPrompt;
  String negativePrompt;

  /// File on this device ('' for entries that only exist in the queue).
  String localPath;
  String fileName;
  String mimeType;
  int sizeBytes;
  double lengthSeconds;
  int? audioSeed;
  String audioShape;
  String musicalKey;
  String timeSignature;
  int takeIndex;
  int takesTotal;
  String wizardJobId;
  bool processed;
  Map<String, dynamic>? processing;
  String processError;

  /// Made in this app run (the "New" tab of the workflow's library).
  bool isNewSession;
  int createdAt;

  RingtoneItem({
    required this.id,
    this.dbName = '',
    this.firebaseKey = '',
    this.fileUrl = '',
    required this.title,
    this.tags = '',
    this.category = 'OTHER',
    this.description = '',
    this.prompt = '',
    this.enhancedPrompt = '',
    this.negativePrompt = '',
    this.localPath = '',
    this.fileName = '',
    this.mimeType = 'audio/mpeg',
    this.sizeBytes = 0,
    this.lengthSeconds = 0,
    this.audioSeed,
    this.audioShape = 'track',
    this.musicalKey = 'Auto',
    this.timeSignature = '4/4',
    this.takeIndex = 1,
    this.takesTotal = 1,
    this.wizardJobId = '',
    this.processed = false,
    this.processing,
    this.processError = '',
    this.isNewSession = false,
    this.createdAt = 0,
  });

  bool get published => firebaseKey.isNotEmpty && dbName.isNotEmpty;
  bool get isMp3 => mimeType == 'audio/mpeg';
  bool get hasLocalFile => localPath.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'dbName': dbName,
        'firebaseKey': firebaseKey,
        'fileUrl': fileUrl,
        'title': title,
        'tags': tags,
        'category': category,
        'description': description,
        'prompt': prompt,
        'enhancedPrompt': enhancedPrompt,
        'negativePrompt': negativePrompt,
        'localPath': localPath,
        'fileName': fileName,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
        'lengthSeconds': lengthSeconds,
        'audioSeed': audioSeed,
        'audioShape': audioShape,
        'musicalKey': musicalKey,
        'timeSignature': timeSignature,
        'takeIndex': takeIndex,
        'takesTotal': takesTotal,
        'wizardJobId': wizardJobId,
        'processed': processed,
        'processing': processing,
        'processError': processError,
        'createdAt': createdAt,
      };

  static RingtoneItem fromJson(Map<String, dynamic> m) {
    int i(String k, [int def = 0]) {
      final v = m[k];
      if (v is num) return v.round();
      return int.tryParse('${v ?? ''}') ?? def;
    }

    String s(String k, [String def = '']) => (m[k] ?? def).toString();
    return RingtoneItem(
      id: s('id'),
      dbName: s('dbName'),
      firebaseKey: s('firebaseKey'),
      fileUrl: s('fileUrl'),
      title: s('title', 'Ringtone'),
      tags: s('tags'),
      category: s('category', 'OTHER'),
      description: s('description'),
      prompt: s('prompt'),
      enhancedPrompt: s('enhancedPrompt'),
      negativePrompt: s('negativePrompt'),
      localPath: s('localPath'),
      fileName: s('fileName'),
      mimeType: s('mimeType', 'audio/mpeg'),
      sizeBytes: i('sizeBytes'),
      lengthSeconds:
          m['lengthSeconds'] is num ? (m['lengthSeconds'] as num).toDouble() : 0,
      audioSeed: m['audioSeed'] is num ? (m['audioSeed'] as num).round() : null,
      audioShape: s('audioShape', 'track'),
      musicalKey: s('musicalKey', 'Auto'),
      timeSignature: s('timeSignature', '4/4'),
      takeIndex: i('takeIndex', 1),
      takesTotal: i('takesTotal', 1),
      wizardJobId: s('wizardJobId'),
      processed: m['processed'] == true,
      processing: m['processing'] is Map
          ? Map<String, dynamic>.from(m['processing'] as Map)
          : null,
      processError: s('processError'),
      createdAt: i('createdAt'),
    );
  }

  static String encodeList(List<RingtoneItem> items) =>
      jsonEncode([for (final i in items) i.toJson()]);

  static List<RingtoneItem> decodeList(String raw) {
    try {
      final j = jsonDecode(raw);
      if (j is! List) return [];
      return [
        for (final e in j)
          if (e is Map) RingtoneItem.fromJson(Map<String, dynamic>.from(e))
      ];
    } catch (_) {
      return [];
    }
  }
}
