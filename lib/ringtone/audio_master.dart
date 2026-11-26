import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'ringtone_models.dart';

/// A usable ffmpeg binary.
class FfmpegInfo {
  final String path;
  final String version;
  const FfmpegInfo(this.path, this.version);
}

/// Finds the FFmpeg that ships inside the app. Nothing is downloaded:
///  * Windows: the build puts `ffmpeg\\ffmpeg.exe` next to the program
///    (portable zip and installer both carry it).
///  * Android: the APK carries `libffmpeg.so` (an FFmpeg executable) that
///    Android unpacks into the app's native library folder.
/// A custom path typed in the studio is only an optional override.
class FfmpegLocator {
  FfmpegLocator._();

  static FfmpegInfo? _cached;
  static String _cachedFor = '\u0000';

  static const _native = MethodChannel('ais/native');

  static String get exeName => Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';

  /// Where the bundled copy lives on this platform (null when unknown).
  static Future<String?> bundledPath() async {
    try {
      if (Platform.isAndroid) {
        final dir = await _native.invokeMethod<String>('nativeLibDir');
        if (dir == null || dir.isEmpty) return null;
        return '$dir/libffmpeg.so';
      }
      final sep = Platform.pathSeparator;
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      return '$exeDir${sep}ffmpeg$sep$exeName';
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _version(String path) async {
    try {
      final r = await Process.run(path, const ['-hide_banner', '-version'])
          .timeout(const Duration(seconds: 10));
      if (r.exitCode != 0) return null;
      final m = RegExp(r'ffmpeg version (\S+)').firstMatch('${r.stdout}');
      return m?.group(1) ?? 'unknown';
    } catch (_) {
      return null;
    }
  }

  /// Bundled copy first, then [custom] (optional override), then a copy
  /// next to the program / on PATH (developer runs). Null when none runs.
  static Future<FfmpegInfo?> find({String custom = '', bool refresh = false}) async {
    if (Platform.isIOS) return null;
    custom = custom.trim();
    if (!refresh && _cachedFor == custom && _cached != null) return _cached;
    final sep = Platform.pathSeparator;
    final candidates = <String>[];
    final bundled = await bundledPath();
    if (bundled != null) candidates.add(bundled);
    if (custom.isNotEmpty) {
      candidates.add(custom);
      candidates.add('$custom$sep$exeName');
      candidates.add('$custom${sep}bin$sep$exeName');
    }
    if (!Platform.isAndroid) {
      try {
        candidates.add(
            '${File(Platform.resolvedExecutable).parent.path}$sep$exeName');
      } catch (_) {}
      candidates.add(exeName); // PATH
      if (!Platform.isWindows) {
        candidates.addAll(const ['/usr/bin/ffmpeg', '/usr/local/bin/ffmpeg']);
      }
    }
    for (final c in candidates) {
      if (c != exeName && !File(c).existsSync()) continue;
      final v = await _version(c);
      if (v != null) {
        _cachedFor = custom;
        return _cached = FfmpegInfo(c, v);
      }
    }
    _cachedFor = custom;
    return _cached = null;
  }

  static void forget() {
    _cached = null;
    _cachedFor = '\u0000';
  }
}

/// A mastered take.
class MasterResult {
  final Uint8List bytes;

  /// `audio/mpeg` with ffmpeg, `audio/wav` without it.
  final String mime;
  final bool processed;
  final Map<String, dynamic>? stats;
  final String error;
  const MasterResult({
    required this.bytes,
    required this.mime,
    required this.processed,
    this.stats,
    this.error = '',
  });

  bool get isMp3 => mime == 'audio/mpeg';
  String get extension => isMp3 ? 'mp3' : 'wav';
}

/// The numbers the mastering chain runs with, derived from the studio
/// config exactly like the workflow's `autoProcessAudio`.
class MasterParams {
  final double gainFactor;
  final double silenceThreshold;
  final double padSec;
  final String shape;
  final int targetSec;
  final bool trim;
  final double fadeInSec;
  final double fadeOutSec;
  final String bitrate;

  MasterParams(RingtoneConfig cfg)
      : gainFactor = cfg.volumeBoostPct / 100,
        silenceThreshold = cfg.silenceThreshold,
        padSec = cfg.padMs / 1000,
        shape = cfg.audioShape.toLowerCase(),
        targetSec = cfg.lengthSeconds.clamp(1, 60),
        trim = cfg.trimSilence,
        fadeInSec =
            cfg.audioShape.toLowerCase() == 'loop' ? 0.015 : cfg.fadeInMs / 1000,
        fadeOutSec = cfg.audioShape.toLowerCase() == 'loop'
            ? 0.025
            : max(0.25, cfg.fadeOutMs / 1000),
        bitrate = RingtoneOptions.bitrates.contains(cfg.bitrate)
            ? cfg.bitrate
            : '192k';

  double get thresholdAmp => max(silenceThreshold, 0.0005);
  double get thresholdDb => 20 * log(thresholdAmp) / ln10;
  double get boostDb => 20 * log(max(gainFactor, 0.01)) / ln10;

  /// Gain that lifts [peakDb] to -1 dBFS (never attenuates, max +30).
  static double normalizeDb(double? peakDb) =>
      peakDb == null ? 0 : min(30.0, max(0.0, -1.0 - peakDb));

  /// The ffmpeg `-af` chain for a file whose peak is [peakDb].
  String filterChain(double? peakDb) {
    final db = '${thresholdDb.toStringAsFixed(1)}dB';
    final chain = <String>[];
    if (trim) {
      final sr =
          'silenceremove=start_periods=1:start_threshold=$db:start_silence=$padSec:detection=peak';
      chain.addAll([
        sr,
        'areverse',
        sr,
        'areverse',
        'atrim=0:$targetSec',
        'asetpts=PTS-STARTPTS',
      ]);
    }
    if (fadeOutSec > 0.005) {
      chain.addAll([
        'areverse',
        'afade=t=in:st=0:d=${fadeOutSec.toStringAsFixed(3)}',
        'areverse',
      ]);
    }
    if (fadeInSec > 0.005) {
      chain.add('afade=t=in:st=0:d=${fadeInSec.toStringAsFixed(3)}');
    }
    chain.addAll([
      'volume=${(normalizeDb(peakDb) + boostDb).toStringAsFixed(2)}dB',
      'alimiter=limit=0.95:attack=5:release=50:level=false',
    ]);
    return chain.join(',');
  }
}

/// Silence trim + normalise + boost + fades (workflow `ffMeasure`,
/// `autoProcessAudio`, `convertAudioToMp3`).
class AudioMaster {
  AudioMaster._();

  static final _rnd = Random();

  static Future<Directory> _tmpDir() async {
    final d = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}ais_ringtone_proc');
    await d.create(recursive: true);
    return d;
  }

  static String _stamp() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_rnd.nextInt(1 << 20).toRadixString(36)}';

