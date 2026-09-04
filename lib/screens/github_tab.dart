import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_config.dart';
import '../services/github_service.dart';
import '../services/time_service.dart';
import '../services/upload_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/stat_card.dart';
import '../widgets/ui.dart';

/// GitHub Control - drives the `generator.yml` workflow of the automation repo.
class GithubTab extends StatefulWidget {
  const GithubTab({super.key});

  @override
  State<GithubTab> createState() => _GithubTabState();
}

class _GithubTabState extends State<GithubTab> {
  final TextEditingController _owner = TextEditingController();
  final TextEditingController _repo = TextEditingController();
  final TextEditingController _branch = TextEditingController();
  final TextEditingController _token = TextEditingController();
  final TextEditingController _session = TextEditingController();

  // Ringtone generator inputs
  final TextEditingController _count = TextEditingController(text: '10');
  final TextEditingController _length = TextEditingController(text: '5');
  final TextEditingController _boost = TextEditingController(text: '200');
  final TextEditingController _silence = TextEditingController(text: '0.02');
  final TextEditingController _pad = TextEditingController(text: '100');
  String _targetAccount = 'zedge_2';
  bool _autoProcess = true;
  bool _attachSessionRg = true;

  // Metadata generator inputs
  final TextEditingController _queuePath = TextEditingController(text: kQueuePath);
  bool _attachSessionIm = true;

  // Files browser
  String _path = '';
  List<RepoEntry> _entries = <RepoEntry>[];
  List<WorkflowRun> _runs = <WorkflowRun>[];
  bool _busy = false;
  bool _tokenVisible = false;
  bool _seeded = false;
  final List<String> _log = <String>[];

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _owner, _repo, _branch, _token, _session, _count, _length, _boost,
      _silence, _pad, _queuePath,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _seed(AppState state) {
    if (_seeded) return;
    _seeded = true;
    _owner.text = state.gh.owner;
    _repo.text = state.gh.repo;
    _branch.text = state.gh.branchOrMain;
    _token.text = state.gh.token;
    _session.text = state.ghSession;
  }

  GithubConfig _cfgFromForm() => GithubConfig(
        owner: _owner.text.trim(),
        repo: _repo.text.trim(),
        branch: _branch.text.trim().isEmpty ? 'main' : _branch.text.trim(),
        token: _token.text.trim(),
      );

  GithubService? _svc(AppState state, {bool warn = true}) {
    final GithubConfig cfg = _cfgFromForm();
    if (!cfg.ready) {
      if (warn) showSnack(context, 'Fill owner, repo and token first', error: true);
      return null;
    }
    return GithubService(cfg);
  }

  void _note(AppState state, String m) {
    if (!mounted) return;
    setState(() {
      _log.insert(0, '[${dhakaStamp(state.dhakaNow)}] $m');
      if (_log.length > 200) _log.removeLast();
    });
  }

