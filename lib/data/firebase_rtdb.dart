import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/build_config.dart';
import '../core/dhaka_time.dart';

/// Firebase Realtime Database client built on the REST API + SSE streaming.
///
/// The web panel uses the Firebase JS SDK; the databases are open
/// (`.read/.write: true`, see SETUP.md) so REST works without auth. Realtime
/// listeners use `Accept: text/event-stream`, which delivers `put`/`patch`
/// events exactly like `onValue` does. `{".sv":"timestamp"}` is the REST
/// equivalent of `serverTimestamp()`.
class FirebaseRtdb {
  FirebaseRtdb(this.account) : baseUrl = account.databaseURL.replaceAll(RegExp(r'/+$'), '');

  final FirebaseAccountConfig account;
  final String baseUrl;
  final http.Client _client = http.Client();

  /// `serverTimestamp()` sentinel.
  static const Map<String, String> serverTimestamp = {'.sv': 'timestamp'};

  Uri _uri(String path, [Map<String, String>? query]) {
    final p = path.replaceAll(RegExp(r'^/+'), '').replaceAll(RegExp(r'/+$'), '');
    final u = Uri.parse(p.isEmpty ? '$baseUrl/.json' : '$baseUrl/$p.json');
    return query == null ? u : u.replace(queryParameters: query);
  }

  Future<dynamic> get(String path, {Duration timeout = const Duration(seconds: 40)}) async {
    final res = await _client.get(_uri(path)).timeout(timeout);
    _syncClock(res);
    if (res.statusCode != 200) throw FirebaseError('GET $path HTTP ${res.statusCode}: ${res.body}');
    return res.body.isEmpty ? null : jsonDecode(res.body);
  }

  Future<void> set(String path, dynamic value) async {
    final res = await _client.put(_uri(path), headers: _json, body: jsonEncode(value)).timeout(const Duration(seconds: 40));
    _syncClock(res);
    if (res.statusCode != 200) throw FirebaseError('SET $path HTTP ${res.statusCode}: ${res.body}');
  }

  /// Multi-location update (`update(ref(db), patch)`); keys may contain slashes.
  Future<void> update(String path, Map<String, dynamic> patch) async {
    if (patch.isEmpty) return;
    final res = await _client.patch(_uri(path), headers: _json, body: jsonEncode(patch)).timeout(const Duration(seconds: 60));
    _syncClock(res);
    if (res.statusCode != 200) throw FirebaseError('UPDATE $path HTTP ${res.statusCode}: ${res.body}');
  }

  Future<void> remove(String path) async {
    final res = await _client.delete(_uri(path)).timeout(const Duration(seconds: 40));
    _syncClock(res);
    if (res.statusCode != 200) throw FirebaseError('REMOVE $path HTTP ${res.statusCode}: ${res.body}');
  }

  /// `push()` - returns the generated key.
  Future<String> push(String path, dynamic value) async {
    final res = await _client.post(_uri(path), headers: _json, body: jsonEncode(value)).timeout(const Duration(seconds: 40));
    _syncClock(res);
    if (res.statusCode != 200) throw FirebaseError('PUSH $path HTTP ${res.statusCode}: ${res.body}');
    final j = jsonDecode(res.body);
    return j is Map && j['name'] != null ? '${j['name']}' : '';
  }

  /// Ask the server for its clock (`.info/serverTimeOffset` replacement).
  Future<void> syncServerTime() async {
    try {
      final t0 = DateTime.now().millisecondsSinceEpoch;
      final res = await _client.get(_uri('.info/connected')).timeout(const Duration(seconds: 10));
      final t1 = DateTime.now().millisecondsSinceEpoch;
      final date = res.headers['date'];
      if (date != null) {
        final server = _parseHttpDate(date);
        if (server != null) RealTime.instance.setFirebaseOffset(server.millisecondsSinceEpoch + 500 - ((t0 + t1) ~/ 2));
      }
    } catch (_) {}
  }

  void _syncClock(http.Response res) {
    if (RealTime.instance.synced) return;
    final date = res.headers['date'];
    if (date == null) return;
    final server = _parseHttpDate(date);
    if (server != null) RealTime.instance.setFirebaseOffset(server.millisecondsSinceEpoch + 500 - DateTime.now().millisecondsSinceEpoch);
  }

  static DateTime? _parseHttpDate(String s) {
    try {
      return http_date_parse(s);
    } catch (_) {
      return null;
    }
  }

  /// Firebase sends an SSE `keep-alive` every ~30 s. If nothing at all arrives for
  /// this long the socket is dead (PC sleep, Wi-Fi switch, NAT/VPN drop) even though
  /// no error was raised - the mirror would silently stay stale (v27.10 fix for
  /// "app/desktop shows old metadata while the web panel is correct").
  static const Duration staleAfter = Duration(seconds: 75);

