import '../core/constants.dart';
import '../data/archive_reader.dart';

/// Natural ("numeric aware", case-insensitive) compare - `Intl.Collator({numeric:true, sensitivity:"base"})`.
int natCmp(String a, String b) {
  final ra = RegExp(r'(\d+)|(\D+)');
  final ta = ra.allMatches(a.toLowerCase()).map((m) => m.group(0)!).toList();
  final tb = ra.allMatches(b.toLowerCase()).map((m) => m.group(0)!).toList();
  for (var i = 0; i < ta.length && i < tb.length; i++) {
    final x = ta[i], y = tb[i];
    final nx = int.tryParse(x), ny = int.tryParse(y);
    int c;
    if (nx != null && ny != null) {
      c = nx.compareTo(ny);
      if (c == 0) c = x.length.compareTo(y.length);
    } else {
      c = x.compareTo(y);
    }
    if (c != 0) return c;
  }
  return ta.length.compareTo(tb.length);
}

/// Slot detection from file names, e.g. "set1_night.jpg", "lock.png", "battery-low.jpg", "wall_2.jpg" (2nd slot).
const Map<String, List<String>> kSlotWords = {
  'morning': ['morning', 'morn', 'dawn', 'sunrise', 'am'],
  'afternoon': ['afternoon', 'noon', 'midday', 'day'],
  'evening': ['evening', 'sunset', 'dusk', 'eve'],
  'night': ['night', 'midnight', 'dark'],
  'lock': ['lock', 'lockscreen', 'ls'],
  'home': ['home', 'homescreen', 'hs'],
  'critical': ['critical', 'crit', 'empty'],
  'low': ['low'],
  'mid': ['mid', 'medium', 'half'],
  'high': ['high'],
  'full': ['full', '100'],
  'charging': ['charging', 'charge', 'chg'],
};

String? detectSlot(String fileBase, List<String> slots) {
  final stem = fileBase.replaceAll(RegExp(r'\.[^.]+$'), '').toLowerCase();
  final tokens = stem.split(RegExp(r'[^a-z0-9]+')).where((t) => t.isNotEmpty).toList();
  for (final slot in slots) {
    final words = kSlotWords[slot] ?? [slot];
    if (words.any(tokens.contains)) return slot;
  }
  final m = RegExp(r'(\d+)$').firstMatch(stem);
  if (m != null) {
    final idx = int.parse(m.group(1)!) - 1;
    if (idx >= 0 && idx < slots.length) return slots[idx];
  }
  return null;
}

final RegExp kAuxImageRe = RegExp(r'(preview|thumb|thumbnail|cover|poster|collage|mockup|screenshot)', caseSensitive: false);

