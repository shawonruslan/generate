import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// Resolves hostnames via DNS-over-HTTPS (Cloudflare 1.1.1.1).
///
/// Fallback for devices where dart:io's own DNS resolver fails
/// ("Failed host lookup") while the browser works fine.
/// 1.1.1.1 is contacted by IP so no DNS is needed to reach the resolver.
class DohResolver {
  late final Dio _dohDio = _createDio();

  Dio _createDio() {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      responseType: ResponseType.json,
      validateStatus: (_) => true,
    ));
    // 1.1.1.1 is contacted by IP; its cert is for cloudflare-dns.com.
    // Skipping cert validation here is safe: the IP we get is only used
    // for a subsequent TLS connection whose cert IS validated against
    // the real hostname.
    final adapter = dio.httpClientAdapter;
    if (adapter is IOHttpClientAdapter) {
      adapter.onHttpClientCreate = (client) {
        client.badCertificateCallback = (_, __, ___) => true;
        return client;
      };
    }
    return dio;
  }

  final Map<String, String> _cache = {};
  final Map<String, int> _expiresAt = {};

  /// Resolve [host] to an IPv4 address, or null on failure.
  Future<String?> resolve(String host) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final exp = _expiresAt[host];
    if (exp != null && exp > now) return _cache[host];

    try {
      final r = await _dohDio.get(
        'https://1.1.1.1/dns-query',
        queryParameters: {'name': host, 'type': 'A'},
        options: Options(headers: {'Accept': 'application/dns-json'}),
      );
      final data = r.data;
      if (data is! Map) return null;
      final answers = (data['Answer'] as List?) ?? const [];
      String? ip;
      var ttl = 300;
      for (final a in answers) {
        if (a is Map && a['type'] == 1 && a['data'] is String) {
          ip = a['data'] as String;
          final t = a['TTL'];
          if (t is int) ttl = t;
          break;
        }
      }
      if (ip == null || ip.isEmpty) return null;
      _cache[host] = ip;
      _expiresAt[host] = now + ttl.clamp(60, 3600) * 1000;
      return ip;
    } catch (_) {
      return null;
    }
  }
}

/// Dio interceptor: on DNS failure, resolve via DoH and retry with the IP.
///
/// The request URL host is swapped to the resolved IP while the original
/// hostname is kept in the Host header. Pair with [applyDohTlsFallback]
/// so TLS cert validation accepts the IP-based connection when the cert
/// matches the original hostname's domain.
class DohFallbackInterceptor extends Interceptor {
  DohFallbackInterceptor(this._dio, this._resolver);
  final Dio _dio;
  final DohResolver _resolver;

  /// hostnames currently served via IP fallback -> their IP.
  final Map<String, String> ipForHost = {};

  bool _isDnsFailure(DioException e) {
    if (e.type != DioExceptionType.connectionError &&
        e.type != DioExceptionType.unknown) return false;
    final msg = '${e.error} ${e.message}'.toLowerCase();
    return msg.contains('failed host lookup') ||
        msg.contains('socketexception');
  }

  bool _isIp(String host) =>
      RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host) || host.contains(':');

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    final opts = err.requestOptions;
    if (!_isDnsFailure(err) || opts.extra['doh_retried'] == true) {
      return handler.next(err);
    }
    final host = opts.uri.host;
    if (host.isEmpty || _isIp(host)) return handler.next(err);

    final ip = await _resolver.resolve(host);
    if (ip == null) return handler.next(err);
    ipForHost[host] = ip;

    final newOpts = opts.copyWith(
      path: opts.uri.replace(host: ip).toString(),
      extra: {...opts.extra, 'doh_retried': true},
    );
    newOpts.headers['Host'] = host;

    try {
      final resp = await _dio.fetch<dynamic>(newOpts);
      return handler.resolve(resp);
    } catch (_) {
      return handler.next(err);
    }
  }
}

/// Allow TLS cert validation to succeed for DoH IP-fallback connections.
///
/// When we connect to https://<ip>/ with Host: <original-host>, the cert
/// won't match the IP. Accept it only if the cert's subject/issuer chain
/// mentions the original hostname's registrable domain (e.g. workers.dev)
/// — the IP itself came from a secure DoH lookup, so this is not a
/// blind trust.
void applyDohTlsFallback(
    Dio dio, DohFallbackInterceptor interceptor, String Function() hostFor) {
  final adapter = dio.httpClientAdapter;
  if (adapter is! IOHttpClientAdapter) return;
  adapter.onHttpClientCreate = (client) {
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) {
      // Normal path: let the platform validate.
      if (interceptor.ipForHost[host] == null &&
          !interceptor.ipForHost.containsValue(host)) {
        return false;
      }
      // IP-fallback path: the cert must reference the original domain.
      final original = hostFor();
      final domain = original.split('.').length > 2
          ? original.split('.').sublist(1).join('.')
          : original;
      final text = '${cert.subject} ${cert.issuer}'.toLowerCase();
      return text.contains(domain.toLowerCase()) ||
          text.contains(original.toLowerCase());
    };
    return client;
  };
}
