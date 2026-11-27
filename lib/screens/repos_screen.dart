import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/sealed_box.dart';
import '../widgets/app_widgets.dart';

/// Repos (v7.11): per-user GitHub deploy cards, ported from the Hermes
/// panel's Repos section. Cards live on the worker per user
/// (__system/repos/<user>.json); every GitHub call goes straight to
/// api.github.com with the card's own token. Push secrets (libsodium
/// sealed-box) is implemented in pure Dart (utils/sealed_box.dart,
/// verified against libsodium), so secrets push works here too.
class ReposScreen extends StatefulWidget {
  const ReposScreen({super.key});

  @override
  State<ReposScreen> createState() => _ReposScreenState();
}

class _ReposScreenState extends State<ReposScreen> {
  List<RepoCard> _cards = [];
  bool _loading = true;
  String? _error;

  ApiClient get _api => context.read<SessionProvider>().api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cards = await _api.getRepos();
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.status == 404
            ? 'Worker update dorkar — Repos er jonno Worker v7.11 lagbe.'
            : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _save({bool quiet = true}) async {
    final ok = await guard(context, () async {
      await _api.saveRepos(_cards);
      return true;
    });
    if (ok == true && !quiet && mounted) showMsg(context, 'Repositories saved');
  }

  String _newId() =>
      'r${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${Random().nextInt(99999)}';

  Future<void> _addCard() async {
    final card = RepoCard(id: _newId());
    final edited = await _editCard(card, isNew: true);
    if (edited != null && mounted) {
      setState(() => _cards.add(edited));
      _save();
    }
  }

  Future<RepoCard?> _editCard(RepoCard card, {bool isNew = false}) {
    return Navigator.push<RepoCard>(
      context,
      MaterialPageRoute(
        builder: (_) => _RepoEditor(card: card, isNew: isNew),
      ),
    );
  }

  // ---------------- GitHub actions ----------------

  bool _require(RepoCard r) {
    if (r.token.isEmpty || r.owner.isEmpty || r.name.isEmpty) {
      showMsg(context, 'Fill owner, repository and token first', error: true);
      return false;
    }
    return true;
  }

  Future<Map<String, dynamic>> _ensureRepo(
      RepoCard r, void Function(String) log) async {
    try {
      final d = await _api.gh(r.token, 'GET', '/repos/${r.owner}/${r.name}');
      return Map<String, dynamic>.from(d as Map);
    } on ApiException catch (e) {
      if (e.status != 404) rethrow;
    }
    log('repo ${r.owner}/${r.name} not found - creating it as ${r.isPrivate ? 'PRIVATE' : 'PUBLIC'}...');
    final me = await _api.gh(r.token, 'GET', '/user');
    final login = (me as Map)['login']?.toString() ?? '';
    final mine = login.toLowerCase() == r.owner.toLowerCase();
    final body = {
      'name': r.name,
      'private': r.isPrivate,
      'auto_init': false,
      'description': 'Created by Team Drive panel',
    };
    final d = await _api.gh(r.token, 'POST',
        mine ? '/user/repos' : '/orgs/${r.owner}/repos', body);
    final info = Map<String, dynamic>.from(d as Map);
    log('created ${info['full_name']} (${r.isPrivate ? 'private' : 'public'})');
    return info;
  }

