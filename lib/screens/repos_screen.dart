import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:archive/archive.dart';
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
///
/// v7.12.4: UI + flow now mirror the web exactly — every card is an inline
/// editable form (label, owner, repository, branch, token + eye), FILES
/// (Choose folder… -> Push files, folder structure preserved), GITHUB ACTION
/// (workflow + Run / Stop runs + status), collapsible Options / Advanced
/// tools / Repo secrets, inline progress bar + log console, autosave, and
/// "Add repository" / "Save list" buttons. Android can also push a ZIP
/// (keeps the folder structure when direct folder access is blocked).
class ReposScreen extends StatefulWidget {
  const ReposScreen({super.key});

  /// Mobile FAB / sidebar "+ New" -> add a card (same as "Add repository").
  static VoidCallback? requestNew;

  @override
  State<ReposScreen> createState() => _ReposScreenState();
}

class _ReposScreenState extends State<ReposScreen> {
  List<RepoCard> _cards = [];
  bool _loading = true;
  String? _error;
  String _status = '';
  Timer? _saveTimer;

  /// Tokens of saveToken=false cards survive a reload during this app run
  /// (same as the web's repoSessionTokens) but are never sent to the worker.
  static final Map<String, String> _sessionTokens = {};

  late final ApiClient _api;

  @override
  void initState() {
    super.initState();
    _api = context.read<SessionProvider>().api;
    ReposScreen.requestNew = _addCard;
    _load();
  }

  @override
  void dispose() {
    if (ReposScreen.requestNew == _addCard) ReposScreen.requestNew = null;
    if (_saveTimer?.isActive == true) {
      _saveTimer!.cancel();
      final api = _api, cards = _cards;
      () async {
        try {
          await api.saveRepos(cards);
        } catch (_) {}
      }();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cards = await _api.getRepos();
      for (final c in cards) {
        if (c.token.isEmpty) c.token = _sessionTokens[c.id] ?? '';
      }
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

  Future<void> _persist({bool quiet = true}) async {
    _saveTimer?.cancel();
    try {
      await _api.saveRepos(_cards);
      if (!mounted) return;
      final t = TimeOfDay.now().format(context);
      setState(() => _status = 'Saved $t');
      if (!quiet) showMsg(context, 'Repositories saved');
    } catch (e) {
      if (!quiet && mounted) {
        showMsg(context,
            'Repo save failed: ${e is ApiException ? e.message : e}',
            error: true);
      }
    }
  }

  void _persistSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 900), _persist);
  }

  String _newId() =>
      'r${Random().nextInt(1 << 32).toRadixString(36)}${DateTime.now().millisecondsSinceEpoch % 1000}';

  void _addCard() {
    setState(() => _cards.add(RepoCard(id: _newId())));
    _persistSoon();
  }

  Future<void> _removeCard(RepoCard r) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove card?'),
        content: Text(
            '"${r.label.isNotEmpty ? r.label : (r.name.isNotEmpty ? r.name : 'repo')}" card delete hobe. GitHub er repo te kichu hobe na.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              style: TextButton.styleFrom(
                  foregroundColor: Theme.of(c).colorScheme.error),
              child: const Text('Remove')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _cards.remove(r));
    _sessionTokens.remove(r.id);
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    final night = Theme.of(context).brightness == Brightness.dark;
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    final width = MediaQuery.of(context).size.width;
    final compact = width < 600;
    final hp = compact ? 12.0 : 22.0;

    Widget body;
    if (_loading) {
      body = const Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()));
    } else if (_error != null) {
      body = _empty(Icons.cloud_off_outlined,
          _error!.startsWith('Worker') ? 'Worker update dorkar' : 'Repos load hocche na',
          _error!, muted);
    } else if (_cards.isEmpty) {
      body = _empty(Icons.code, 'No repositories yet',
          '"Add repository" click kore prothom card banan.', muted);
    } else {
      body = LayoutBuilder(builder: (c, cons) {
        const gap = 20.0;
        final cols = max(1, ((cons.maxWidth + gap) / (430 + gap)).floor());
        final w = (cons.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: compact ? 12 : gap,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            for (final r in _cards)
              SizedBox(
                width: w,
                child: _RepoCardView(
                  key: ValueKey(r.id),
                  card: r,
                  api: _api,
                  compact: compact,
                  onChanged: _persistSoon,
                  onTokenChanged: () {
                    _sessionTokens[r.id] = r.token;
                    if (r.saveToken) _persistSoon();
                  },
                  onRemove: () => _removeCard(r),
                ),
              ),
          ],
        );
      });
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(hp, compact ? 12 : 14, hp, compact ? 96 : 24),
        children: [
          Text('Repos',
              style: TextStyle(
                  fontSize: compact ? 20 : 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(children: [
              const TextSpan(
                  text: 'GitHub deploy cards — prottek card e alada repo + token. Folder push korle '),
              const TextSpan(
                  text: 'ekta clean commit',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const TextSpan(
                  text: ' e sob file jay, ar custom secrets ei device ei encrypt hoye GitHub Actions e save hoy. Cards sudhu '),
              TextSpan(
                  text: 'apnar nijer account er jonno private',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: night ? Colors.white : Colors.black87)),
              const TextSpan(
                  text: ' — onno member ba admin apnar card/token dekhte pabe na.'),
            ]),
            style: TextStyle(fontSize: compact ? 12 : 13, color: muted, height: 1.45),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _loading ? null : _addCard,
                icon: const Icon(Icons.add, size: 17),
                label: const Text('Add repository'),
              ),
              OutlinedButton.icon(
                onPressed: _loading ? null : () => _persist(quiet: false),
                icon: const Icon(Icons.save_outlined, size: 17),
                label: const Text('Save list'),
              ),
              if (_status.isNotEmpty)
                Text(_status, style: TextStyle(fontSize: 12.5, color: muted)),
            ],
          ),
          const SizedBox(height: 16),
          body,
        ],
      ),
    );
  }

  Widget _empty(IconData icon, String title, String text, Color muted) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 20),
        child: Column(children: [
          Icon(icon, size: 40, color: muted),
          const SizedBox(height: 12),
          Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: muted)),
        ]),
      );
}

