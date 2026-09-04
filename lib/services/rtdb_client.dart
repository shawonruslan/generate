import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thin Firebase Realtime Database client built on the plain REST + SSE API.
///
/// Why not the FlutterFire SDK? `firebase_database` has no Windows support, so
/// a desktop build would need a second data path. The REST/SSE API is identical
/// on Windows and Android, needs no `google-services.json`, and gives us the
/// same live updates through Server-Sent Events.
class RtdbClient {
  RtdbClient({required this.databaseUrl, http.Client? client})
      : _client = client ?? http.Client();

  final String databaseUrl;
  final http.Client _client;

  Uri _uri(String path) {
    final String clean = path.replaceAll(RegExp(r'^/+'), '');
    return Uri.parse('$databaseUrl/$clean.json');
  }

  Future<Object?> read(String path) async {
    final http.Response res = await _client.get(_uri(path));
    if (res.statusCode >= 400) {
      throw RtdbException('GET $path failed (${res.statusCode})');
    }
    if (res.body.isEmpty) return null;
    return jsonDecode(res.body);
  }

  Future<Map<String, dynamic>> readMap(String path) async {
    final Object? body = await read(path);
    if (body is Map) return Map<String, dynamic>.from(body);
    return <String, dynamic>{};
  }

  /// Merge-update (same semantics as the web SDK `update()`).
  Future<void> patch(String path, Map<String, dynamic> data) async {
    final http.Response res = await _client.patch(
      _uri(path),
      headers: const <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    if (res.statusCode >= 400) {
      throw RtdbException('PATCH $path failed (${res.statusCode})');
    }
  }

  Future<void> put(String path, Object? data) async {
    final http.Response res = await _client.put(
      _uri(path),
      headers: const <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    if (res.statusCode >= 400) {
      throw RtdbException('PUT $path failed (${res.statusCode})');
    }
  }

  /// Creates a child with a server generated key and returns that key.
  Future<String> push(String path, Map<String, dynamic> data) async {
    final http.Response res = await _client.post(
      _uri(path),
      headers: const <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    if (res.statusCode >= 400) {
      throw RtdbException('POST $path failed (${res.statusCode})');
    }
    final Object? body = jsonDecode(res.body.isEmpty ? '{}' : res.body);
    if (body is Map && body['name'] != null) return body['name'].toString();
    throw RtdbException('POST $path returned no key');
  }

  Future<void> delete(String path) async {
    final http.Response res = await _client.delete(_uri(path));
    if (res.statusCode >= 400) {
      throw RtdbException('DELETE $path failed (${res.statusCode})');
    }
  }

  /// Live view of a map node. Emits the full merged snapshot on every change.
  RtdbWatcher watchMap(String path) =>
      RtdbWatcher(client: this, httpClient: _client, path: path);

  void close() => _client.close();
}

class RtdbException implements Exception {
  RtdbException(this.message);

  final String message;

  @override
  String toString() => 'RtdbException: $message';
}

/// Keeps a local copy of a node in sync using Server-Sent Events, and silently
/// degrades to polling when a network or proxy blocks event streams.
class RtdbWatcher {
  RtdbWatcher({
    required RtdbClient client,
    required http.Client httpClient,
    required this.path,
    this.pollInterval = const Duration(seconds: 10),
  })  : _client = client,
        _httpClient = httpClient {
    _controller = StreamController<Map<String, dynamic>>.broadcast(
      onListen: _start,
    );
  }

  final RtdbClient _client;
  final http.Client _httpClient;
  final String path;
  final Duration pollInterval;

  late final StreamController<Map<String, dynamic>> _controller;
  Map<String, dynamic> _cache = <String, dynamic>{};
  StreamSubscription<String>? _sseSub;
  Timer? _pollTimer;
  bool _closed = false;
  bool _started = false;

  Stream<Map<String, dynamic>> get stream => _controller.stream;
  Map<String, dynamic> get value => _cache;

  void _start() {
    if (_started || _closed) return;
    _started = true;
    _connect();
  }

  Future<void> _connect() async {
    if (_closed) return;
    try {
      final Uri uri = Uri.parse(
        '${_client.databaseUrl}/${path.replaceAll(RegExp(r'^/+'), '')}.json',
      );
      final http.Request request = http.Request('GET', uri);
      request.headers['Accept'] = 'text/event-stream';
      request.headers['Cache-Control'] = 'no-cache';
      request.followRedirects = true;
      final http.StreamedResponse response = await _httpClient.send(request);
      if (response.statusCode != 200) {
        throw RtdbException('stream refused (${response.statusCode})');
      }

      // First payload arrives as a `put` on "/" - no manual priming needed.
      String eventName = '';
      _sseSub = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (String line) {
          if (line.startsWith('event:')) {
            eventName = line.substring(6).trim();
            return;
          }
          if (!line.startsWith('data:')) return;
          final String payload = line.substring(5).trim();
          if (payload.isEmpty || payload == 'null') return;
          if (eventName == 'keep-alive' || eventName == 'auth_revoked') return;
          try {
            final Object? decoded = jsonDecode(payload);
            if (decoded is Map) {
              _applyEvent(
                (decoded['path'] ?? '/').toString(),
                decoded['data'],
              );
            }
          } catch (_) {
            // A partial frame is harmless - the next full event repairs state.
          }
        },
        onError: (Object error) => _fallback(error),
        onDone: () => _fallback('stream closed'),
        cancelOnError: true,
      );
    } catch (error) {
      _fallback(error);
    }
  }

  void _applyEvent(String eventPath, Object? data) {
    final List<String> parts = eventPath
        .split('/')
        .where((String part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) {
      _cache = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    } else if (parts.length == 1) {
      if (data == null) {
        _cache.remove(parts.first);
      } else {
        _cache[parts.first] = data;
      }
    } else {
      final Object? childRaw = _cache[parts.first];
      final Map<String, dynamic> child =
          childRaw is Map ? Map<String, dynamic>.from(childRaw) : <String, dynamic>{};
      Map<String, dynamic> cursor = child;
      for (int i = 1; i < parts.length - 1; i++) {
        final Object? next = cursor[parts[i]];
        final Map<String, dynamic> nextMap =
            next is Map ? Map<String, dynamic>.from(next) : <String, dynamic>{};
        cursor[parts[i]] = nextMap;
        cursor = nextMap;
      }
      final String leaf = parts.last;
      if (data == null) {
        cursor.remove(leaf);
      } else {
        cursor[leaf] = data;
      }
      _cache[parts.first] = child;
    }

    if (!_controller.isClosed) {
      _controller.add(Map<String, dynamic>.from(_cache));
    }
  }

  /// Event streams can be blocked by corporate proxies - poll instead.
  void _fallback(Object reason) {
    if (_closed) return;
    _sseSub?.cancel();
    _sseSub = null;
    if (_pollTimer != null) return;
    _pollOnce();
    _pollTimer = Timer.periodic(pollInterval, (_) => _pollOnce());
  }

  Future<void> _pollOnce() async {
    if (_closed) return;
    try {
      final Map<String, dynamic> fresh = await _client.readMap(path);
      _cache = fresh;
      if (!_controller.isClosed) {
        _controller.add(Map<String, dynamic>.from(_cache));
      }
    } catch (_) {
      // Offline - keep the last known snapshot on screen.
    }
  }

  Future<void> close() async {
    _closed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    await _sseSub?.cancel();
    _sseSub = null;
    await _controller.close();
  }
}
