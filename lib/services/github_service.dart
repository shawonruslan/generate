import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_config.dart';

/// Settings of the GitHub Control panel (synced to `dashboardSettings/ghPanel`).
class GithubConfig {
  const GithubConfig({
    this.owner = '',
    this.repo = '',
    this.branch = 'main',
    this.token = '',
  });

  factory GithubConfig.fromJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const GithubConfig();
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map) {
        return GithubConfig(
          owner: (decoded['owner'] ?? '').toString(),
          repo: (decoded['repo'] ?? '').toString(),
          branch: (decoded['branch'] ?? 'main').toString(),
          token: (decoded['token'] ?? '').toString(),
        );
      }
    } catch (_) {}
    return const GithubConfig();
  }

  final String owner;
  final String repo;
  final String branch;
  final String token;

  bool get ready => owner.isNotEmpty && repo.isNotEmpty && token.isNotEmpty;
  String get branchOrMain => branch.isEmpty ? 'main' : branch;

  String toJson() => jsonEncode(<String, String>{
        'owner': owner,
        'repo': repo,
        'branch': branch,
        'token': token,
      });

  GithubConfig copyWith({
    String? owner,
    String? repo,
    String? branch,
    String? token,
  }) =>
      GithubConfig(
        owner: owner ?? this.owner,
        repo: repo ?? this.repo,
        branch: branch ?? this.branch,
        token: token ?? this.token,
      );
}

class GithubException implements Exception {
  GithubException(this.message, [this.status]);

  final String message;
  final int? status;

  @override
  String toString() => message;
}

class WorkflowRun {
  WorkflowRun(this.raw);

  final Map<String, dynamic> raw;

  int get id => (raw['id'] as num?)?.toInt() ?? 0;
  int get number => (raw['run_number'] as num?)?.toInt() ?? 0;
  String get name => (raw['name'] ?? raw['path'] ?? 'run').toString();
  String get status => (raw['status'] ?? '').toString();
  String get conclusion => (raw['conclusion'] ?? '').toString();
  String get htmlUrl => (raw['html_url'] ?? '').toString();
  String get event => (raw['event'] ?? '').toString();
  DateTime? get startedAt {
    final String s =
        (raw['run_started_at'] ?? raw['created_at'] ?? '').toString();
    return s.isEmpty ? null : DateTime.tryParse(s);
  }
  DateTime? get updatedAt {
    final String s = (raw['updated_at'] ?? '').toString();
    return s.isEmpty ? null : DateTime.tryParse(s);
  }
  bool get completed => status == 'completed';
  int get durationMinutes {
    final DateTime? start = startedAt;
    if (start == null) return 0;
    final DateTime end =
        completed ? (updatedAt ?? DateTime.now().toUtc()) : DateTime.now().toUtc();
    final int m = end.difference(start).inMinutes;
    return m < 0 ? 0 : m;
  }
}

class RepoEntry {
  RepoEntry(this.raw);

  final Map<String, dynamic> raw;

  String get name => (raw['name'] ?? '').toString();
  String get path => (raw['path'] ?? '').toString();
  String get type => (raw['type'] ?? 'file').toString();
  String get sha => (raw['sha'] ?? '').toString();
  int get size => (raw['size'] as num?)?.toInt() ?? 0;
  bool get isDir => type == 'dir';
}

/// Thin wrapper over the GitHub REST API used by the Control panel.
class GithubService {
  GithubService(this.cfg);

  final GithubConfig cfg;

  String get _repoPath => '/repos/${cfg.owner}/${cfg.repo}';

  Map<String, String> get _headers => <String, String>{
        'Authorization': 'Bearer ${cfg.token}',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'Content-Type': 'application/json',
      };