  /// `onValue(ref(db, path), cb)` - emits the full value at [path] on every change.
  /// Reconnects automatically with back-off; never throws into the stream.
  /// [onConnection] reports live (true) / lost (false) so the UI can show it.
  Stream<dynamic> stream(String path, {void Function(bool connected)? onConnection}) {
    late StreamController<dynamic> ctrl;
    var closed = false;
    http.Client? sseClient;
    dynamic tree;
    var backoff = 1;
    var lastEventAt = DateTime.now();
    Timer? watchdog;

    Future<void> connect() async {
      while (!closed) {
        final client = http.Client();
        sseClient = client;
        lastEventAt = DateTime.now();
        watchdog?.cancel();
        watchdog = Timer.periodic(const Duration(seconds: 15), (_) {
          if (closed) return;
          if (DateTime.now().difference(lastEventAt) > staleAfter) {
            // Dead socket: closing the client aborts the await-for below -> reconnect below fetches a
            // fresh full snapshot (`put /`) so the local mirror is re-synced with the server.
            client.close();
          }
        });
        try {
          final req = http.Request('GET', _uri(path))
            ..headers['Accept'] = 'text/event-stream'
            ..headers['Cache-Control'] = 'no-cache';
          req.followRedirects = true;
          final res = await client.send(req).timeout(const Duration(seconds: 30));
          if (res.statusCode != 200) throw FirebaseError('stream $path HTTP ${res.statusCode}');
          backoff = 1;
          String? event;
          final buf = StringBuffer();
          await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
            if (closed) break;
            lastEventAt = DateTime.now();
            if (line.startsWith('event:')) {
              event = line.substring(6).trim();
            } else if (line.startsWith('data:')) {
              buf.write(line.substring(5).trim());
            } else if (line.isEmpty) {
              final data = buf.toString();
              buf.clear();
              if (event == null) continue;
              if (event == 'put' || event == 'patch') {
                final payload = data.isEmpty ? null : jsonDecode(data);
                if (payload is Map) {
                  final p = '${payload['path'] ?? '/'}';
                  final d = payload['data'];
                  tree = event == 'put' ? _applyPut(tree, p, d) : _applyPatch(tree, p, d);
                  if (!ctrl.isClosed) ctrl.add(_deepCopy(tree));
                  onConnection?.call(true);
                }
              } else if (event == 'cancel' || event == 'auth_revoked') {
                break;
              }
              event = null;
            }
          }
        } catch (_) {
          // fall through to reconnect
        } finally {
          watchdog?.cancel();
          client.close();
        }
        if (closed) break;
        onConnection?.call(false);
        await Future.delayed(Duration(seconds: backoff));
        backoff = (backoff * 2).clamp(1, 30).toInt();
      }
    }

    ctrl = StreamController<dynamic>.broadcast(
      onListen: () {
        if (!closed) unawaited(connect());
      },
      onCancel: () {
        closed = true;
        watchdog?.cancel();
        sseClient?.close();
      },
    );
    return ctrl.stream;
  }

  static List<String> _segs(String p) => p.split('/').where((s) => s.isNotEmpty).toList();

  static dynamic _applyPut(dynamic tree, String path, dynamic data) {
    final segs = _segs(path);
    if (segs.isEmpty) return data;
    final root = tree is Map ? Map<String, dynamic>.from(tree) : <String, dynamic>{};
    Map<String, dynamic> node = root;
    for (var i = 0; i < segs.length - 1; i++) {
      final next = node[segs[i]];
      final m = next is Map ? Map<String, dynamic>.from(next) : <String, dynamic>{};
      node[segs[i]] = m;
      node = m;
    }
    if (data == null) {
      node.remove(segs.last);
    } else {
      node[segs.last] = data;
    }
    return _prune(root);
  }

  static dynamic _applyPatch(dynamic tree, String path, dynamic data) {
    var t = tree;
    if (data is Map) {
      data.forEach((k, v) {
        t = _applyPut(t, '$path/$k', v);
      });
    }
    return t;
  }

  static dynamic _prune(dynamic node) {
    if (node is Map) {
      final out = <String, dynamic>{};
      node.forEach((k, v) {
        final pv = _prune(v);
        if (pv != null) out['$k'] = pv;
      });
      return out.isEmpty ? null : out;
    }
    return node;
  }

  static dynamic _deepCopy(dynamic v) {
    if (v is Map) return v.map((k, val) => MapEntry('$k', _deepCopy(val)));
    if (v is List) return v.map(_deepCopy).toList();
    return v;
  }

  static const Map<String, String> _json = {'Content-Type': 'application/json'};

  void dispose() => _client.close();
}

class FirebaseError implements Exception {
  FirebaseError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// RFC 1123 date parser ("Sun, 06 Nov 1994 08:49:37 GMT").
// ignore: non_constant_identifier_names
DateTime http_date_parse(String s) {
  final m = RegExp(r'^\w{3}, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$').firstMatch(s.trim());
  if (m == null) throw const FormatException('bad http date');
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return DateTime.utc(int.parse(m.group(3)!), months.indexOf(m.group(2)!) + 1, int.parse(m.group(1)!), int.parse(m.group(4)!), int.parse(m.group(5)!), int.parse(m.group(6)!));
}

/// Converts a Firebase value (Map keyed by id, or List) into `[id, value]` entries.
List<MapEntry<String, Map<String, dynamic>>> firebaseEntries(dynamic data) {
  final out = <MapEntry<String, Map<String, dynamic>>>[];
  if (data is Map) {
    data.forEach((k, v) {
      out.add(MapEntry('$k', v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{}));
    });
  } else if (data is List) {
    for (var i = 0; i < data.length; i++) {
      final v = data[i];
      if (v != null) out.add(MapEntry('$i', v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{}));
    }
  }
  return out;
}
