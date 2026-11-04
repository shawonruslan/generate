import 'package:intl/intl.dart';

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var v = bytes / 1024.0;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[i]}';
}

String formatDateTime(int ms) {
  if (ms <= 0) return '—';
  return DateFormat('dd MMM yyyy, HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ms));
}

String formatDate(int ms) {
  if (ms <= 0) return '—';
  return DateFormat('dd MMM yyyy').format(DateTime.fromMillisecondsSinceEpoch(ms));
}

String timeAgo(int ms) {
  if (ms <= 0) return '—';
  final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 30) return '${d.inDays}d ago';
  final months = (d.inDays / 30).floor();
  if (months < 12) return '${months}mo ago';
  return '${(months / 12).floor()}y ago';
}

/// Web-parity relative time — mirrors the web app's rel():
/// "just now", "3 hours ago", "1 week ago", "2 months ago".
String formatRelative(int ms) {
  if (ms <= 0) return '—';
  final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) {
    final m = d.inMinutes;
    return m == 1 ? '1 minute ago' : '$m minutes ago';
  }
  if (d.inHours < 24) {
    final h = d.inHours;
    return h == 1 ? '1 hour ago' : '$h hours ago';
  }
  if (d.inDays < 7) {
    final days = d.inDays;
    return days == 1 ? '1 day ago' : '$days days ago';
  }
  if (d.inDays < 30) {
    final w = (d.inDays / 7).floor();
    return w == 1 ? '1 week ago' : '$w weeks ago';
  }
  final months = (d.inDays / 30).floor();
  if (months < 12) return months == 1 ? '1 month ago' : '$months months ago';
  final years = (months / 12).floor();
  return years == 1 ? '1 year ago' : '$years years ago';
}

/// Epoch-millis convenience alias for [formatRelative].
String formatRelativeMs(int ms) => formatRelative(ms);

/// Mirrors the web app's cleanName(): no slashes/backslashes, no control
/// chars, trimmed, max 200 chars.
String cleanName(String name) {
  var n = name.replaceAll(RegExp(r'[\\/]'), '-').replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim();
  if (n.length > 200) n = n.substring(0, 200);
  return n;
}

String guessMime(String fileName) {
  final ext = fileName.split('.').last.toLowerCase();
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'svg':
      return 'image/svg+xml';
    case 'mp4':
      return 'video/mp4';
    case 'webm':
      return 'video/webm';
    case 'mov':
      return 'video/quicktime';
    case 'mp3':
      return 'audio/mpeg';
    case 'wav':
      return 'audio/wav';
    case 'ogg':
      return 'audio/ogg';
    case 'pdf':
      return 'application/pdf';
    case 'zip':
      return 'application/zip';
    case 'txt':
      return 'text/plain';
    case 'md':
      return 'text/markdown';
    case 'json':
      return 'application/json';
    case 'csv':
      return 'text/csv';
    case 'doc':
      return 'application/msword';
    case 'docx':
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case 'xls':
      return 'application/vnd.ms-excel';
    case 'xlsx':
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    case 'ppt':
    case 'pptx':
      return 'application/vnd.ms-powerpoint';
    case 'apk':
      return 'application/vnd.android.package-archive';
    case 'exe':
      return 'application/x-msdownload';
    default:
      return 'application/octet-stream';
  }
}

bool isImageMime(String mime) => mime.startsWith('image/');
bool isVideoMime(String mime) => mime.startsWith('video/');
bool isAudioMime(String mime) => mime.startsWith('audio/');
bool isPdfMime(String mime) => mime == 'application/pdf';

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
