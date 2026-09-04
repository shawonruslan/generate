import '../app_config.dart';

/// One row of `wallpaperQueue` in the Realtime Database.
///
/// The raw map is kept as-is so unknown fields written by the uploader bot are
/// never lost when the app saves an edit.
class QueueItem {
  QueueItem({required this.id, required this.raw});

  factory QueueItem.fromMap(String id, Map<String, dynamic> map) {
    return QueueItem(id: id, raw: map);
  }

  final String id;
  final Map<String, dynamic> raw;

  String _str(String key) {
    final Object? value = raw[key];
    if (value == null) return '';
    return value.toString();
  }

  num _num(String key) {
    final Object? value = raw[key];
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? 0;
    return 0;
  }

  String get name => _str('name');
  String get title => _str('title').trim();
  String get tags => _str('tags');
  String get category => _str('category');
  String get description => _str('description');
  String get fileUrl => _str('fileUrl');
  String get thumbUrl => _str('thumbUrl');
  String get mimeType => _str('type');
  String get error => _str('error');
  int get size => _num('size').toInt();

  String get status {
    final String value = _str('status');
    return value.isEmpty ? 'queued' : value;
  }

  String get scheduledDate => _str('scheduledDate');

  int get createdAt {
    for (final String key in <String>['timestamp', 'createdAt', 'addedAt']) {
      final num value = _num(key);
      if (value > 0) return value.toInt();
    }
    return 0;
  }

  bool get isAudioFile {
    if (raw['isMp3'] == true) return true;
    if (mimeType.startsWith('audio')) return true;
    return name.toLowerCase().endsWith('.mp3');
  }

  String get contentType {
    final String value = _str('contentType');
    if (value.isNotEmpty) return value;
    return isAudioFile ? 'RINGTONE' : 'WALLPAPER';
  }

  String get typeLabel => kTypeLabels[contentType] ?? contentType;

  bool get isAudio => contentType == 'RINGTONE' || contentType == 'AUDIO';

  bool get isVideo =>
      contentType == 'LIVE_WALLPAPER' || contentType == 'CHARGING_ANIMATION';

  List<String> get slots => kSetSlots[contentType] ?? const <String>[];

  bool get isSet => slots.isNotEmpty;

  /// URL for one slot of a 24H / Dual / Battery set.
  String slotUrl(String slot) {
    final Object? files = raw['files'];
    if (files is Map) {
      final Object? entry = files[slot];
      if (entry is String) return entry;
      if (entry is Map) {
        final Object? url = entry['fileUrl'];
        if (url != null) return url.toString();
      }
    }
    return '';
  }

  /// Every slot that actually has an uploaded image.
  List<String> get filledSlots =>
      slots.where((String slot) => slotUrl(slot).isNotEmpty).toList();

  /// Image shown on the phone mock-up.
  String get previewUrl {
    if (isSet) {
      for (final String slot in slots) {
        final String url = slotUrl(slot);
        if (url.isNotEmpty) return url;
      }
    }
    if (fileUrl.isNotEmpty && !isAudio) return fileUrl;
    return thumbUrl;
  }

  /// Frames used by the auto presentation preview.
  List<PreviewFrame> get previewFrames {
    if (isSet) {
      return filledSlots
          .map((String slot) => PreviewFrame(
                url: slotUrl(slot),
                label: slot[0].toUpperCase() + slot.substring(1),
              ))
          .toList();
    }
    final String url = previewUrl;
    if (url.isEmpty) return const <PreviewFrame>[];
    return <PreviewFrame>[
      PreviewFrame(url: url, label: title.isEmpty ? name : title),
    ];
  }

  String get displayTitle {
    if (title.isNotEmpty) return title;
    if (name.isNotEmpty) return name;
    return typeLabel;
  }
}

class PreviewFrame {
  const PreviewFrame({required this.url, required this.label});

  final String url;
  final String label;
}

/// Aggregated `uploadState` node - drives the daily rotation card.
class UploadState {
  const UploadState({
    required this.lastUploadDate,
    required this.uploadDayType,
    required this.totalUploadsToday,
  });

  factory UploadState.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return const UploadState(
        lastUploadDate: '',
        uploadDayType: '',
        totalUploadsToday: 0,
      );
    }
    final Object? total = map['totalUploadsToday'];
    return UploadState(
      lastUploadDate: (map['lastUploadDate'] ?? '').toString(),
      uploadDayType: (map['uploadDayType'] ?? '').toString(),
      totalUploadsToday: total is num ? total.toInt() : 0,
    );
  }

  final String lastUploadDate;
  final String uploadDayType;
  final int totalUploadsToday;

  /// The type the bot will publish today, following the daily cycle.
  String typeForToday(String todayKey) {
    if (lastUploadDate == todayKey && uploadDayType.isNotEmpty) {
      return uploadDayType;
    }
    final int index = kTypeCycle.indexOf(uploadDayType);
    if (index == -1) return kTypeCycle.first;
    return kTypeCycle[(index + 1) % kTypeCycle.length];
  }

  int uploadsToday(String todayKey) =>
      lastUploadDate == todayKey ? totalUploadsToday : 0;
}