  static Future<ProcessResult> _ff(String bin, List<String> args,
      {Duration timeout = const Duration(seconds: 90)}) async {
    final proc = await Process.start(
        bin, ['-hide_banner', '-nostats', ...args]);
    // Drain both pipes or a chatty ffmpeg blocks on a full buffer.
    final out = proc.stdout.transform(const Utf8Decoder(allowMalformed: true)).join();
    final err = proc.stderr.transform(const Utf8Decoder(allowMalformed: true)).join();
    int code;
    try {
      code = await proc.exitCode.timeout(timeout);
    } on TimeoutException {
      proc.kill();
      throw Exception('ffmpeg timed out');
    }
    return ProcessResult(proc.pid, code, await out, await err);
  }

  static Future<void> _run(String bin, List<String> args) async {
    final r = await _ff(bin, args);
    if (r.exitCode != 0) {
      final tail = '${r.stderr}'.trim().split('\n');
      throw Exception(
          'ffmpeg failed: ${tail.skip(max(0, tail.length - 5)).join(' | ')}');
    }
  }

  /// Duration and peak / mean level of [file].
  static Future<({double? duration, double? peakDb, double? meanDb})> measure(
      String bin, String file) async {
    final r =
        await _ff(bin, ['-i', file, '-af', 'volumedetect', '-f', 'null', '-']);
    final out = '${r.stdout}\n${r.stderr}';
    if (!out.contains('max_volume')) {
      final tail = out.trim().split('\n');
      throw Exception(
          'ffmpeg measure failed: ${tail.skip(max(0, tail.length - 3)).join(' | ')}');
    }
    final dur = RegExp(r'Duration:\s*(\d+):(\d+):([\d.]+)').firstMatch(out);
    final peak = RegExp(r'max_volume:\s*(-?[\d.]+)\s*dB').firstMatch(out);
    final mean = RegExp(r'mean_volume:\s*(-?[\d.]+)\s*dB').firstMatch(out);
    return (
      duration: dur == null
          ? null
          : int.parse(dur.group(1)!) * 3600 +
              int.parse(dur.group(2)!) * 60 +
              double.parse(dur.group(3)!),
      peakDb: peak == null ? null : double.tryParse(peak.group(1)!),
      meanDb: mean == null ? null : double.tryParse(mean.group(1)!),
    );
  }