/// One file to push: repo-relative path + lazy reader.
class _PushEntry {
  final String path;
  final int size;
  final Future<List<int>> Function() read;
  _PushEntry(this.path, this.size, this.read);
}

/// One repo card — inline form + actions, same layout as the web card.
class _RepoCardView extends StatefulWidget {
  final RepoCard card;
  final ApiClient api;
  final bool compact;
  final VoidCallback onChanged;
  final VoidCallback onTokenChanged;
  final VoidCallback onRemove;
  const _RepoCardView({
    super.key,
    required this.card,
    required this.api,
    required this.compact,
    required this.onChanged,
    required this.onTokenChanged,
    required this.onRemove,
  });

  @override
  State<_RepoCardView> createState() => _RepoCardViewState();
}

class _RepoCardViewState extends State<_RepoCardView> {
  RepoCard get card => widget.card;
  ApiClient get _api => widget.api;

  late final TextEditingController _label, _owner, _name, _branch, _token,
      _msg, _workflow;
  bool _showToken = false;
  bool _busy = false;
  String? _busyOp;
  List<_PushEntry> _entries = [];
  String _fileInfo = 'no folder chosen';
  String _runInfo = '';
  final List<String> _log = [];
  final _logScroll = ScrollController();
  double _prog = 0;
  bool _progOn = false;
  Timer? _progTimer;

  @override
  void initState() {
    super.initState();
    _label = TextEditingController(text: card.label);
    _owner = TextEditingController(text: card.owner);
    _name = TextEditingController(text: card.name);
    _branch = TextEditingController(text: card.branch);
    _token = TextEditingController(text: card.token);
    _msg = TextEditingController(text: card.message);
    _workflow = TextEditingController(text: card.workflow);
  }

  @override
  void dispose() {
    for (final c in [_label, _owner, _name, _branch, _token, _msg, _workflow]) {
      c.dispose();
    }
    _logScroll.dispose();
    _progTimer?.cancel();
    super.dispose();
  }

  // ---------------- helpers ----------------

