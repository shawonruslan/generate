import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:path_provider/path_provider.dart';

import 'ringtone_engine.dart';

/// DSP statistics recorded per mastered file (the workflow's
/// processing block in the Firebase record).
class MasterStats {
  double durationBefore = 0, durationAfter = 0, trimmedSec = 0;
  double peakBeforeDb = -120, peakAfterDb = -120;
  double meanBeforeDb = -120, meanAfterDb = -120;
  double gainDb = 0, normalizeDb = 0, boostDb = 0;
  Map<String, dynamic> toJson() => {
        'durationBefore': durationBefore,
        'durationAfter': durationAfter,
        'trimmedSec': trimmedSec,
        'peakBeforeDb': peakBeforeDb,
        'peakAfterDb': peakAfterDb,
        'meanBeforeDb': meanBeforeDb,
        'meanAfterDb': meanAfterDb,
        'gainDb': gainDb,
        'normalizeDb': normalizeDb,
        'boostDb': boostDb,
      };
}

/// Builds the workflow's ffmpeg filter chain for the settings, given
/// the measured source peak (dBFS). Shared by the desktop-binary and
/// the bundled-plugin paths.
({String filters, double normalizeDb, double boostDb, double gainDb})
    ffmpegFilterChain(RingtoneSettings s, double peakBeforeDb) {
  final thrDb = 20 * log(s.silenceThreshold) / ln10;
  final padSec = s.padMs / 1000.0;
  final isLoop = s.audioShape == 'loop';
  final fadeOut = isLoop ? 0.025 : max(0.25, s.fadeOutMs / 1000.0);
  final fadeIn = isLoop ? 0.015 : s.fadeInMs / 1000.0;
  final normalizeDb = (-1.0 - peakBeforeDb).clamp(0.0, 30.0);
  final boostDb = 20 * log(s.volumeBoostPct / 100) / ln10;
  final gainDb = normalizeDb + boostDb;
  final filters = <String>[];
  if (s.trimSilence) {
    final sil =
        'silenceremove=start_periods=1:start_threshold=${thrDb.toStringAsFixed(2)}dB:start_silence=${padSec.toStringAsFixed(3)}:detection=peak';
    filters.addAll([sil, 'areverse', sil, 'areverse']);
    filters.add('atrim=0:${s.lengthSeconds}');
    filters.add('asetpts=PTS-STARTPTS');
  }
  filters.addAll([
    'areverse',
    'afade=t=in:st=0:d=${fadeOut.toStringAsFixed(3)}',
    'areverse',
    'afade=t=in:st=0:d=${fadeIn.toStringAsFixed(3)}',
    'volume=${gainDb.toStringAsFixed(2)}dB',
    'alimiter=limit=0.95:attack=5:release=50:level=false',
  ]);
  return (
    filters: filters.join(','),
    normalizeDb: normalizeDb,
    boostDb: boostDb,
    gainDb: gainDb
  );
}

/// Masters through the BUNDLED ffmpeg (ffmpeg_kit_flutter_new_audio —
/// the audio variant with lame/MP3) — this is how Android gets real
/// MP3 files. Same chain and stats as the desktop path; returns null
/// on any failure so the caller can fall back to the pure-Dart WAV.
Future<(Uint8List, MasterStats)?> masterWithFfmpegKit(
    Uint8List wavBytes, RingtoneSettings s) async {
  final tmp = await getTemporaryDirectory();
  final dir = Directory(
      '${tmp.path}/ringtone_proc_${DateTime.now().millisecondsSinceEpoch}');
  await dir.create(recursive: true);
  try {
    final inF = File('${dir.path}/in.wav');
    final outF = File('${dir.path}/out.mp3');
    await inF.writeAsBytes(wavBytes);
    final stats = MasterStats();

    Future<String> run(String cmd) async {
      final session = await FFmpegKit.execute(cmd);
      final rc = await session.getReturnCode();
      if (!ReturnCode.isSuccess(rc)) {
        throw Exception('ffmpeg failed: ${await session.getFailStackTrace()}');
      }
      return (await session.getAllLogsAsString()) ?? '';
    }

    Future<void> measureInto(File f, bool before) async {
      final logs =
          await run('-i "${f.path}" -af volumedetect -f null -');
      double grab(String k) =>
          double.tryParse(
              RegExp('$k: (-?[0-9.]+) dB').firstMatch(logs)?.group(1) ??
                  '') ??
          -120;
      final dur = RegExp(r'Duration: (\d+):(\d+):([0-9.]+)').firstMatch(logs);
      final durSec = dur == null
          ? 0.0
          : int.parse(dur.group(1)!) * 3600 +
              int.parse(dur.group(2)!) * 60 +
              double.parse(dur.group(3)!);
      if (before) {
        stats.durationBefore = durSec;
        stats.peakBeforeDb = grab('max_volume');
        stats.meanBeforeDb = grab('mean_volume');
      } else {
        stats.durationAfter = durSec;
        stats.peakAfterDb = grab('max_volume');
        stats.meanAfterDb = grab('mean_volume');
      }
    }

    await measureInto(inF, true);
    if (!s.autoProcess) {
      await run('-y -i "${inF.path}" -ar 44100 -b:a ${s.bitrate} '
          '"${outF.path}"');
    } else {
      final chain = ffmpegFilterChain(s, stats.peakBeforeDb);
      stats.normalizeDb = chain.normalizeDb;
      stats.boostDb = chain.boostDb;
      stats.gainDb = chain.gainDb;
      await run('-y -i "${inF.path}" -af "${chain.filters}" '
          '-ar 44100 -b:a ${s.bitrate} "${outF.path}"');
    }
    if (!await outF.exists()) return null;
    await measureInto(outF, false);
    stats.trimmedSec = stats.durationBefore - stats.durationAfter;
    return (await outF.readAsBytes(), stats);
  } catch (_) {
    return null;
  } finally {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }
}