  static double? _r2(double? v) =>
      v == null ? null : (v * 100).roundToDouble() / 100;

  /// Plain WAV -> MP3, no processing.
  static Future<Uint8List> toMp3(
      Uint8List wav, FfmpegInfo ff, String bitrate) async {
    final dir = await _tmpDir();
    final s = _stamp();
    final sep = Platform.pathSeparator;
    final inF = File('${dir.path}${sep}raw_$s.wav');
    final outF = File('${dir.path}${sep}raw_$s.mp3');
    await inF.writeAsBytes(wav, flush: true);
    try {
      await _run(ff.path,
          ['-i', inF.path, '-ar', '44100', '-b:a', bitrate, '-y', outF.path]);
      return await outF.readAsBytes();
    } finally {
      _del(inF);
      _del(outF);
    }
  }

  static void _del(File f) {
    try {
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  /// The workflow's full chain, MP3 out.
  static Future<MasterResult> masterWithFfmpeg(
      Uint8List wav, RingtoneConfig cfg, FfmpegInfo ff) async {
    final p = MasterParams(cfg);
    final dir = await _tmpDir();
    final s = _stamp();
    final sep = Platform.pathSeparator;
    final inF = File('${dir.path}${sep}in_$s.wav');
    final outF = File('${dir.path}${sep}out_$s.mp3');
    await inF.writeAsBytes(wav, flush: true);
    try {
      final before = await measure(ff.path, inF.path);
      final normDb = MasterParams.normalizeDb(before.peakDb);
      final total = normDb + p.boostDb;
      await _run(ff.path, [
        '-i', inF.path,
        '-af', p.filterChain(before.peakDb),
        '-ar', '44100',
        '-b:a', p.bitrate,
        '-y', outF.path,
      ]);
      if (!outF.existsSync() || outF.lengthSync() < 1000) {
        throw Exception('ffmpeg output empty or too small');
      }
      final after = await measure(ff.path, outF.path);
      final bytes = await outF.readAsBytes();
      final trimmed = (before.duration != null && after.duration != null)
          ? max(0.0, before.duration! - after.duration!)
          : null;
      return MasterResult(
        bytes: bytes,
        mime: 'audio/mpeg',
        processed: true,
        stats: {
          'durationBefore': _r2(before.duration),
          'durationAfter': _r2(after.duration),
          'trimmedSec': _r2(trimmed),
          'peakBeforeDb': before.peakDb,
          'peakAfterDb': after.peakDb,
          'meanBeforeDb': before.meanDb,
          'meanAfterDb': after.meanDb,
          'gainDb': _r2(total),
          'normalizeDb': _r2(normDb),
          'boostDb': _r2(p.boostDb),
          'boostPct': (p.gainFactor * 100).round(),
          'silenceThreshold': p.silenceThreshold,
          'padMs': (p.padSec * 1000).round(),
          'ffmpeg': ff.version,
        },
      );
    } finally {
      _del(inF);
      _del(outF);
    }
  }

  /// What the batch runner calls for every take.
  ///
  /// With ffmpeg: mastered MP3 (or, when mastering is off or fails, a
  /// plain MP3 - the workflow's fallback). Without ffmpeg: the same
  /// trim / fades / gain / limiter done in Dart, saved as WAV - good
  /// for listening and saving, but the queue takes MP3 only.
  static Future<MasterResult> process(
      Uint8List wav, RingtoneConfig cfg, FfmpegInfo? ff) async {
    if (ff != null) {
      if (cfg.autoProcess) {
        try {
          return await masterWithFfmpeg(wav, cfg, ff);
        } catch (e) {
          final mp3 = await toMp3(wav, ff, MasterParams(cfg).bitrate);
          return MasterResult(
              bytes: mp3, mime: 'audio/mpeg', processed: false, error: '$e');
        }
      }
      return MasterResult(
          bytes: await toMp3(wav, ff, MasterParams(cfg).bitrate),
          mime: 'audio/mpeg',
          processed: false);
    }
    if (cfg.autoProcess) {
      try {
        return masterWav(wav, cfg);
      } catch (e) {
        return MasterResult(
            bytes: wav, mime: 'audio/wav', processed: false, error: '$e');
      }
    }
    return MasterResult(bytes: wav, mime: 'audio/wav', processed: false);
  }

  // ---- pure-Dart path (no ffmpeg on this device) ----

  /// The same chain on raw samples; returns a 16-bit PCM WAV.
  static MasterResult masterWav(Uint8List wav, RingtoneConfig cfg) {
    final p = MasterParams(cfg);
    final a = WavAudio.parse(wav);
    final ch = a.channels;
    final rate = a.sampleRate;
    var s = a.samples; // interleaved, -1..1
    var frames = s.length ~/ ch;
    final durBefore = frames / rate;
    final peakBefore = _peak(s);

    if (p.trim && frames > 0) {
      final thr = p.thresholdAmp;
      final pad = (p.padSec * rate).round();
      var first = -1, last = -1;
      for (var f = 0; f < frames && first < 0; f++) {
        for (var c = 0; c < ch; c++) {
          if (s[f * ch + c].abs() > thr) {
            first = f;
            break;
          }
        }
      }
      if (first >= 0) {
        for (var f = frames - 1; f >= first && last < 0; f--) {
          for (var c = 0; c < ch; c++) {
            if (s[f * ch + c].abs() > thr) {
              last = f;
              break;
            }
          }
        }
        final from = max(0, first - pad);
        var to = min(frames, last + 1 + pad);
        to = min(to, from + p.targetSec * rate);
        s = Float64List.sublistView(s, from * ch, to * ch);
        frames = to - from;
      }
      // All silence: left untouched, like silenceremove finding nothing.
    }
    s = Float64List.fromList(s);

    final fo = min(frames, (p.fadeOutSec * rate).round());
    if (p.fadeOutSec > 0.005) {
      for (var i = 0; i < fo; i++) {
        final g = i / fo;
        final f = frames - 1 - i;
        for (var c = 0; c < ch; c++) {
          s[f * ch + c] *= g;
        }
      }
    }
    final fi = min(frames, (p.fadeInSec * rate).round());
    if (p.fadeInSec > 0.005) {
      for (var i = 0; i < fi; i++) {
        final g = i / fi;
        for (var c = 0; c < ch; c++) {
          s[i * ch + c] *= g;
        }
      }
    }

    final peakDb = peakBefore > 0 ? 20 * log(peakBefore) / ln10 : null;
    final normDb = MasterParams.normalizeDb(peakDb);
    final totalDb = normDb + p.boostDb;
    final gain = pow(10, totalDb / 20).toDouble();
    for (var i = 0; i < s.length; i++) {
      s[i] *= gain;
    }
    _limit(s, ch, rate);

    final peakAfter = _peak(s);
    return MasterResult(
      bytes: WavAudio.encode16(s, ch, rate),
      mime: 'audio/wav',
      processed: true,
      stats: {
        'durationBefore': _r2(durBefore),
        'durationAfter': _r2(frames / rate),
        'trimmedSec': _r2(max(0.0, durBefore - frames / rate)),
        'peakBeforeDb': _r2(peakDb),
        'peakAfterDb':
            _r2(peakAfter > 0 ? 20 * log(peakAfter) / ln10 : null),
        'gainDb': _r2(totalDb),
        'normalizeDb': _r2(normDb),
        'boostDb': _r2(p.boostDb),
        'boostPct': (p.gainFactor * 100).round(),
        'silenceThreshold': p.silenceThreshold,
        'padMs': (p.padSec * 1000).round(),
        'ffmpeg': 'built-in (no ffmpeg)',
      },
    );
  }

  static double _peak(Float64List s) {
    var m = 0.0;
    for (final v in s) {
      final a = v.abs();
      if (a > m) m = a;
    }
    return m;
  }

  /// Look-ahead peak limiter at 0.95 (5 ms attack, 50 ms release), all
  /// channels linked - the role `alimiter` plays in the ffmpeg chain.
  static void _limit(Float64List s, int ch, int rate) {
    const limit = 0.95;
    final frames = s.length ~/ ch;
    if (frames == 0) return;
    final look = max(1, (0.005 * rate).round());
    final rel = exp(-1 / (0.050 * rate));
    // Gain each frame needs on its own.
    final need = Float64List(frames);
    for (var f = 0; f < frames; f++) {
      var pk = 0.0;
      for (var c = 0; c < ch; c++) {
        final a = s[f * ch + c].abs();
        if (a > pk) pk = a;
      }
      need[f] = pk > limit ? limit / pk : 1.0;
    }
    // Lowest need inside the look-ahead window (monotonic deque).
    final dq = List<int>.filled(frames, 0);
    var head = 0, tail = 0, g = 1.0;
    var next = 0;
    for (var f = 0; f < frames; f++) {
      final end = min(frames, f + look + 1);
      while (next < end) {
        while (tail > head && need[dq[tail - 1]] >= need[next]) {
          tail--;
        }
        dq[tail++] = next++;
      }
      while (dq[head] < f) {
        head++;
      }
      final target = need[dq[head]];
      g = target < g ? target : target + (g - target) * rel;
      if (g > need[f]) g = need[f];
      for (var c = 0; c < ch; c++) {
        s[f * ch + c] *= g;
      }
    }
  }
}

/// Decoded PCM WAV.
class WavAudio {
  final int channels;
  final int sampleRate;

  /// Interleaved samples, -1..1.
  final Float64List samples;
  const WavAudio(this.channels, this.sampleRate, this.samples);

  double get seconds =>
      channels == 0 || sampleRate == 0 ? 0 : samples.length / channels / sampleRate;

  /// Length in seconds from the header alone (null: not a readable WAV).
  static double? durationOf(Uint8List bytes) {
    try {
      final h = _header(bytes);
      final frameBytes = h.channels * (h.bits ~/ 8);
      if (frameBytes == 0 || h.rate == 0) return null;
      return h.dataLen / frameBytes / h.rate;
    } catch (_) {
      return null;
    }
  }

  static ({int format, int channels, int rate, int bits, int dataOff, int dataLen})
      _header(Uint8List b) {
    if (b.length < 44 ||
        ascii.decode(b.sublist(0, 4), allowInvalid: true) != 'RIFF' ||
        ascii.decode(b.sublist(8, 12), allowInvalid: true) != 'WAVE') {
      throw const FormatException('Not a WAV file');
    }
    final d = ByteData.sublistView(b);
    var off = 12;
    int? format, channels, rate, bits;
    while (off + 8 <= b.length) {
      final id = ascii.decode(b.sublist(off, off + 4), allowInvalid: true);
      var size = d.getUint32(off + 4, Endian.little);
      final body = off + 8;
      if (id == 'fmt ' && body + 16 <= b.length) {
        format = d.getUint16(body, Endian.little);
        channels = d.getUint16(body + 2, Endian.little);
        rate = d.getUint32(body + 4, Endian.little);
        bits = d.getUint16(body + 14, Endian.little);
        // WAVE_FORMAT_EXTENSIBLE: the real format is in the sub-format.
        if (format == 0xFFFE && size >= 26 && body + 26 <= b.length) {
          format = d.getUint16(body + 24, Endian.little);
        }
      } else if (id == 'data') {
        if (format == null) throw const FormatException('WAV without fmt chunk');
        // Streamed files write 0 / 0xFFFFFFFF as the size.
        if (size == 0 || size == 0xFFFFFFFF || body + size > b.length) {
          size = b.length - body;
        }
        return (
          format: format,
          channels: channels!,
          rate: rate!,
          bits: bits!,
          dataOff: body,
          dataLen: size
        );
      }
      off = body + size + (size & 1);
    }
    throw const FormatException('WAV without audio data');
  }

  static WavAudio parse(Uint8List b) {
    final h = _header(b);
    final bytesPer = h.bits ~/ 8;
    if (h.channels < 1 || h.rate < 1 || bytesPer < 1) {
      throw const FormatException('Unsupported WAV header');
    }
    final n = h.dataLen ~/ bytesPer;
    final count = n - n % h.channels;
    final out = Float64List(count);
    final d = ByteData.sublistView(b, h.dataOff, h.dataOff + count * bytesPer);
    if (h.format == 3) {
      if (h.bits == 32) {
        for (var i = 0; i < count; i++) {
          out[i] = d.getFloat32(i * 4, Endian.little);
        }
      } else if (h.bits == 64) {
        for (var i = 0; i < count; i++) {
          out[i] = d.getFloat64(i * 8, Endian.little);
        }
      } else {
        throw FormatException('Unsupported float WAV (${h.bits}-bit)');
      }
    } else if (h.format == 1) {
      switch (h.bits) {
        case 8:
          for (var i = 0; i < count; i++) {
            out[i] = (d.getUint8(i) - 128) / 128;
          }
        case 16:
          for (var i = 0; i < count; i++) {
            out[i] = d.getInt16(i * 2, Endian.little) / 32768;
          }
        case 24:
          for (var i = 0; i < count; i++) {
            final o = i * 3;
            var v = d.getUint8(o) |
                (d.getUint8(o + 1) << 8) |
                (d.getUint8(o + 2) << 16);
            if (v & 0x800000 != 0) v -= 0x1000000;
            out[i] = v / 8388608;
          }
        case 32:
          for (var i = 0; i < count; i++) {
            out[i] = d.getInt32(i * 4, Endian.little) / 2147483648;
          }
        default:
          throw FormatException('Unsupported WAV (${h.bits}-bit)');
      }
    } else {
      throw FormatException('Unsupported WAV encoding (format ${h.format})');
    }
    return WavAudio(h.channels, h.rate, out);
  }

  static Uint8List encode16(Float64List samples, int channels, int rate) {
    final dataLen = samples.length * 2;
    final out = Uint8List(44 + dataLen);
    final d = ByteData.sublistView(out);
    out.setRange(0, 4, ascii.encode('RIFF'));
    d.setUint32(4, 36 + dataLen, Endian.little);
    out.setRange(8, 16, ascii.encode('WAVEfmt '));
    d.setUint32(16, 16, Endian.little);
    d.setUint16(20, 1, Endian.little);
    d.setUint16(22, channels, Endian.little);
    d.setUint32(24, rate, Endian.little);
    d.setUint32(28, rate * channels * 2, Endian.little);
    d.setUint16(32, channels * 2, Endian.little);
    d.setUint16(34, 16, Endian.little);
    out.setRange(36, 40, ascii.encode('data'));
    d.setUint32(40, dataLen, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      final v = (samples[i] * 32767).round().clamp(-32768, 32767);
      d.setInt16(44 + i * 2, v, Endian.little);
    }
    return out;
  }
}
