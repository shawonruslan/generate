import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';

class ZipEntryData {
  final String name; // e.g. 'set-01/morning.jpg' (folders are created)
  final List<int> bytes;

  ZipEntryData(this.name, this.bytes);
}

/// Builds a .zip file on disk using streaming writes (safe for large batches)
/// and returns the created file.
Future<File> buildZipFile(String fileName, List<ZipEntryData> entries) async {
  Directory dir;
  try {
    dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  } catch (_) {
    dir = await getApplicationDocumentsDirectory();
  }
  final zipPath = '${dir.path}${Platform.pathSeparator}$fileName';
  final tmp = await getTemporaryDirectory();
  final tmpFile = File('${tmp.path}${Platform.pathSeparator}zipentry.tmp');
  final encoder = ZipFileEncoder();
  encoder.create(zipPath);
  try {
    for (final e in entries) {
      await tmpFile.writeAsBytes(e.bytes, flush: true);
      encoder.addFile(tmpFile, e.name);
    }
  } finally {
    encoder.close();
  }
  try {
    if (await tmpFile.exists()) await tmpFile.delete();
  } catch (_) {}
  return File(zipPath);
}