/// Finds an ffmpeg binary on desktop platforms (PATH lookup).
Future<String?> findFfmpeg() async {
  if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
    return null;
  }
  try {
    final r = await Process.run(
        Platform.isWindows ? 'where' : 'which', ['ffmpeg']);
    if (r.exitCode == 0) {
      final first = '${r.stdout}'.split('\n').first.trim();
      if (first.isNotEmpty) return first;
    }
  } catch (_) {}
  return null;
}

/// The workflow's exact ffmpeg chain, when a binary is available:
/// volumedetect measure, then one pass of silenceremove x2 (reversed
/// trick), atrim, fades, volume, alimiter -> MP3 44.1kHz.
/// Returns (mp3Bytes, stats) or null when ffmpeg is unavailable/fails.
Future<(Uint8List, MasterStats)?> masterWithFfmpeg(
    Uint8List wavBytes, RingtoneSettings s, String ffmpeg) async {
  final dir = await Directory.systemTemp.createTemp('ringtone_proc');
  try {
    final inF = File('${dir.path}/in.wav');
    final outF = File('${dir.path}/out.mp3');
    await inF.writeAsBytes(wavBytes);
    final stats = MasterStats();

    Future<Map<String, String>> measure(File f) async {
      final r = await Process.run(ffmpeg,
          ['-i', f.path, '-af', 'volumedetect', '-f', 'null', '-']);
      final err = '${r.stderr}';
      String grab(String k) =>
          RegExp('$k: (-?[0-9.]+) dB').firstMatch(err)?.group(1) ?? '';
      final dur = RegExp(r'Duration: (\d+):(\d+):([0-9.]+)')
          .firstMatch(err);
      return {
        'max': grab('max_volume'),
        'mean': grab('mean_volume'),
        'dur': dur == null
            ? ''
            : '${int.parse(dur.group(1)!) * 3600 + int.parse(dur.group(2)!) * 60 + double.parse(dur.group(3)!)}',
      };
    }

    final before = await measure(inF);
    stats.durationBefore = double.tryParse(before['dur'] ?? '') ?? 0;
    stats.peakBeforeDb = double.tryParse(before['max'] ?? '') ?? -120;
    stats.meanBeforeDb = double.tryParse(before['mean'] ?? '') ?? -120;

    if (!s.autoProcess) {
      final r = await Process.run(ffmpeg, [
        '-y', '-i', inF.path, '-ar', '44100', '-b:a', s.bitrate, outF.path
      ]);
      if (r.exitCode != 0 || !await outF.exists()) return null;
      return (await outF.readAsBytes(), stats);
    }

    final thrDb = 20 * log(s.silenceThreshold) / ln10;
    final padSec = s.padMs / 1000.0;
    final isLoop = s.audioShape == 'loop';
    final fadeOut = isLoop ? 0.025 : max(0.25, s.fadeOutMs / 1000.0);
    final fadeIn = isLoop ? 0.015 : s.fadeInMs / 1000.0;
    final normalizeDb = (-1.0 - stats.peakBeforeDb).clamp(0.0, 30.0);
    final boostDb = 20 * log(s.volumeBoostPct / 100) / ln10;
    stats.normalizeDb = normalizeDb;
    stats.boostDb = boostDb;
    stats.gainDb = normalizeDb + boostDb;

    final filters = <String>[];
    if (s.trimSilence) {
      final sil =
          'silenceremove=start_periods=1:start_threshold=${thrDb.toStringAsFixed(2)}dB:start_silence=${padSec.toStringAsFixed(3)}:detection=peak';
      filters.addAll([sil, 'areverse', sil, 'areverse']);
      filters.add('atrim=0:${s.lengthSeconds}');
      filters.add('asetpts=PTS-STARTPTS');
    }
    filters.addAll([
      'areverse',
      'afade=t=in:st=0:d=${fadeOut.toStringAsFixed(3)}',
      'areverse',
      'afade=t=in:st=0:d=${fadeIn.toStringAsFixed(3)}',
      'volume=${stats.gainDb.toStringAsFixed(2)}dB',
      'alimiter=limit=0.95:attack=5:release=50:level=false',
    ]);
    final r = await Process.run(ffmpeg, [
      '-y', '-i', inF.path,
      '-af', filters.join(','),
      '-ar', '44100', '-b:a', s.bitrate, outF.path
    ]);
    if (r.exitCode != 0 || !await outF.exists()) return null;
    final after = await measure(outF);
    stats.durationAfter = double.tryParse(after['dur'] ?? '') ?? 0;
    stats.peakAfterDb = double.tryParse(after['max'] ?? '') ?? -120;
    stats.meanAfterDb = double.tryParse(after['mean'] ?? '') ?? -120;
    stats.trimmedSec = stats.durationBefore - stats.durationAfter;
    return (await outF.readAsBytes(), stats);
  } catch (_) {
    return null;
  } finally {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }
}
