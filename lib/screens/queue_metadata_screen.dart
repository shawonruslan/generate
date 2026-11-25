import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../distribute.dart';
import '../gemini_web.dart';
import '../ringtone/ringtone_constants.dart';
import '../ringtone/ringtone_data.dart';
import '../ringtone/ringtone_engine.dart';

/// Queue Metadata — the Generator Hub workflow's metadata mode,
/// in-app: scans every configured panel database's queue for image /
/// video records missing title, tags or category, asks Gemini WITH
/// the actual image attached (tagged prompt + Zedge policy verdict),
/// and patches the cleaned metadata back. Policy-flagged queued
/// items are held (status failed) so the upload bot never ships them.
class QueueMetadataScreen extends StatefulWidget {
  const QueueMetadataScreen({super.key});
  @override
  State<QueueMetadataScreen> createState() => _QueueMetadataScreenState();
}

class _QueueMetadataScreenState extends State<QueueMetadataScreen> {
  DistConfig _dist = const DistConfig();
  GeminiWebClient? _web;
  bool _running = false;
  bool _stop = false;
  String _status = 'Ready.';
  int _done = 0, _ok = 0, _failed = 0, _held = 0, _total = 0;
  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final dist = await DistributeStore.load();
    final (web, _) = await loadGeminiClient();
    if (!mounted) return;
    setState(() {
      _dist = dist;
      _web = web;
    });
  }

  void _log(String s) {
    if (!mounted) return;
    setState(() {
      _logs.add(s);
      while (_logs.length > 200) _logs.removeAt(0);
    });
  }

  static const _setKinds = {
    'WALLPAPER_24H': ['morning', 'afternoon', 'evening', 'night'],
    'WALLPAPER_DUAL': ['lock', 'home'],
    'WALLPAPER_BATTERY': ['critical', 'low', 'mid', 'high', 'full', 'charging'],
  };
  static const _videoKinds = {'LIVE_WALLPAPER', 'CHARGING_ANIMATION'};

  String _kindOf(Map<String, dynamic> rec) {
    final ct = (rec['contentType'] ?? '').toString();
    if (_setKinds.containsKey(ct) || _videoKinds.contains(ct)) return ct;
    final type = (rec['type'] ?? '').toString();
    if (type.startsWith('video/')) return 'LIVE_WALLPAPER';
    return 'WALLPAPER';
  }

  bool _isCandidate(Map<String, dynamic> rec) {
    if (rec['isMp3'] == true) return false;
    final type = (rec['type'] ?? '').toString();
    final isImage = type.startsWith('image/') ||
        rec['isImage'] == true ||
        (rec['isMp3'] == false && type.isEmpty);
    final isVideo = _videoKinds.contains(_kindOf(rec)) ||
        type.startsWith('video/');
    if (!isImage && !isVideo) return false;
    bool blank(String k) => (rec[k] ?? '').toString().trim().isEmpty;
    if (!(blank('title') || blank('tags') || blank('category'))) {
      return false;
    }
    return _sourceOf(rec) != null;
  }

  /// A downloadable source: a URL (with [isThumb] marking a video
  /// thumbnail vs the media file itself) or inline base64.
  ({String? url, String? base64, bool isThumb})? _sourceOf(
      Map<String, dynamic> rec) {
    final b64 = (rec['fileBase64'] ?? '').toString();
    if (b64.isNotEmpty) return (url: null, base64: b64, isThumb: false);
    final kind = _kindOf(rec);
    if (_videoKinds.contains(kind)) {
      final thumb = (rec['thumbUrl'] ?? '').toString();
      if (thumb.isNotEmpty) return (url: thumb, base64: null, isThumb: true);
    }
    for (final k in ['fileUrl', 'imageUrl']) {
      final u = (rec[k] ?? '').toString();
      if (u.isNotEmpty) return (url: u, base64: null, isThumb: false);
    }
    final slots = _setKinds[kind];
    final files = rec['files'];
    if (slots != null && files is Map) {
      for (final slot in slots) {
        final v = files[slot];
        if (v is String && v.isNotEmpty) {
          return (url: v, base64: null, isThumb: false);
        }
        if (v is Map && (v['fileUrl'] ?? '').toString().isNotEmpty) {
          return (url: v['fileUrl'].toString(), base64: null, isThumb: false);
        }
      }
    }
    return null;
  }

  String _kindContext(String kind) {
    switch (kind) {
      case 'WALLPAPER_24H':
        return 'I have attached ONE image from a 24H WALLPAPER SET - 4 wallpapers of the same scene that automatically change through the day (morning, afternoon, evening, night). Write metadata for the WHOLE day-cycle set, not just this single frame.';
      case 'WALLPAPER_DUAL':
        return 'I have attached ONE image from a DUAL WALLPAPER SET - a matching lock screen + home screen wallpaper pair. Write metadata that fits the matching pair.';
      case 'WALLPAPER_BATTERY':
        return 'I have attached ONE image from a BATTERY WALLPAPER SET - artwork that changes with the phone battery level (critical, low, mid, high, full, charging). Write metadata that fits the whole battery pack.';
      case 'LIVE_WALLPAPER':
        return 'I have attached a FRAME extracted from a LIVE WALLPAPER VIDEO (an animated phone wallpaper). Write metadata for the animated live wallpaper.';
      case 'CHARGING_ANIMATION':
        return 'I have attached a FRAME extracted from a phone CHARGING ANIMATION VIDEO (an animation that plays while the phone is charging). Write metadata that fits a charging screen animation.';
      default:
        return 'I have attached a phone wallpaper image.';
    }
  }

  String _prompt(String kind) {
    final cats =
        kImageCategories.where((c) => c != 'OTHER').join(', ');
    return 'You are an expert image curator, SEO metadata specialist and Zedge marketplace compliance reviewer.\n\n'
        '$kZedgePolicyRulesImage\n\n'
        '${_kindContext(kind)}\n'
        'Look at the attached image carefully and generate the following metadata:\n'
        '1. A creative and UNIQUE TITLE (max 25 characters). Use evocative, descriptive words. Avoid generic filler words like "beautiful", "amazing", "stunning". No quotes.\n'
        '2. 15 relevant, descriptive single-word KEYWORDS (comma-separated). Cover the subject, colors, mood, style, and use-case.\n'
        '3. The most appropriate CATEGORY selected ONLY from this list: $cats.\n'
        '4. A SHORT description in MAXIMUM 5 WORDS. No punctuation, no full sentences.\n'
        '5. POLICY verdict: write OK if this image is clearly safe and original under the policy above. Otherwise write FLAG: <short reason> — flag any recognizable copyrighted character, franchise art, brand/logo/trademark, celebrity or real identifiable person (selfie, family photo), text watermark, sexual/suggestive content, hate symbol, violence, weapons, drugs, apparent minors, or a stretched / blurry / badly cropped low-quality image.\n\n'
        'CRITICAL: Format your ENTIRE response EXACTLY like this — no other text outside these tags:\n'
        '[TITLE]...[/TITLE]\n'
        '[KEYWORDS]...[/KEYWORDS]\n'
        '[CATEGORY]...[/CATEGORY]\n'
        '[DESCRIPTION]...[/DESCRIPTION]\n'
        '[POLICY]OK or FLAG: reason[/POLICY]';
  }

  Future<Uint8List?> _fetchImage(
      ({String? url, String? base64, bool isThumb}) src) async {
    if (src.base64 != null) {
      var b = src.base64!;
      final comma = b.indexOf(',');
      if (b.startsWith('data:') && comma > 0) b = b.substring(comma + 1);
      try {
        return base64Decode(b);
      } catch (_) {
        return null;
      }
    }
    final resp = await http
        .get(Uri.parse(src.url!))
        .timeout(const Duration(seconds: 60));
    if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
    return resp.bodyBytes;
  }

  Future<void> _run() async {
    if (_web == null) {
      final (web, _) = await loadGeminiClient();
      if (mounted) setState(() => _web = web);
    }
    if (_web == null) {
      _log('No Gemini session. Sign in in the Image to Prompt browser first.');
      return;
    }
    setState(() {
      _running = true;
      _stop = false;
      _done = 0;
      _ok = 0;
      _failed = 0;
      _held = 0;
      _total = 0;
      _status = 'Scanning queues…';
    });
    try {
      // Scan all DBs first.
      final work = <(DistAccount, String, Map<String, dynamic>)>[];
      for (final acc in _dist.accounts) {
        try {
          final q = await fetchQueue(
              dbUrl: acc.dbUrl, queuePath: _dist.queuePath, secret: acc.secret);
          if (q == null) continue;
          q.forEach((key, v) {
            if (v is Map) {
              final rec = Map<String, dynamic>.from(v);
              if (_isCandidate(rec)) work.add((acc, key, rec));
            }
          });
        } catch (e) {
          _log('${acc.name}: scan failed — $e');
        }
      }
      setState(() {
        _total = work.length;
        _status = work.isEmpty
            ? 'Nothing missing metadata.'
            : 'Generating metadata for ${work.length} item(s)…';
      });
      _log('Found ${work.length} item(s) missing metadata.');
      for (final (acc, key, rec) in work) {
        if (_stop) break;
        try {
          await _processOne(acc, key, rec);
          _ok++;
        } catch (e) {
          _failed++;
          _log('$key failed: $e');
        }
        if (mounted) setState(() => _done++);
      }
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _status =
              'Done. Success $_ok · Failed $_failed · Held $_held of $_total.';
        });
      }
    }
  }

  Future<void> _processOne(
      DistAccount acc, String key, Map<String, dynamic> rec) async {
    final kind = _kindOf(rec);
    final src = _sourceOf(rec)!;
    final isVideo = _videoKinds.contains(kind);
    if (isVideo && src.base64 == null && !src.isThumb) {
      _log('$key: video without a thumbnail — skipped (frame extraction '
          'needs ffmpeg).');
      throw Exception('video without thumbnail');
    }
    final bytes = await _fetchImage(src);
    if (bytes == null || bytes.length < 1024) {
      throw Exception('image source unreadable');
    }
    var reply = await _web!.askWithImage(_prompt(kind), bytes,
        filename: 'image.jpg', mimeType: 'image/jpeg', attempts: 2);
    var title = cleanImageTitle(tagValue(reply, 'TITLE'));
    var tags = cleanImageKeywords(tagValue(reply, 'KEYWORDS'));
    var category = cleanImageCategory(tagValue(reply, 'CATEGORY'));
    var desc = cleanImageDescription(tagValue(reply, 'DESCRIPTION'));
    var policy = tagValue(reply, 'POLICY').trim();
    if (title.isEmpty) title = 'Image ${key.substring(0, min(8, key.length))}';

    var en = ZedgePolicy.enforce(
      title: title,
      tags: tags,
      description: desc,
      prompt: '',
      category: category,
      audio: false,
    );
    var flagged = policy.toUpperCase().startsWith('FLAG')
        ? policy
        : (en.issues.isNotEmpty ? en.issues.first : '');
    if (flagged.isNotEmpty) {
      // One regeneration, like the workflow.
      reply = await _web!.askWithImage(_prompt(kind), bytes,
          filename: 'image.jpg', mimeType: 'image/jpeg', attempts: 1);
      title = cleanImageTitle(tagValue(reply, 'TITLE'));
      tags = cleanImageKeywords(tagValue(reply, 'KEYWORDS'));
      category = cleanImageCategory(tagValue(reply, 'CATEGORY'));
      desc = cleanImageDescription(tagValue(reply, 'DESCRIPTION'));
      policy = tagValue(reply, 'POLICY').trim();
      en = ZedgePolicy.enforce(
        title: title,
        tags: tags,
        description: desc,
        prompt: '',
        category: category,
        audio: false,
      );
      flagged = policy.toUpperCase().startsWith('FLAG')
          ? policy
          : (en.issues.isNotEmpty ? en.issues.first : '');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final patch = <String, dynamic>{
      'title': title,
      'tags': en.tags.join(', '),
      'category': category,
      'description':
          desc.isNotEmpty ? desc : title.split(' ').take(3).join(' '),
      'metadataGeneratedAt': now,
      'policyCheckedAt': now,
    };
    final queued = (rec['status'] ?? '').toString() == 'queued';
    if (flagged.isNotEmpty && queued) {
      patch['policyCheck'] = 'held';
      patch['policyFlag'] = flagged;
      patch['status'] = 'failed';
      patch['error'] =
          'Zedge policy hold — $flagged. Review this item; Requeue only if it is your own original, policy-compliant work.';
      patch['failedAt'] = now;
      _held++;
      _log('$key HELD: $flagged');
    } else {
      patch['policyCheck'] = flagged.isNotEmpty ? 'review' : 'passed';
      if (flagged.isNotEmpty) patch['policyFlag'] = flagged;
      _log('$key → "$title" ($category)');
    }
    await patchQueueRecord(
      dbUrl: acc.dbUrl,
      queuePath: _dist.queuePath,
      key: key,
      secret: acc.secret,
      patch: patch,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Queue Metadata (auto-scan)')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(
            'Scans every configured panel database for image/video records '
            'missing title, tags or category, generates the metadata with '
            'Gemini looking at the actual image (the workflow\'s tagged '
            'prompt + Zedge policy verdict), and patches it back. Flagged '
            'queued items are held so the bot never uploads them.'),
        const SizedBox(height: 12),
        if (_dist.accounts.isEmpty)
          Text('No panel accounts configured (Settings → Distribution).',
              style: TextStyle(color: scheme.error))
        else
          Text(
              'Accounts: ${_dist.accounts.map((a) => a.name).join(', ')} · queue: ${_dist.queuePath}',
              style: TextStyle(color: scheme.outline, fontSize: 13)),
        Text(
            _web == null
                ? 'Gemini: not connected yet.'
                : 'Gemini: ready.',
            style: TextStyle(color: scheme.outline, fontSize: 13)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _running || _dist.accounts.isEmpty ? null : _run,
              icon: const Icon(Icons.auto_fix_high_outlined, size: 20),
              label: const Text('Scan & generate metadata'),
            ),
          ),
          if (_running) ...[
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => setState(() => _stop = true),
              child: const Text('Stop'),
            ),
          ],
        ]),
        const SizedBox(height: 8),
        if (_running || _total > 0)
          LinearProgressIndicator(
              value: _total == 0 ? null : _done / _total),
        const SizedBox(height: 4),
        Text(_status, style: TextStyle(color: scheme.outline, fontSize: 13)),
        if (_logs.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: SingleChildScrollView(
                reverse: true,
                child: Text(_logs.join('\n'),
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 11)),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}