  Future<void> _runWithLog(
      String title,
      Future<void> Function(void Function(String) log,
              void Function(double) prog)
          fn) async {
    final logs = ValueNotifier<List<String>>([]);
    final progress = ValueNotifier<double>(0);
    void log(String m) => logs.value = [...logs.value, m];
    final dialog = showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 15)),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ValueListenableBuilder<double>(
                valueListenable: progress,
                builder: (_, v, __) =>
                    LinearProgressIndicator(value: v > 0 ? v : null),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ValueListenableBuilder<List<String>>(
                  valueListenable: logs,
                  builder: (_, lines, __) => SingleChildScrollView(
                    child: Text(
                      lines.join('\n'),
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 11.5, height: 1.6),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Close')),
        ],
      ),
    );
    try {
      await fn(log, (v) => progress.value = v);
      log('— done —');
    } catch (e) {
      log('ERROR: ${e is ApiException ? e.message : e}');
    }
    await dialog;
  }

  Future<void> _test(RepoCard r) => _runWithLog('Test connection', (log, prog) async {
        final me = await _api.gh(r.token, 'GET', '/user');
        log('token OK - ${(me as Map)['login']}');
        final repo =
            await _api.gh(r.token, 'GET', '/repos/${r.owner}/${r.name}');
        final m = Map<String, dynamic>.from(repo as Map);
        log('repo OK - ${m['full_name']} (default: ${m['default_branch']}, ${(m['private'] == true) ? 'private' : 'public'})');
        prog(1);
      });

  bool _skipPath(String p) =>
      p.endsWith('.pyc') ||
      p.endsWith('.DS_Store') ||
      '/$p'.contains('/.git/') ||
      '/$p'.contains('/__pycache__/') ||
      '/$p'.contains('/node_modules/') ||
      '/$p'.contains('/.venv/');

  Future<void> _pushFiles(RepoCard r) async {
    if (!_require(r)) return;
    final picked = await FilePicker.platform
        .pickFiles(allowMultiple: true, withData: false);
    if (picked == null || picked.files.isEmpty || !mounted) return;
    final files = picked.files
        .where((f) => f.path != null && !_skipPath(f.name))
        .toList();
    if (files.isEmpty) {
      showMsg(context, 'No pushable files', error: true);
      return;
    }
    await _runWithLog('Push files — ${r.owner}/${r.name}', (log, prog) async {
      final info = await _ensureRepo(r, log);
      log('repo: ${info['full_name']}');
      final o = r.owner, n = r.name, b = r.branch.isEmpty ? 'main' : r.branch;
      List<dynamic> parents = [];
      String? baseTree;
      var bootstrapped = false;
      try {
        final r0 =
            await _api.gh(r.token, 'GET', '/repos/$o/$n/git/ref/heads/$b');
        final sha = (r0 as Map)['object']['sha'].toString();
        parents = [sha];
        final c0 = await _api.gh(r.token, 'GET', '/repos/$o/$n/git/commits/$sha');
        baseTree = (c0 as Map)['tree']['sha'].toString();
        log("branch '$b' found");
      } catch (_) {
        try {
          final def = info['default_branch'].toString();
          final r1 =
              await _api.gh(r.token, 'GET', '/repos/$o/$n/git/ref/heads/$def');
          final sha = (r1 as Map)['object']['sha'].toString();
          await _api.gh(r.token, 'POST', '/repos/$o/$n/git/refs',
              {'ref': 'refs/heads/$b', 'sha': sha});
          parents = [sha];
          final c0 =
              await _api.gh(r.token, 'GET', '/repos/$o/$n/git/commits/$sha');
          baseTree = (c0 as Map)['tree']['sha'].toString();
          log("branch '$b' created from '$def'");
        } catch (_) {
          log('empty repo detected');
        }
      }
      if (parents.isEmpty) {
        log("initializing empty repo on '$b'...");
        final init = await _api.gh(r.token, 'PUT',
            '/repos/$o/$n/contents/.td-init', {
          'message': 'initialize repository',
          'content': base64Encode(utf8.encode('init')),
          'branch': b,
        });
        final sha = (init as Map)['commit']['sha'].toString();
        parents = [sha];
        final c0 = await _api.gh(r.token, 'GET', '/repos/$o/$n/git/commits/$sha');
        baseTree = (c0 as Map)['tree']['sha'].toString();
        bootstrapped = true;
        log('repo initialized - pushing files...');
      }
      final tree = <Map<String, dynamic>>[];
      var done = 0;
      for (final pf in files) {
        final f = File(pf.path!);
        final size = await f.length();
        if (size > 95 * 1024 * 1024) {
          log('SKIP ${pf.name} (over GitHub 100 MB limit)');
          done++;
          prog(done / (files.length + 3));
          continue;
        }
        final bytes = await f.readAsBytes();
        final blob = await _api.gh(r.token, 'POST', '/repos/$o/$n/git/blobs',
            {'content': base64Encode(bytes), 'encoding': 'base64'});
        final exec = pf.name.endsWith('.sh');
        tree.add({
          'path': pf.name,
          'mode': exec ? '100755' : '100644',
          'type': 'blob',
          'sha': (blob as Map)['sha'],
        });
        done++;
        prog(done / (files.length + 3));
        log('+ ${pf.name}');
      }
      if (bootstrapped) {
        tree.add(
            {'path': '.td-init', 'mode': '100644', 'type': 'blob', 'sha': null});
      }
      log('building tree...');
      final nt = await _api.gh(r.token, 'POST', '/repos/$o/$n/git/trees',
          {if (baseTree != null) 'base_tree': baseTree, 'tree': tree});
      final commit =
          await _api.gh(r.token, 'POST', '/repos/$o/$n/git/commits', {
        'message': r.message.isEmpty ? 'Update from Team Drive' : r.message,
        'tree': (nt as Map)['sha'],
        'parents': parents,
      });
      final csha = (commit as Map)['sha'];
      try {
        await _api.gh(r.token, 'PATCH', '/repos/$o/$n/git/refs/heads/$b',
            {'sha': csha, 'force': true});
      } catch (_) {
        await _api.gh(r.token, 'POST', '/repos/$o/$n/git/refs',
            {'ref': 'refs/heads/$b', 'sha': csha});
      }
      prog(1);
      log('DONE - ${files.length} files -> https://github.com/$o/$n/tree/$b');
    });
  }


  Future<void> _pushSecrets(RepoCard r) async {
    if (!_require(r)) return;
    final nameOk = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
    final rows = r.extraSecrets
        .where((e) =>
            nameOk.hasMatch(e.name.trim()) &&
            e.value.isNotEmpty &&
            !e.name.trim().toUpperCase().startsWith('GITHUB_'))
        .toList();
    if (rows.isEmpty) {
      showMsg(context, 'Age card e custom secret row add korun (Edit card)',
          error: true);
      return;
    }
    await _runWithLog('Push secrets — ${r.owner}/${r.name}', (log, prog) async {
      await _ensureRepo(r, log);
      final pkRes = await _api.gh(r.token, 'GET',
          '/repos/${r.owner}/${r.name}/actions/secrets/public-key');
      final pkMap = Map<String, dynamic>.from(pkRes as Map);
      final pubKey = base64Decode(pkMap['key'].toString());
      final keyId = pkMap['key_id'].toString();
      var i = 0;
      for (final row in rows) {
        final nm = row.name.trim();
        final sealed = sealForGitHub(utf8.encode(row.value), pubKey);
        await _api.gh(r.token, 'PUT',
            '/repos/${r.owner}/${r.name}/actions/secrets/$nm',
            {'encrypted_value': base64Encode(sealed), 'key_id': keyId});
        i++;
        prog(i / rows.length);
        log('+ secret $nm');
      }
      log('DONE - ${rows.length} secrets synced (encrypted locally on this device)');
    });
  }

  Future<void> _runAction(RepoCard r) async {
    if (!_require(r)) return;
    if (r.workflow.isEmpty) {
      showMsg(context, 'Workflow file din (e.g. build.yml)', error: true);
      return;
    }
    final wf = r.workflow.split('/').last;
    await _runWithLog('Run action — $wf', (log, prog) async {
      var ref = r.branch;
      if (ref.isEmpty) {
        final repo =
            await _api.gh(r.token, 'GET', '/repos/${r.owner}/${r.name}');
        ref = (repo as Map)['default_branch']?.toString() ?? 'main';
      }
      try {
        await _api.gh(r.token, 'POST',
            '/repos/${r.owner}/${r.name}/actions/workflows/$wf/dispatches',
            {'ref': ref});
      } on ApiException catch (e) {
        if (e.status == 404) {
          throw ApiException(404,
              '$wf not found on branch "$ref" - push the repo files first (workflow_dispatch thakte hobe)');
        }
        rethrow;
      }
      log('run dispatched ($wf @ $ref)');
      log('watch it: https://github.com/${r.owner}/${r.name}/actions');
      prog(1);
    });
  }

  Future<void> _stopRuns(RepoCard r) async {
    if (!_require(r)) return;
    await _runWithLog('Stop runs — ${r.owner}/${r.name}', (log, prog) async {
      final base = '/repos/${r.owner}/${r.name}/actions/runs';
      final active = <dynamic>[];
      for (final st in ['in_progress', 'queued', 'requested', 'waiting']) {
        final d = await _api.gh(r.token, 'GET', '$base?status=$st&per_page=50');
        active.addAll(((d as Map)['workflow_runs'] as List?) ?? []);
      }
      if (active.isEmpty) {
        log('no active runs to stop');
        prog(1);
        return;
      }
      var n = 0;
      for (final run in active) {
        try {
          await _api.gh(r.token, 'POST', '$base/${run['id']}/cancel');
          log('cancelled: ${run['name'] ?? 'run'} #${run['run_number']}');
          n++;
        } catch (e) {
          log('could not cancel #${run['run_number']}: $e');
        }
      }
      prog(1);
      log('$n run(s) cancelled');
    });
  }


  /// Delete the repo's whole Actions run history: cancel active runs,
  /// wait for them to finish, then DELETE every run (GitHub has no bulk API).
  Future<void> _cleanRuns(RepoCard r, void Function(String) log) async {
    final base = '/repos/${r.owner}/${r.name}/actions/runs';
    Future<List<dynamic>> listAll() async {
      final all = <dynamic>[];
      for (var page = 1; page <= 20; page++) {
        final d = await _api.gh(r.token, 'GET', '$base?per_page=100&page=$page');
        final runs = ((d as Map)['workflow_runs'] as List?) ?? [];
        all.addAll(runs);
        if (runs.length < 100) break;
      }
      return all;
    }

    var runs = await listAll();
    if (runs.isEmpty) {
      log('actions history: already clean');
      return;
    }
    log('actions history: ${runs.length} run(s) found - cleaning...');
    final active = runs.where((x) => x['status'] != 'completed').toList();
    if (active.isNotEmpty) {
      for (final run in active) {
        try {
          await _api.gh(r.token, 'POST', '$base/${run['id']}/cancel');
        } catch (_) {}
      }
      log('actions history: ${active.length} active run(s) cancel kore wait korchi...');
      for (var i = 0; i < 6 && active.isNotEmpty; i++) {
        await Future.delayed(const Duration(seconds: 5));
        for (var j = active.length - 1; j >= 0; j--) {
          try {
            final d = await _api.gh(r.token, 'GET', '$base/${active[j]['id']}');
            if ((d as Map)['status'] == 'completed') active.removeAt(j);
          } catch (_) {
            active.removeAt(j);
          }
        }
      }
      runs = await listAll();
    }
    var ok = 0, fail = 0;
    for (final run in runs) {
      try {
        await _api.gh(r.token, 'DELETE', '$base/${run['id']}');
        ok++;
      } catch (_) {
        fail++;
      }
    }
    log('actions history: $ok run deleted${fail > 0 ? ', $fail ta delete hoy nai (abar Clean chalale jabe)' : ' - puro history clean'}');
  }

  Future<void> _clean(RepoCard r) async {
    if (!_require(r)) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Clean repo?'),
        content: Text(
            '${r.owner}/${r.name} er SOB file ekta commit e delete hobe (git history thakbe). Sathe Actions er sob workflow run history (logs) o delete hobe.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Clean repo')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await _runWithLog('Clean repo — ${r.owner}/${r.name}', (log, prog) async {
      var ref = r.branch;
      if (ref.isEmpty) {
        final repo =
            await _api.gh(r.token, 'GET', '/repos/${r.owner}/${r.name}');
        ref = (repo as Map)['default_branch']?.toString() ?? 'main';
      }
      final full = '${r.owner}/${r.name}';
      String cur;
      try {
        final d = await _api.gh(
            r.token, 'GET', '/repos/$full/git/ref/heads/$ref');
        cur = (d as Map)['object']['sha'].toString();
      } on ApiException catch (e) {
        if (e.status == 404 || e.status == 409) {
          log('repository is already empty - files nai, sudhu history check korchi');
          try { await _cleanRuns(r, log); } catch (_) {}
          prog(1);
          return;
        }
        rethrow;
      }
      const emptyTree = '4b825dc642cb6eb9a060e54bf8d69288fbee4904';
      dynamic commit;
      try {
        commit = await _api.gh(r.token, 'POST', '/repos/$full/git/commits', {
          'message': 'clean repository - all files removed via Team Drive panel',
          'tree': emptyTree,
          'parents': [cur],
        });
      } catch (_) {
        final cc =
            await _api.gh(r.token, 'GET', '/repos/$full/git/commits/$cur');
        final treeSha = (cc as Map)['tree']['sha'].toString();
        final ct = await _api.gh(r.token, 'GET',
            '/repos/$full/git/trees/$treeSha?recursive=1');
        final dels = (((ct as Map)['tree'] as List?) ?? [])
            .where((t) => t['type'] == 'blob')
            .map((t) => {
                  'path': t['path'],
                  'mode': t['mode'],
                  'type': 'blob',
                  'sha': null,
                })
            .toList();
        if (dels.isEmpty) {
          log('repository is already empty - files nai, sudhu history check korchi');
          try { await _cleanRuns(r, log); } catch (_) {}
          prog(1);
          return;
        }
        final nt = await _api.gh(r.token, 'POST', '/repos/$full/git/trees',
            {'base_tree': treeSha, 'tree': dels});
        commit = await _api.gh(r.token, 'POST', '/repos/$full/git/commits', {
          'message': 'clean repository - all files removed via Team Drive panel',
          'tree': (nt as Map)['sha'],
          'parents': [cur],
        });
      }
      await _api.gh(r.token, 'PATCH', '/repos/$full/git/refs/heads/$ref',
          {'sha': (commit as Map)['sha'], 'force': true});
      prog(1);
      log('$full cleaned - every file removed on "$ref"');
      try {
        await _cleanRuns(r, log);
      } catch (e) {
        log('actions history clean holo na: $e');
      }
    });
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final night = Theme.of(context).brightness == Brightness.dark;
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            children: [
              const Text('Repos',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _addCard,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add repository'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Text(
            'GitHub deploy cards — prottek card e alada repo + token. Cards sudhu apnar nijer account er jonno private. Secrets ei device ei encrypt hoye GitHub e jay.',
            style: TextStyle(fontSize: 12.5, color: muted),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: muted)),
                      ),
                    )
                  : _cards.isEmpty
                      ? Center(
                          child: Text('No repositories yet — "Add repository" diye prothom card banan.',
                              style: TextStyle(color: muted)),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          itemCount: _cards.length,
                          itemBuilder: (_, i) => _cardTile(_cards[i]),
                        ),
        ),
      ],
    );
  }

  Widget _cardTile(RepoCard r) {
    final night = Theme.of(context).brightness == Brightness.dark;
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    final line = night ? AppColors.nightLine : AppColors.dayLine;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: night ? AppColors.nightPanel : Colors.white,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.code, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(r.label.isEmpty ? 'Repository' : r.label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14.5),
                    overflow: TextOverflow.ellipsis),
              ),
              IconButton(
                tooltip: 'Edit card',
                icon: const Icon(Icons.edit_outlined, size: 19),
                onPressed: () async {
                  final edited = await _editCard(r);
                  if (edited != null && mounted) {
                    setState(() {
                      final i = _cards.indexOf(r);
                      if (i >= 0) _cards[i] = edited;
                    });
                    _save();
                  }
                },
              ),
              IconButton(
                tooltip: 'Remove card',
                icon: const Icon(Icons.delete_outline, size: 19),
                onPressed: () async {
                  final yes = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Remove card?'),
                      content: Text(
                          '"${r.label}" card delete hobe. GitHub er repo te kichu hobe na.'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: const Text('Cancel')),
                        TextButton(
                            onPressed: () => Navigator.pop(c, true),
                            child: const Text('Remove')),
                      ],
                    ),
                  );
                  if (yes == true && mounted) {
                    setState(() => _cards.remove(r));
                    _save();
                  }
                },
              ),
            ],
          ),
          Text(
            '${r.owner}/${r.name}${r.branch.isNotEmpty ? ' · ${r.branch}' : ''}${r.isPrivate ? ' · private' : ' · public'}',
            style: TextStyle(fontSize: 12.5, color: muted),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: () => _pushFiles(r),
                icon: const Icon(Icons.cloud_upload_outlined, size: 16),
                label: const Text('Push files'),
              ),
              OutlinedButton.icon(
                onPressed: () => _pushSecrets(r),
                icon: const Icon(Icons.key_outlined, size: 16),
                label: const Text('Push secrets'),
              ),
              OutlinedButton.icon(
                onPressed: () => _test(r),
                icon: const Icon(Icons.check_circle_outline, size: 16),
                label: const Text('Test'),
              ),
              OutlinedButton.icon(
                onPressed: () => _runAction(r),
                icon: const Icon(Icons.play_arrow_outlined, size: 16),
                label: const Text('Run'),
              ),
              OutlinedButton.icon(
                onPressed: () => _stopRuns(r),
                icon: const Icon(Icons.stop_outlined, size: 16),
                label: const Text('Stop runs'),
              ),
              OutlinedButton.icon(
                onPressed: () => _clean(r),
                icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                label: const Text('Clean'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RepoEditor extends StatefulWidget {
  final RepoCard card;
  final bool isNew;
  const _RepoEditor({required this.card, required this.isNew});

  @override
  State<_RepoEditor> createState() => _RepoEditorState();
}

class _RepoEditorState extends State<_RepoEditor> {
  late final _label = TextEditingController(text: widget.card.label);
  late final _owner = TextEditingController(text: widget.card.owner);
  late final _name = TextEditingController(text: widget.card.name);
  late final _branch = TextEditingController(text: widget.card.branch);
  late final _token = TextEditingController(text: widget.card.token);
  late final _message = TextEditingController(text: widget.card.message);
  late final _workflow = TextEditingController(text: widget.card.workflow);
  late bool _saveToken = widget.card.saveToken;
  late bool _isPrivate = widget.card.isPrivate;
  late final List<RepoSecret> _secrets =
      widget.card.extraSecrets.map((e) => RepoSecret(name: e.name, value: e.value)).toList();
  bool _showToken = false;

  @override
  void dispose() {
    for (final c in [_label, _owner, _name, _branch, _token, _message, _workflow]) {
      c.dispose();
    }
    super.dispose();
  }

  RepoCard _collect() => RepoCard(
        id: widget.card.id,
        label: _label.text.trim(),
        owner: _owner.text.trim(),
        name: _name.text.trim(),
        branch: _branch.text.trim(),
        message: _message.text,
        workflow: _workflow.text.trim(),
        token: _token.text.trim(),
        saveToken: _saveToken,
        isPrivate: _isPrivate,
        extraSecrets: _secrets,
      );

  Widget _field(String label, TextEditingController c,
      {String? hint, bool obscure = false, Widget? suffix}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          suffixIcon: suffix,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'New repository' : 'Edit repository'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _collect()),
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _field('Label', _label),
          _field('Owner (user / org)', _owner),
          _field('Repository', _name),
          _field('Branch', _branch, hint: 'main'),
          _field('GitHub token (PAT)', _token,
              obscure: !_showToken,
              suffix: IconButton(
                icon: Icon(
                    _showToken ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showToken = !_showToken),
              )),
          _field('Workflow file (Run er jonno)', _workflow,
              hint: 'e.g. build.yml'),
          _field('Commit message (optional)', _message),
          SwitchListTile(
            title: const Text('Remember token in my account'),
            value: _saveToken,
            onChanged: (v) => setState(() => _saveToken = v),
          ),
          SwitchListTile(
            title: const Text('Create as private repo if missing'),
            value: _isPrivate,
            onChanged: (v) => setState(() => _isPrivate = v),
          ),
          const Divider(height: 28),
          Row(
            children: [
              const Text('Custom secrets',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton.icon(
                onPressed: () =>
                    setState(() => _secrets.add(RepoSecret())),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add'),
              ),
            ],
          ),
          const Text(
            'Secret rows card er sathe save hoy — card theke "Push secrets" dile ei device ei encrypt hoye GitHub Actions e chole jay.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _secrets.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: _secrets[i].name,
                      decoration: const InputDecoration(
                          labelText: 'SECRET_NAME',
                          border: OutlineInputBorder()),
                      onChanged: (v) => _secrets[i].name = v,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      initialValue: _secrets[i].value,
                      obscureText: true,
                      decoration: const InputDecoration(
                          labelText: 'value', border: OutlineInputBorder()),
                      onChanged: (v) => _secrets[i].value = v,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _secrets.removeAt(i)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, _collect()),
            child: const Text('Save card'),
          ),
        ],
      ),
    );
  }
}