  Future<void> _guard(AppState state, Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      _note(state, 'ERROR: $e');
      if (mounted) showSnack(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveCfg(AppState state) async {
    await state.saveGithubConfig(_cfgFromForm());
    _note(state, 'Settings saved (local + synced to Zedge 1)');
    if (mounted) showSnack(context, 'GitHub settings saved');
  }

  Future<void> _test(AppState state) => _guard(state, () async {
        final GithubService? svc = _svc(state);
        if (svc == null) return;
        final String msg = await svc.testConnection();
        _note(state, msg);
        if (mounted) showSnack(context, msg);
      });

  Future<void> _refreshRuns(AppState state) => _guard(state, () async {
        final GithubService? svc = _svc(state);
        if (svc == null) return;
        final List<WorkflowRun> runs = await svc.listRuns();
        setState(() => _runs = runs);
        _note(state, 'Loaded ${runs.length} runs');
      });

  Future<void> _cleanRuns(AppState state) async {
    final bool ok = await confirmDialog(
      context,
      title: 'Delete completed runs?',
      message: 'Every completed workflow run (up to 100 per pass) will be deleted.',
      confirmLabel: 'Clean',
      danger: true,
    );
    if (!ok) return;
    await _guard(state, () async {
      final GithubService? svc = _svc(state);
      if (svc == null) return;
      final List<WorkflowRun> completed = await svc.listRuns(perPage: 100, status: 'completed');
      int n = 0;
      for (final WorkflowRun r in completed) {
        try {
          await svc.deleteRun(r.id);
          n++;
        } catch (e) {
          _note(state, 'Could not delete run #${r.number}: $e');
        }
      }
      _note(state, 'Deleted $n completed runs');
      setState(() => _runs = <WorkflowRun>[]);
      await _refreshRuns(state);
    });
  }

  Map<String, String> _sessionInput(bool attach) {
    final String s = _session.text.trim();
    if (!attach || s.isEmpty) return <String, String>{};
    return <String, String>{'gemini_session': s};
  }

  Future<void> _runRingtone(AppState state) => _guard(state, () async {
        final GithubService? svc = _svc(state);
        if (svc == null) return;
        final Map<String, String> inputs = <String, String>{
          'mode': 'ringtone',
          'auto_generate_count': _count.text.trim(),
          'length_seconds': _length.text.trim(),
          'auto_process': _autoProcess ? 'true' : 'false',
          'volume_boost_pct': _boost.text.trim(),
          'silence_threshold': _silence.text.trim(),
          'pad_ms': _pad.text.trim(),
          'target_account': _targetAccount,
          ..._sessionInput(_attachSessionRg),
        };
        await svc.triggerWorkflow(kGeneratorWorkflow, inputs);
        _note(state, 'Ringtone generator dispatched (${inputs['auto_generate_count']} x ${inputs['length_seconds']}s -> $_targetAccount)');
        if (mounted) showSnack(context, 'Ringtone generator started');
        await Future<void>.delayed(const Duration(seconds: 3));
        await _refreshRuns(state);
      });

  Future<void> _runMetadata(AppState state) => _guard(state, () async {
        final GithubService? svc = _svc(state);
        if (svc == null) return;
        final Map<String, String> inputs = <String, String>{
          'mode': 'metadata',
          'image_queue_path': _queuePath.text.trim().isEmpty ? kQueuePath : _queuePath.text.trim(),
          ..._sessionInput(_attachSessionIm),
        };
        await svc.triggerWorkflow(kGeneratorWorkflow, inputs);
        _note(state, 'Metadata generator dispatched for ${inputs['image_queue_path']}');
        if (mounted) showSnack(context, 'Metadata generator started');
        await Future<void>.delayed(const Duration(seconds: 3));
        await _refreshRuns(state);
      });

  Future<void> _validateSession(AppState state) async {
    try {
      final String info = describeSessionJson(_session.text.trim());
      final int kb = utf8.encode(_session.text).length ~/ 1024;
      final String warn = kb > 60 ? ' - WARNING: ${kb}KB is above the 60KB dispatch limit' : ' ($kb KB)';
      _note(state, 'Session valid: $info$warn');
      showSnack(context, 'Valid: $info$warn', error: kb > 60);
    } catch (e) {
      _note(state, 'Session invalid: $e');
      showSnack(context, 'Invalid session JSON: $e', error: true);
    }
  }

  Future<void> _listPath(AppState state, String path) => _guard(state, () async {
        final GithubService? svc = _svc(state);
        if (svc == null) return;
        final List<RepoEntry> entries = await svc.listPath(path);
        setState(() {
          _path = path;
          _entries = entries;
        });
      });

  Future<void> _push(AppState state) => _guard(state, () async {
        final GithubService? svc = _svc(state);
        if (svc == null) return;
        final List<PickedFile> files = await pickFiles(
          extensions: const <String>[],
          title: 'Files to push to /${_path.isEmpty ? '' : '$_path/'}',
        );
        if (files.isEmpty) return;
        for (final PickedFile f in files) {
          if (f.size > 25 * 1024 * 1024) {
            _note(state, 'Skipped ${f.name} (> 25 MB)');
            continue;
          }
          final String target = _path.isEmpty ? f.name : '$_path/${f.name}';
          final bool updated = await svc.pushFile(target, f.bytes);
          _note(state, '${updated ? 'Updated' : 'Added'} $target');
        }
        await _listPath(state, _path);
      });

  Future<void> _deleteFile(AppState state, RepoEntry e) async {
    final bool ok = await confirmDialog(
      context,
      title: 'Delete ${e.name}?',
      message: 'The file is removed from branch ${_branch.text} with a commit.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (!ok) return;
    await _guard(state, () async {
      final GithubService? svc = _svc(state);
      if (svc == null) return;
      await svc.deleteFile(e);
      _note(state, 'Deleted ${e.path}');
      await _listPath(state, _path);
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    _seed(state);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final bool wide = c.maxWidth >= 1000;
        final List<Widget> left = <Widget>[
          _configCard(state),
          const SizedBox(height: 16),
          _sessionCard(state),
          const SizedBox(height: 16),
          _ringtoneCard(state),
          const SizedBox(height: 16),
          _metadataCard(state),
        ];
        final List<Widget> right = <Widget>[
          _runsCard(state),
          const SizedBox(height: 16),
          _filesCard(state),
          const SizedBox(height: 16),
          _logCard(),
        ];
        return ListView(
          padding: EdgeInsets.fromLTRB(wide ? 24 : 14, 8, wide ? 24 : 14, 32),
          children: <Widget>[
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: Column(children: left)),
                  const SizedBox(width: 16),
                  Expanded(child: Column(children: right)),
                ],
              )
            else ...<Widget>[...left, const SizedBox(height: 16), ...right],
          ],
        );
      },
    );
  }