  Future<Object?> _call(String path,
      {String method = 'GET', Object? body}) async {
    final Uri uri = Uri.parse('$kGithubApi$path');
    late http.Response res;
    final String? encoded = body == null ? null : jsonEncode(body);
    switch (method) {
      case 'POST':
        res = await http.post(uri, headers: _headers, body: encoded);
        break;
      case 'PUT':
        res = await http.put(uri, headers: _headers, body: encoded);
        break;
      case 'DELETE':
        res = await http.delete(uri, headers: _headers, body: encoded);
        break;
      default:
        res = await http.get(uri, headers: _headers);
    }
    if (res.statusCode == 204) return null;
    Object? decoded;
    try {
      decoded = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {
      decoded = null;
    }
    if (res.statusCode >= 400) {
      String msg = 'HTTP ${res.statusCode}';
      if (decoded is Map && decoded['message'] != null) {
        msg = '${decoded['message']} (HTTP ${res.statusCode})';
      }
      throw GithubException(msg, res.statusCode);
    }
    return decoded;
  }

  /// Returns (repo full name, number of workflows).
  Future<String> testConnection() async {
    final Object? repo = await _call(_repoPath);
    final Object? wf = await _call('$_repoPath/actions/workflows?per_page=50');
    final String full =
        repo is Map ? (repo['full_name'] ?? cfg.repo).toString() : cfg.repo;
    int count = 0;
    if (wf is Map && wf['workflows'] is List) {
      count = (wf['workflows'] as List).length;
    }
    final String priv = repo is Map && repo['private'] == true ? 'private' : 'public';
    return 'Connected to $full ($priv) - $count workflow(s)';
  }

  Future<void> triggerWorkflow(
    String workflowFile,
    Map<String, String> inputs,
  ) async {
    await _call(
      '$_repoPath/actions/workflows/$workflowFile/dispatches',
      method: 'POST',
      body: <String, Object>{'ref': cfg.branchOrMain, 'inputs': inputs},
    );
  }

  Future<List<WorkflowRun>> listRuns({int perPage = 20, String? status}) async {
    final String q = status == null ? '' : '&status=$status';
    final Object? data =
        await _call('$_repoPath/actions/runs?per_page=$perPage$q');
    if (data is Map && data['workflow_runs'] is List) {
      return (data['workflow_runs'] as List)
          .whereType<Map>()
          .map((Map m) => WorkflowRun(Map<String, dynamic>.from(m)))
          .toList();
    }
    return <WorkflowRun>[];
  }

  Future<void> deleteRun(int id) =>
      _call('$_repoPath/actions/runs/$id', method: 'DELETE');

  static String encodePath(String p) =>
      p.split('/').map(Uri.encodeComponent).join('/');

  Future<List<RepoEntry>> listPath(String path) async {
    final Object? data = await _call(
      '$_repoPath/contents/${path.isEmpty ? '' : encodePath(path)}?ref=${Uri.encodeComponent(cfg.branchOrMain)}',
    );
    final List<Object?> items = data is List ? data : <Object?>[data];
    final List<RepoEntry> out = items
        .whereType<Map>()
        .map((Map m) => RepoEntry(Map<String, dynamic>.from(m)))
        .toList()
      ..sort((RepoEntry a, RepoEntry b) {
        if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return out;
  }

  Future<String?> fileSha(String path) async {
    try {
      final Object? data = await _call(
        '$_repoPath/contents/${encodePath(path)}?ref=${Uri.encodeComponent(cfg.branchOrMain)}',
      );
      if (data is Map && data['sha'] != null) return data['sha'].toString();
    } catch (_) {}
    return null;
  }

  /// Creates or updates a file. Returns true when an existing file was updated.
  Future<bool> pushFile(String path, List<int> bytes) async {
    final String? sha = await fileSha(path);
    final Map<String, Object> body = <String, Object>{
      'message': '${sha == null ? 'add' : 'update'}: $path (pushed from Zedge Studio)',
      'content': base64Encode(bytes),
      'branch': cfg.branchOrMain,
    };
    if (sha != null) body['sha'] = sha;
    await _call('$_repoPath/contents/${encodePath(path)}',
        method: 'PUT', body: body);
    return sha != null;
  }

  Future<void> deleteFile(RepoEntry entry) async {
    await _call(
      '$_repoPath/contents/${encodePath(entry.path)}',
      method: 'DELETE',
      body: <String, Object>{
        'message': 'chore: delete ${entry.path} (Zedge Studio repo clean)',
        'sha': entry.sha,
        'branch': cfg.branchOrMain,
      },
    );
  }
}

/// Validates a Gemini browser session JSON (cookie array or Playwright
/// storageState). Returns a human readable summary or throws.
String describeSessionJson(String raw) {
  final Object? decoded = jsonDecode(raw);
  if (decoded is List) {
    return 'cookie array, ${decoded.length} cookies';
  }
  if (decoded is Map && decoded['cookies'] is List) {
    return 'storageState, ${(decoded['cookies'] as List).length} cookies';
  }
  throw const FormatException(
      'expected a cookie array or a storageState object with "cookies"');
}