  String _clock() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(n.hour)}:${two(n.minute)}:${two(n.second)}';
  }

  void _setRunInfo(String s) {
    if (mounted) setState(() => _runInfo = s);
  }

  void _addLog(String m) {
    if (!mounted) return;
    setState(() => _log.add(m));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
      }
    });
  }

  void _setProg(double v) {
    if (!mounted) return;
    _progTimer?.cancel();
    setState(() {
      _progOn = true;
      _prog = v.clamp(0, 1).toDouble();
    });
    if (v >= 1) {
      _progTimer = Timer(const Duration(milliseconds: 3500), () {
        if (mounted) setState(() {
          _progOn = false;
          _prog = 0;
        });
      });
    }
  }

  bool _require(RepoCard r) {
    if (r.token.isEmpty || r.owner.isEmpty || r.name.isEmpty) {
      showMsg(context, 'Fill owner, repository and token first', error: true);
      return false;
    }
    return true;
  }

  /// Runs one GitHub operation with the inline log + progress (web `busy`).
  Future<void> _run(
      Future<void> Function(void Function(String) log,
              void Function(double) prog)
          fn) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await fn(_addLog, _setProg);
    } catch (e) {
      final m = e is ApiException ? e.message : e.toString();
      _addLog('ERROR: $m');
      if (mounted) showMsg(context, m, error: true);
    } finally {
      if (mounted) setState(() {
        _busy = false;
        _busyOp = null;
      });
    }
  }

  Future<void> _op(String id, Future<void> Function() fn) async {
    if (_busy) return;
    setState(() => _busyOp = id);
    await fn();
    if (mounted && !_busy) setState(() => _busyOp = null);
  }

  // ---------------- choose folder ----------------

  static bool _skipPath(String p) =>
      p.endsWith('.pyc') ||
      p.endsWith('.DS_Store') ||
      '/$p'.contains('/.git/') ||
      '/$p'.contains('/__pycache__/') ||
      '/$p'.contains('/node_modules/') ||
      '/$p'.contains('/.venv/');

  void _setEntries(List<_PushEntry> list, String what) {
    final keep = list.where((e) => e.path.isNotEmpty && !_skipPath(e.path)).toList();
    setState(() {
      _entries = keep;
      _fileInfo = keep.isEmpty ? 'no pushable files' : '${keep.length} files ready$what';
    });
  }

  Future<void> _choose() async {
    if (Platform.isAndroid) {
      final pick = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('Folder'),
              subtitle: const Text('Folder er sob file, structure soho'),
              onTap: () => Navigator.pop(c, 'folder'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_zip_outlined),
              title: const Text('ZIP file'),
              subtitle: const Text(
                  'Folder access block hole — zip er structure thik rekhe push hobe'),
              onTap: () => Navigator.pop(c, 'zip'),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: const Text('Files'),
              subtitle: const Text('Kichu file (repo root e jabe)'),
              onTap: () => Navigator.pop(c, 'files'),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      );
      if (pick == 'folder') return _chooseFolder();
      if (pick == 'zip') return _chooseZip();
      if (pick == 'files') return _chooseFiles();
      return;
    }
    return _chooseFolder();
  }

  Future<void> _chooseFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null || !mounted) return;
    try {
      final root = dir.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
      final list = <_PushEntry>[];
      await for (final e in Directory(dir).list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        final full = e.path.replaceAll('\\', '/');
        var rel = full.startsWith(root) ? full.substring(root.length) : full;
        rel = rel.replaceAll(RegExp(r'^/+'), '');
        if (_skipPath(rel)) continue;
        final f = e;
        list.add(_PushEntry(rel, await f.length(), () => f.readAsBytes()));
      }
      if (!mounted) return;
      if (list.isEmpty && Platform.isAndroid) {
        showMsg(context,
            'Android ei folder er file porte dicche na — "ZIP file" option use korun',
            error: true);
      }
      _setEntries(list, '');
    } catch (e) {
      if (!mounted) return;
      showMsg(
          context,
          Platform.isAndroid
              ? 'Folder access hocche na — folder ta ZIP kore "ZIP file" option diye din'
              : 'Folder read failed: $e',
          error: true);
    }
  }

  Future<void> _chooseZip() async {
    final res = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['zip'], withData: false);
    final path = res?.files.single.path;
    if (path == null || !mounted) return;
    try {
      final archive = ZipDecoder().decodeBytes(await File(path).readAsBytes());
      final files = archive.files.where((f) => f.isFile).toList();
      // Strip one common top folder (zip of "myproject/..." -> repo root),
      // like the web strips the chosen folder name.
      final names = files.map((f) => f.name.replaceAll('\\', '/')).toList();
      String prefix = '';
      if (names.isNotEmpty && names.every((n) => n.contains('/'))) {
        final first = names.first.split('/').first;
        if (names.every((n) => n.startsWith('$first/'))) prefix = '$first/';
      }
      final list = <_PushEntry>[];
      for (var i = 0; i < files.length; i++) {
        final f = files[i];
        final rel = names[i].substring(prefix.length);
        if (rel.isEmpty || rel.endsWith('/') || rel.startsWith('__MACOSX/')) continue;
        list.add(_PushEntry(rel, f.size, () async => f.content as List<int>));
      }
      _setEntries(list, ' (zip)');
    } catch (e) {
      if (mounted) showMsg(context, 'ZIP read failed: $e', error: true);
    }
  }

  Future<void> _chooseFiles() async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: true, withData: false);
    if (res == null || !mounted) return;
    final list = <_PushEntry>[];
    for (final pf in res.files) {
      if (pf.path == null) continue;
      final f = File(pf.path!);
      list.add(_PushEntry(pf.name, pf.size, () => f.readAsBytes()));
    }
    _setEntries(list, '');
  }

  // ---------------- GitHub actions ----------------

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

  Future<void> _test(RepoCard r) => _run((log, prog) async {
        final me = await _api.gh(r.token, 'GET', '/user');
        log('token OK - ${(me as Map)['login']}');
        final repo =
            await _api.gh(r.token, 'GET', '/repos/${r.owner}/${r.name}');
        final m = Map<String, dynamic>.from(repo as Map);
        log('repo OK - ${m['full_name']} (default: ${m['default_branch']}, ${(m['private'] == true) ? 'private' : 'public'})');
        prog(1);
      });


  Future<void> _pushFiles(RepoCard r) async {
    if (!_require(r)) return;
    final files = _entries;
    if (files.isEmpty) {
      showMsg(context, 'Age "Choose folder…" diye folder select korun',
          error: true);
      return;
    }
    await _run((log, prog) async {
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
        final size = pf.size;
        if (size > 95 * 1024 * 1024) {
          log('SKIP ${pf.path} (over GitHub 100 MB limit)');
          done++;
          prog(done / (files.length + 3));
          continue;
        }
        final bytes = await pf.read();
        final blob = await _api.gh(r.token, 'POST', '/repos/$o/$n/git/blobs',
            {'content': base64Encode(bytes), 'encoding': 'base64'});
        final exec = pf.path.endsWith('.sh');
        tree.add({
          'path': pf.path,
          'mode': exec ? '100755' : '100644',
          'type': 'blob',
          'sha': (blob as Map)['sha'],
        });
        done++;
        prog(done / (files.length + 3));
        log('+ ${pf.path}');
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
      if (mounted) showMsg(context, 'Pushed to $o/$n');
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
      showMsg(context, 'Age "+ custom secret" diye NAME + value din',
          error: true);
      return;
    }
    await _run((log, prog) async {
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
    await _run((log, prog) async {
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
      _setRunInfo('run queued ${_clock()}');
      prog(1);
    });
  }

  Future<void> _stopRuns(RepoCard r) async {
    if (!_require(r)) return;
    await _run((log, prog) async {
      final base = '/repos/${r.owner}/${r.name}/actions/runs';
      final active = <dynamic>[];
      for (final st in ['in_progress', 'queued', 'requested', 'waiting']) {
        final d = await _api.gh(r.token, 'GET', '$base?status=$st&per_page=50');
        active.addAll(((d as Map)['workflow_runs'] as List?) ?? []);
      }
      if (active.isEmpty) {
        log('no active runs to stop');
        _setRunInfo('no active runs');
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
      _setRunInfo('$n run(s) cancelled');
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
    await _run((log, prog) async {
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
      _setRunInfo('repo cleaned ${_clock()}');
    });
  }


  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final night = theme.brightness == Brightness.dark;
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    final line = night ? AppColors.nightLine : AppColors.dayLine;
    final danger = theme.colorScheme.error;
    final c = widget.compact;
    final r = card;

    Widget field(TextEditingController ctl, String hint, void Function(String) onCh,
            {bool obscure = false, Widget? suffix}) =>
        TextField(
          controller: ctl,
          obscureText: obscure,
          autocorrect: false,
          enableSuggestions: false,
          style: TextStyle(fontSize: c ? 13.5 : 14),
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            suffixIcon: suffix,
          ),
          onChanged: onCh,
        );

    Widget groupTitle(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(t.toUpperCase(),
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.9,
                  color: muted)),
        );

    Widget btn(String id, IconData icon, String label, Future<void> Function() fn,
        {bool primary = false, Color? color}) {
      final running = _busyOp == id && _busy;
      final ic = running
          ? const SizedBox(
              width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(icon, size: 15);
      final onTap = _busy ? null : () => _op(id, fn);
      final pad = EdgeInsets.symmetric(horizontal: c ? 11 : 12, vertical: 8);
      const ts = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600);
      final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(9));
      if (primary) {
        return ElevatedButton.icon(
          onPressed: onTap,
          icon: ic,
          label: Text(label),
          style: ElevatedButton.styleFrom(
              padding: pad, minimumSize: const Size(0, 34), textStyle: ts, shape: shape),
        );
      }
      return OutlinedButton.icon(
        onPressed: onTap,
        icon: ic,
        label: Text(label),
        style: OutlinedButton.styleFrom(
            foregroundColor: color ?? theme.colorScheme.onSurface,
            side: BorderSide(color: line),
            padding: pad,
            minimumSize: const Size(0, 34),
            textStyle: ts,
            shape: shape),
      );
    }

    Widget badge(String s) => Text(s, style: TextStyle(fontSize: 11.5, color: muted));

    Widget section(String title, List<Widget> children) => Container(
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
              border: Border(top: BorderSide(color: line, width: 1))),
          child: Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              dense: true,
              visualDensity: VisualDensity.compact,
              controlAffinity: ListTileControlAffinity.leading,
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              iconColor: muted,
              collapsedIconColor: muted,
              title: Text(title,
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600, color: muted)),
              children: children,
            ),
          ),
        );

    Widget check(bool v, Widget label, void Function(bool) on) => InkWell(
          onTap: () => on(!v),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              SizedBox(
                width: 28,
                height: 28,
                child: Checkbox(
                    value: v,
                    visualDensity: VisualDensity.compact,
                    onChanged: (x) => on(x ?? false)),
              ),
              const SizedBox(width: 6),
              Expanded(
                  child: DefaultTextStyle.merge(
                      style: TextStyle(fontSize: 12, color: muted), child: label)),
            ]),
          ),
        );

    final owner = field(_owner, 'owner (user / org)', (v) {
      r.owner = v.trim();
      widget.onChanged();
    });
    final name = field(_name, 'repository', (v) {
      r.name = v.trim();
      widget.onChanged();
    });
    final branch = field(_branch, 'branch (main)', (v) {
      r.branch = v.trim();
      widget.onChanged();
    });
    final token = field(_token, 'GitHub token (PAT)', (v) {
      r.token = v.trim();
      widget.onTokenChanged();
    },
        obscure: !_showToken,
        suffix: IconButton(
          tooltip: 'Show / hide token',
          icon: Icon(_showToken ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 19),
          onPressed: () => setState(() => _showToken = !_showToken),
        ));

    Widget pair(Widget a, Widget b) => c
        ? Column(children: [a, const SizedBox(height: 10), b])
        : Row(children: [
            Expanded(child: a),
            const SizedBox(width: 10),
            Expanded(child: b),
          ]);

    return Container(
      padding: EdgeInsets.all(c ? 14 : 18),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // header: editable label + remove
          Container(
            padding: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: line))),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _label,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                    hintText: 'Label',
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                  onChanged: (v) {
                    r.label = v;
                    widget.onChanged();
                  },
                ),
              ),
              IconButton(
                tooltip: 'Remove card',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 19),
                onPressed: _busy ? null : widget.onRemove,
              ),
            ]),
          ),
          const SizedBox(height: 13),
          pair(owner, name),
          const SizedBox(height: 10),
          pair(branch, token),
          const SizedBox(height: 14),

          groupTitle('Files'),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            btn('pick', Icons.folder_open_outlined, 'Choose folder…', _choose),
            btn('push', Icons.cloud_upload_outlined, 'Push files', () => _pushFiles(r),
                primary: true),
            badge(_fileInfo),
          ]),
          const SizedBox(height: 14),

          groupTitle('GitHub Action'),
          field(_workflow, 'workflow file, e.g. build.yml', (v) {
            r.workflow = v.trim();
            widget.onChanged();
          }),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            btn('run', Icons.play_arrow_rounded, 'Run', () => _runAction(r), primary: true),
            btn('stop', Icons.stop_rounded, 'Stop runs', () => _stopRuns(r)),
            if (_runInfo.isNotEmpty) badge(_runInfo),
          ]),
          const SizedBox(height: 10),

          section('Options', [
            field(_msg, 'commit message (optional)', (v) {
              r.message = v;
              widget.onChanged();
            }),
            const SizedBox(height: 8),
            check(r.saveToken, const Text('remember token in my account'), (v) {
              setState(() => r.saveToken = v);
              widget.onChanged();
            }),
            check(
                r.isPrivate,
                const Text.rich(TextSpan(children: [
                  TextSpan(text: 'create as '),
                  TextSpan(text: 'private', style: TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: ' repo if it does not exist yet (untick = public)'),
                ])), (v) {
              setState(() => r.isPrivate = v);
              widget.onChanged();
            }),
          ]),
          section('Advanced tools', [
            Wrap(spacing: 8, runSpacing: 8, children: [
              btn('test', Icons.power_outlined, 'Test connection', () => _test(r)),
              btn('clean', Icons.delete_outline, 'Clean repo', () => _clean(r), color: danger),
            ]),
          ]),
          section('Repo secrets (GitHub Actions)', [
            badge('Custom secrets — value ei device ei encrypt hoye GitHub e jay, Team Drive server e jay na.'),
            const SizedBox(height: 8),
            for (var i = 0; i < r.extraSecrets.length; i++)
              Padding(
                key: ObjectKey(r.extraSecrets[i]),
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: r.extraSecrets[i].name,
                      style: const TextStyle(fontSize: 13.5),
                      decoration: const InputDecoration(
                          hintText: 'SECRET_NAME', isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                      onChanged: (v) {
                        r.extraSecrets[i].name = v;
                        widget.onChanged();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      initialValue: r.extraSecrets[i].value,
                      obscureText: true,
                      style: const TextStyle(fontSize: 13.5),
                      decoration: const InputDecoration(
                          hintText: 'value', isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                      onChanged: (v) {
                        r.extraSecrets[i].value = v;
                        widget.onChanged();
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove secret row',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      setState(() => r.extraSecrets.removeAt(i));
                      widget.onChanged();
                    },
                  ),
                ]),
              ),
            Wrap(spacing: 8, runSpacing: 8, children: [
              btn('addsec', Icons.add, 'custom secret', () async {
                setState(() => r.extraSecrets.add(RepoSecret()));
              }),
              btn('pushsec', Icons.key_outlined, 'Push secrets', () => _pushSecrets(r),
                  primary: true),
            ]),
          ]),

          // progress (hidden while idle) + log console
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            child: _progOn
                ? Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                          value: _prog > 0 ? _prog : null, minHeight: 4),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          if (_log.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 10),
              constraints: const BoxConstraints(maxHeight: 170),
              decoration: BoxDecoration(
                color: night ? AppColors.nightSide2.withOpacity(0.55) : AppColors.daySoft,
                border: Border.all(color: line),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Scrollbar(
                controller: _logScroll,
                child: SingleChildScrollView(
                  controller: _logScroll,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: SelectableText(
                    _log.join('\n'),
                    style: TextStyle(
                        fontFamily: 'monospace', fontSize: 11.5, height: 1.7, color: muted),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