String prettySetLabel(String? folder) {
  if (folder == null || folder.isEmpty) return '';
  final s = folder.replaceAll(RegExp(r'[_\-]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return s.replaceAllMapped(RegExp(r'\b([a-z])'), (m) => m.group(1)!.toUpperCase());
}

/// A detected set: slot -> archive entry.
class SetGroup {
  SetGroup({required this.files, required this.label, required this.byName});
  final Map<String, ArchiveEntry> files;
  final String label;
  final bool byName;
}

Map<String, ArchiveEntry>? pickBySlotNames(List<ArchiveEntry> files, List<String> slots) {
  final byName = <String, ArchiveEntry>{};
  for (final f in files) {
    final sl = detectSlot(baseName(f.name), slots);
    if (sl != null && !byName.containsKey(sl)) byName[sl] = f;
  }
  return byName.length == slots.length ? byName : null;
}

SetGroup makeSetFromFiles(List<ArchiveEntry> files, List<String> slots, String label) {
  final byName = pickBySlotNames(files, slots);
  if (byName != null) return SetGroup(files: byName, label: label, byName: true);
  final ordered = <String, ArchiveEntry>{};
  for (var i = 0; i < slots.length; i++) {
    ordered[slots[i]] = files[i];
  }
  return SetGroup(files: ordered, label: label, byName: false);
}

class GroupResult {
  GroupResult(this.sets, this.leftovers, this.imageCount);
  final List<SetGroup> sets;
  final List<ArchiveEntry> leftovers;
  final int imageCount;
}

String _dirOf(String name) => name.contains('/') ? name.substring(0, name.lastIndexOf('/')) : '';

/// Folder with exactly N images = one set. Otherwise (flat list / big folder) chunk by N in natural name order.
GroupResult groupEntriesIntoSets(List<ArchiveEntry> entries, List<String> slots) {
  final n = slots.length;
  final imgs = entries.where((e) => !isJunkPath(e.name) && kImgNameRe.hasMatch(e.name)).toList();
  final byDir = <String, List<ArchiveEntry>>{};
  for (final e in imgs) {
    byDir.putIfAbsent(_dirOf(e.name), () => []).add(e);
  }
  final sets = <SetGroup>[];
  final leftovers = <ArchiveEntry>[];
  final dirs = byDir.keys.toList()..sort(natCmp);
  for (final dir in dirs) {
    final files = byDir[dir]!..sort((a, b) => natCmp(baseName(a.name), baseName(b.name)));
    final folderLabel = prettySetLabel(dir.isNotEmpty ? dir.split('/').last : '');
    if (files.length == n) {
      sets.add(makeSetFromFiles(files, slots, folderLabel));
      continue;
    }
    if (files.length > n && files.length < 2 * n) {
      final main = files.where((f) => !kAuxImageRe.hasMatch(baseName(f.name))).toList();
      final aux = files.where((f) => kAuxImageRe.hasMatch(baseName(f.name))).toList();
      if (main.length == n) {
        sets.add(makeSetFromFiles(main, slots, folderLabel));
        leftovers.addAll(aux);
        continue;
      }
      final picked = pickBySlotNames(files, slots);
      if (picked != null) {
        final used = picked.values.toSet();
        sets.add(SetGroup(files: picked, label: folderLabel, byName: true));
        leftovers.addAll(files.where((f) => !used.contains(f)));
        continue;
      }
    }
    var k = 0;
    for (var i = 0; i + n <= files.length; i += n, k++) {
      sets.add(makeSetFromFiles(files.sublist(i, i + n), slots, folderLabel.isNotEmpty ? '$folderLabel #${k + 1}' : ''));
    }
    leftovers.addAll(files.sublist((files.length ~/ n) * n));
  }
  return GroupResult(sets, leftovers, imgs.length);
}

/// Smart archive import unit: either a whole set or a single media file.
class ImportUnit {
  ImportUnit.file({required this.media, required this.entry})
      : kind = 'file',
        type = null,
        files = null,
        byName = false,
        label = '',
        archive = entry?.zArchive;

  ImportUnit.set({required this.type, required this.files, required this.byName, required this.label, required this.archive})
      : kind = 'set',
        media = null,
        entry = null;

  final String kind; // file | set
  final String? media; // audio | video | image
  final ArchiveEntry? entry;
  final String? type; // WALLPAPER_DUAL | WALLPAPER_24H | WALLPAPER_BATTERY
  final Map<String, ArchiveEntry>? files;
  final bool byName;
  final String label;
  final String? archive;

  bool get isSet => kind == 'set';

  /// `unitTitle`
  String get title {
    if (isSet) return '${kSetTypeMeta[type]!.label}${label.isNotEmpty ? ' - $label' : ''}';
    return baseName(entry!.name);
  }
}

class ClassifyResult {
  ClassifyResult(this.units, this.notes, this.mediaCount);
  final List<ImportUnit> units;
  final List<String> notes;
  final int mediaCount;
}

const Map<int, String> kCountToSetType = {2: 'WALLPAPER_DUAL', 4: 'WALLPAPER_24H', 6: 'WALLPAPER_BATTERY'};

/// Classify everything inside a ZIP/RAR without any user selection:
/// folder with 2 images -> Dual set, 4 -> 24H set, 6 -> Battery set;
/// other images -> single wallpapers, mp3 -> ringtone, mp4/mov -> video.
ClassifyResult classifyArchiveEntries(List<ArchiveEntry> entries, String archiveName, String? fallbackType) {
  final units = <ImportUnit>[];
  final notes = <String>[];
  final media = entries
      .where((e) => !isJunkPath(e.name) && (kImgNameRe.hasMatch(e.name) || kAudioNameRe.hasMatch(e.name) || kVideoNameRe.hasMatch(e.name)))
      .toList();
  for (final e in media) {
    e.zArchive = archiveName;
  }
  final audios = media.where((e) => kAudioNameRe.hasMatch(e.name)).toList()..sort((a, b) => natCmp(a.name, b.name));
  for (final e in audios) {
    units.add(ImportUnit.file(media: 'audio', entry: e));
  }
  final videos = media.where((e) => kVideoNameRe.hasMatch(e.name)).toList()..sort((a, b) => natCmp(a.name, b.name));
  for (final e in videos) {
    units.add(ImportUnit.file(media: 'video', entry: e));
  }
  final imgs = media.where((e) => kImgNameRe.hasMatch(e.name)).toList();
  final byDir = <String, List<ArchiveEntry>>{};
  for (final e in imgs) {
    byDir.putIfAbsent(_dirOf(e.name), () => []).add(e);
  }
  final dirs = byDir.keys.toList()..sort(natCmp);
  for (final dir in dirs) {
    var files = byDir[dir]!..sort((a, b) => natCmp(baseName(a.name), baseName(b.name)));
    final label = prettySetLabel(dir.isNotEmpty ? dir.split('/').last : '');
    String? type = kCountToSetType[files.length];
    if (type == null && dir.isNotEmpty) {
      final main = files.where((f) => !kAuxImageRe.hasMatch(baseName(f.name))).toList();
      if (main.length != files.length && kCountToSetType.containsKey(main.length)) {
        notes.add('$label: ignored ${files.length - main.length} preview/cover image(s)');
        files = main;
        type = kCountToSetType[files.length];
      }
    }
    if (type != null && dir.isNotEmpty) {
      final st = makeSetFromFiles(files, kSetTypeMeta[type]!.slots, label);
      units.add(ImportUnit.set(type: type, files: st.files, byName: st.byName, label: label, archive: archiveName));
      continue;
    }
    if (type != null && dir.isEmpty && byDir.length == 1) {
      final st = makeSetFromFiles(files, kSetTypeMeta[type]!.slots, '');
      units.add(ImportUnit.set(type: type, files: st.files, byName: st.byName, label: '', archive: archiveName));
      continue;
    }
    if (fallbackType != null && kSetTypeMeta.containsKey(fallbackType)) {
      final fm = kSetTypeMeta[fallbackType]!;
      final g = groupEntriesIntoSets(files.map((f) => f.copyWithName(baseName(f.name))).toList(), fm.slots);
      for (var i = 0; i < g.sets.length; i++) {
        final st = g.sets[i];
        units.add(ImportUnit.set(
            type: fallbackType, files: st.files, byName: st.byName, label: label.isNotEmpty ? '$label #${i + 1}' : '', archive: archiveName));
      }
      if (g.leftovers.isNotEmpty) {
        notes.add('${label.isNotEmpty ? label : 'root'}: ${g.leftovers.length} image(s) left over (not a full ${fm.short} set) - skipped');
      }
      continue;
    }
    if (dir.isNotEmpty && files.length > 1) {
      notes.add('$label: ${files.length} images is not a set size (2 / 4 / 6) - queued as single wallpapers');
    }
    for (final e in files) {
      units.add(ImportUnit.file(media: 'image', entry: e));
    }
  }
  return ClassifyResult(units, notes, media.length);
}

String describeUnits(List<ImportUnit> units) {
  final c = <String, int>{};
  for (final u in units) {
    final k = u.isSet ? u.type! : u.media!;
    c[k] = (c[k] ?? 0) + 1;
  }
  final parts = <String>[];
  for (final t in const ['WALLPAPER_24H', 'WALLPAPER_DUAL', 'WALLPAPER_BATTERY']) {
    if ((c[t] ?? 0) > 0) parts.add('${c[t]} x ${kSetTypeMeta[t]!.label}');
  }
  if ((c['image'] ?? 0) > 0) parts.add('${c['image']} single wallpaper(s)');
  if ((c['audio'] ?? 0) > 0) parts.add('${c['audio']} ringtone(s)');
  if ((c['video'] ?? 0) > 0) parts.add('${c['video']} video(s)');
  return parts.join(', ');
}