  Widget _configCard(AppState state) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionTitle(
            icon: Icons.terminal_rounded,
            title: 'GitHub Control',
            subtitle: state.gh.ready
                ? '${state.gh.owner}/${state.gh.repo} @ ${state.gh.branchOrMain}'
                : 'Connect the automation repository',
            gradient: const LinearGradient(colors: <Color>[Zc.ink, Color(0xFF3A321C)]),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _owner,
                  decoration: const InputDecoration(labelText: 'Owner'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _repo,
                  decoration: const InputDecoration(labelText: 'Repository'),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _branch,
                  decoration: const InputDecoration(labelText: 'Branch'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _token,
            obscureText: !_tokenVisible,
            decoration: InputDecoration(
              labelText: 'Personal access token (repo + workflow scopes)',
              suffixIcon: IconButton(
                onPressed: () => setState(() => _tokenVisible = !_tokenVisible),
                icon: Icon(_tokenVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 18),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              GradientButton(
                label: 'Save settings',
                icon: Icons.save_rounded,
                dense: true,
                onPressed: () => _saveCfg(state),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _test(state),
                icon: const Icon(Icons.wifi_tethering_rounded, size: 15),
                label: const Text('Test connection'),
              ),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        await state.syncGithubSettingsFromDb();
                        setState(() {
                          _seeded = false;
                          _seed(state);
                        });
                        _note(state, 'Pulled shared settings from Zedge 1');
                      },
                icon: const Icon(Icons.cloud_sync_rounded, size: 15),
                label: const Text('Pull shared'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sessionCard(AppState state) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionTitle(
            icon: Icons.cookie_rounded,
            title: 'Gemini session',
            subtitle: 'Cookie array or Playwright storageState JSON - attached to workflow runs',
            gradient: Zc.secondaryGradient,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _session,
            minLines: 4,
            maxLines: 8,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
            decoration: const InputDecoration(hintText: '[ { "name": "__Secure-1PSID", ... } ]'),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              GradientButton(
                label: 'Save session',
                icon: Icons.save_rounded,
                dense: true,
                onPressed: () async {
                  await state.saveGithubSession(_session.text.trim());
                  _note(state, 'Gemini session saved (synced)');
                  if (mounted) showSnack(context, 'Session saved');
                },
              ),
              OutlinedButton.icon(
                onPressed: () => _validateSession(state),
                icon: const Icon(Icons.rule_rounded, size: 15),
                label: const Text('Validate JSON'),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _session.clear()),
                icon: const Icon(Icons.clear_rounded, size: 15),
                label: const Text('Clear'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _num(TextEditingController c, String label, {double width = 120}) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Widget _ringtoneCard(AppState state) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionTitle(
            icon: Icons.music_note_rounded,
            title: 'Ringtone generator',
            subtitle: 'generator.yml - mode: ringtone',
            gradient: LinearGradient(colors: <Color>[Zc.purple, Color(0xFF5E35B1)]),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _num(_count, 'Count'),
              _num(_length, 'Length (s)'),
              _num(_boost, 'Volume boost %'),
              _num(_silence, 'Silence threshold'),
              _num(_pad, 'Pad (ms)'),
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<String>(
                  value: _targetAccount,
                  decoration: const InputDecoration(labelText: 'Target account'),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(value: 'zedge_1', child: Text('zedge_1')),
                    DropdownMenuItem<String>(value: 'zedge_2', child: Text('zedge_2')),
                    DropdownMenuItem<String>(value: 'zedge_3', child: Text('zedge_3')),
                  ],
                  onChanged: (String? v) => setState(() => _targetAccount = v ?? 'zedge_2'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            children: <Widget>[
              _check('Auto process', _autoProcess, (bool v) => setState(() => _autoProcess = v)),
              _check('Attach Gemini session', _attachSessionRg, (bool v) => setState(() => _attachSessionRg = v)),
            ],
          ),
          const SizedBox(height: 10),
          GradientButton(
            label: 'Run ringtone generator',
            icon: Icons.play_arrow_rounded,
            dense: true,
            busy: _busy,
            gradient: const LinearGradient(colors: <Color>[Zc.purple, Color(0xFF5E35B1)]),
            foreground: Colors.white,
            onPressed: _busy ? null : () => _runRingtone(state),
          ),
        ],
      ),
    );
  }

  Widget _metadataCard(AppState state) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionTitle(
            icon: Icons.auto_awesome_rounded,
            title: 'Metadata generator',
            subtitle: 'generator.yml - mode: metadata (titles, tags, descriptions via Gemini)',
            gradient: Zc.accentGradient,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _queuePath,
            decoration: const InputDecoration(labelText: 'Image queue path'),
          ),
          const SizedBox(height: 6),
          _check('Attach Gemini session', _attachSessionIm, (bool v) => setState(() => _attachSessionIm = v)),
          const SizedBox(height: 10),
          GradientButton(
            label: 'Run metadata generator',
            icon: Icons.play_arrow_rounded,
            dense: true,
            busy: _busy,
            gradient: Zc.accentGradient,
            onPressed: _busy ? null : () => _runMetadata(state),
          ),
        ],
      ),
    );
  }

