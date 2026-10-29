import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'platform_ui.dart';

/// Keeps long runs (Batch Sets, single images, Image to Prompt queue)
/// going while the phone sleeps.
///
/// Android: starts a foreground service with a progress notification that
/// holds a wake lock + Wi-Fi lock (see android_native/GenerationService).
/// Without it Android pauses the app / cuts its network a few minutes
/// after the screen turns off, and every queued image failed.
/// Other platforms: no-op.
class KeepAwake {
  KeepAwake._();

  static const _ch = MethodChannel('ais/keepawake');
  static bool get supported => isAndroidUi;

  static final Map<String, _Task> _tasks = {};
  static DateTime _lastPush = DateTime.fromMillisecondsSinceEpoch(0);
  static Timer? _pending;

  /// Starts (or renames) a task; the service runs while any task exists.
  static void start(String key, String title,
      {String text = 'Starting...', int done = 0, int total = 0}) {
    if (!supported) return;
    _tasks[key] = _Task(title, text, done, total);
    _push(force: true);
  }

  /// Progress of a running task (throttled to ~1 update / second).
  static void progress(String key, {String? text, int? done, int? total}) {
    if (!supported) return;
    final t = _tasks[key];
    if (t == null) return;
    if (text != null) t.text = text;
    if (done != null) t.done = done;
    if (total != null) t.total = total;
    _push();
  }

  static void stop(String key) {
    if (!supported) return;
    if (_tasks.remove(key) == null) return;
    if (_tasks.isEmpty) {
      _pending?.cancel();
      _pending = null;
      _ch.invokeMethod('stop').catchError((_) => null);
    } else {
      _push(force: true);
    }
  }

  /// Runs [body] with the phone kept awake.
  static Future<T> hold<T>(String key, String title, Future<T> Function() body,
      {String text = 'Starting...', int total = 0}) async {
    start(key, title, text: text, total: total);
    try {
      return await body();
    } finally {
      stop(key);
    }
  }

  static void _push({bool force = false}) {
    if (_tasks.isEmpty) return;
    final since = DateTime.now().difference(_lastPush);
    if (!force && since < const Duration(seconds: 1)) {
      _pending ??= Timer(const Duration(seconds: 1) - since, () {
        _pending = null;
        _push(force: true);
      });
      return;
    }
    _lastPush = DateTime.now();
    final list = _tasks.values.toList();
    final first = list.first;
    var done = 0, total = 0;
    for (final t in list) {
      done += t.done;
      total += t.total;
    }
    final title = list.length == 1
        ? first.title
        : list.map((t) => t.title).join(' + ');
    final text = list.length == 1
        ? first.text
        : list.map((t) => '${t.title}: ${t.text}').join(' · ');
    _ch.invokeMethod('start', {
      'title': title,
      'text': text,
      'done': done,
      'total': total,
    }).catchError((_) => null);
  }

  /// Whether Android battery optimisation is off for the app.
  static Future<bool> batteryUnrestricted() async {
    if (!supported) return true;
    try {
      return await _ch.invokeMethod<bool>('batteryOk') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system dialog "Let app always run in background?".
  static Future<void> askBatteryUnrestricted() async {
    if (!supported) return;
    try {
      await _ch.invokeMethod('askBattery');
    } catch (_) {}
  }

  /// Waits (up to [max]) until the internet is reachable again, e.g. right
  /// after the phone wakes up and Wi-Fi / mobile data reconnects.
  static Future<bool> waitForNetwork(
      {Duration max = const Duration(minutes: 3),
      String host = 'api.cloudinary.com'}) async {
    final end = DateTime.now().add(max);
    while (true) {
      try {
        final r = await InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 8));
        if (r.isNotEmpty) return true;
      } catch (_) {}
      if (DateTime.now().isAfter(end)) return false;
      await Future<void>.delayed(const Duration(seconds: 4));
    }
  }
}

class _Task {
  _Task(this.title, this.text, this.done, this.total);
  final String title;
  String text;
  int done;
  int total;
}
