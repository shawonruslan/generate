import 'dart:async';
import 'dart:typed_data';

import 'package:cronet_http/cronet_http.dart';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

/// A Dio [HttpClientAdapter] that routes requests through Cronet
/// (Chromium's network stack) on Android.
///
/// Dart's own DNS resolver (dart:io) can fail with "Failed host lookup" on
/// some Android devices/networks even when Chrome on the same device
/// resolves fine — Cronet uses the exact same stack as Chrome, so it
/// behaves identically.
class CronetDioAdapter implements HttpClientAdapter {
  final CronetClient _cronet = CronetClient.defaultCronetEngine();

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final uri = options.uri;

    final req = http.Request(options.method, uri);
    // Headers
    options.headers.forEach((k, v) {
      if (v != null) req.headers[k] = v.toString();
    });
    // Body
    if (requestStream != null) {
      final bytes = await _collect(requestStream, cancelFuture);
      req.bodyBytes = bytes;
    } else if (options.data != null) {
      final d = options.data;
      if (d is List<int>) {
        req.bodyBytes = Uint8List.fromList(d);
      } else if (d is String) {
        req.body = d;
      } else if (d is Map) {
        req.bodyFields = d.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    }

    http.StreamedResponse streamed;
    try {
      final future = _cronet.send(req);
      if (cancelFuture != null) {
        streamed = await Future.any([
          future,
          cancelFuture.then((_) => throw DioException(
              requestOptions: options, type: DioExceptionType.cancel)),
        ]);
      } else {
        streamed = await future;
      }
    } on http.ClientException catch (e) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: e,
      );
    }

    final headers = <String, List<String>>{};
    streamed.headers.forEach((k, v) => headers[k] = [v]);

    return ResponseBody(
      streamed.stream,
      streamed.statusCode,
      headers: headers,
      statusMessage: streamed.reasonPhrase,
      isRedirect: streamed.isRedirect,
    );
  }

  Future<Uint8List> _collect(
      Stream<Uint8List> stream, Future<void>? cancelFuture) {
    final completer = Completer<Uint8List>();
    final chunks = <int>[];
    late StreamSubscription<Uint8List> sub;
    sub = stream.listen(
      chunks.addAll,
      onDone: () => completer.complete(Uint8List.fromList(chunks)),
      onError: completer.completeError,
      cancelOnError: true,
    );
    if (cancelFuture != null) {
      cancelFuture.then((_) {
        sub.cancel();
        if (!completer.isCompleted) {
          completer.completeError(
              DioException(requestOptions: RequestOptions(path: '')));
        }
      });
    }
    return completer.future;
  }

  @override
  void close({bool force = false}) {
    _cronet.close();
  }
}