  Widget _check(String label, bool value, ValueChanged<bool> onChanged) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(!value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Checkbox(value: value, onChanged: (bool? v) => onChanged(v ?? false), activeColor: Zc.goldDeep),
          Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Zc.inkSoft)),
        ],
      ),
    );
  }

  Widget _runsCard(AppState state) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionTitle(
            icon: Icons.history_rounded,
            title: 'Workflow runs',
            subtitle: '${_runs.length} loaded',
            trailing: Wrap(
              spacing: 4,
              children: <Widget>[
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _busy ? null : () => _refreshRuns(state),
                  icon: const Icon(Icons.refresh_rounded),
                ),
                IconButton(
                  tooltip: 'Delete completed runs',
                  onPressed: _busy ? null : () => _cleanRuns(state),
                  icon: const Icon(Icons.cleaning_services_rounded, color: Zc.danger),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_runs.isEmpty)
            const Text(
              'No runs loaded - press refresh.',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Zc.muted),
            )
          else
            ..._runs.map((WorkflowRun r) {
              final Color color = r.completed
                  ? (r.conclusion == 'success' ? Zc.okDeep : Zc.danger)
                  : Zc.info;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: Zc.cream,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Zc.line),
                ),
                child: Row(
                  children: <Widget>[
                    Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('#${r.number}  ${r.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: Zc.ink)),
                          Text(
                            '${r.completed ? r.conclusion : r.status} - ${r.event} - ${r.durationMinutes} min'
                            '${r.startedAt == null ? '' : ' - ${DateFormat('d MMM HH:mm').format(r.startedAt!.add(kDhakaOffset))} Dhaka'}',
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Zc.muted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Open on GitHub',
                      onPressed: r.htmlUrl.isEmpty ? null : () => launchUrl(Uri.parse(r.htmlUrl), mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.open_in_new_rounded, size: 17),
                    ),
                    IconButton(
                      tooltip: 'Delete run',
                      onPressed: _busy
                          ? null
                          : () => _guard(state, () async {
                                final GithubService? svc = _svc(state);
                                if (svc == null) return;
                                await svc.deleteRun(r.id);
                                setState(() => _runs.remove(r));
                                _note(state, 'Deleted run #${r.number}');
                              }),
                      icon: const Icon(Icons.delete_outline_rounded, size: 17, color: Zc.danger),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _filesCard(AppState state) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionTitle(
            icon: Icons.folder_rounded,
            title: 'Repository files',
            subtitle: '/${_path.isEmpty ? '' : _path}',
            trailing: Wrap(
              spacing: 4,
              children: <Widget>[
                IconButton(
                  tooltip: 'Up',
                  onPressed: _busy || _path.isEmpty
                      ? null
                      : () {
                          final int i = _path.lastIndexOf('/');
                          _listPath(state, i < 0 ? '' : _path.substring(0, i));
                        },
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _busy ? null : () => _listPath(state, _path),
                  icon: const Icon(Icons.refresh_rounded),
                ),
                IconButton(
                  tooltip: 'Push files here',
                  onPressed: _busy ? null : () => _push(state),
                  icon: const Icon(Icons.upload_file_rounded, color: Zc.goldDeep),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_entries.isEmpty)
            const Text(
              'Press refresh to browse the repository.',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Zc.muted),
            )
          else
            ..._entries.map((RepoEntry e) => ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                  leading: Icon(
                    e.isDir ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
                    color: e.isDir ? Zc.goldDeep : Zc.muted,
                  ),
                  title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                  subtitle: e.isDir ? null : Text('${(e.size / 1024).toStringAsFixed(1)} KB', style: const TextStyle(fontSize: 10.5)),
                  onTap: e.isDir && !_busy ? () => _listPath(state, e.path) : null,
                  trailing: e.isDir
                      ? const Icon(Icons.chevron_right_rounded)
                      : IconButton(
                          onPressed: _busy ? null : () => _deleteFile(state, e),
                          icon: const Icon(Icons.delete_outline_rounded, size: 17, color: Zc.danger),
                        ),
                )),
        ],
      ),
    );
  }

  Widget _logCard() {
    return Panel(
      padding: const EdgeInsets.all(14),
      color: const Color(0xFF15120A),
      borderColor: const Color(0xFF15120A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.receipt_long_rounded, color: Zc.gold, size: 16),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('ACTIVITY LOG',
                    style: TextStyle(color: Zc.gold, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1.2)),
              ),
              TextButton(
                onPressed: () => setState(() => _log.clear()),
                child: const Text('Clear', style: TextStyle(color: Colors.white70)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              child: SelectableText(
                _log.isEmpty ? 'Ready.' : _log.join('\n'),
                style: const TextStyle(color: Color(0xFFFFE873), fontFamily: 'monospace', fontSize: 11, height: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
