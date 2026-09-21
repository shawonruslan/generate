import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/github_api.dart';
import '../../domain/vpn.dart';
import '../../state/app_state.dart';
import '../shell/app_shell.dart';
import '../widgets/common.dart';
import '../widgets/dropzone.dart';
import '../widgets/fa.dart';
import '../widgets/responsive.dart';

/// GitHub Control tab (`initGithubPanel`): connection, Gemini session, workflow triggers,
/// action runs, repo file browser, activity log.
class GithubScreen extends StatelessWidget {
  const GithubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return PageBody(children: [
      GlassCard(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionTitle('GitHub Repo Control', icon: 'fa-code-branch'),
          const SizedBox(height: 8),
          Text.rich(TextSpan(style: TextStyle(fontSize: 12.5, color: p.muted, height: 1.5), children: const [
            TextSpan(text: 'Trigger the generator workflows, pass your Gemini cookie/session JSON, clean old Action runs and push/delete repo files - all from this panel. Settings, token & session are saved on this device '),
            TextSpan(text: 'and auto-synced to your Firebase database', style: TextStyle(fontWeight: FontWeight.w800)),
            TextSpan(text: ' - open the dashboard on another device and everything is already there.'),
          ])),
        ]),
      ),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (context, c) {
        final two = c.maxWidth >= Bp.md;
        const left = [_ConnectionCard(), SizedBox(height: 16), _SessionCard()];
        const right = [_RingtoneCard(), SizedBox(height: 16), _MetadataCard()];
        if (!two) return const Column(children: [...left, SizedBox(height: 16), ...right]);
        return const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(children: left)),
          SizedBox(width: 16),
          Expanded(child: Column(children: right)),
        ]);
      }),
      const SizedBox(height: 16),
      const _RunsCard(),
      const SizedBox(height: 16),
      const _FilesCard(),
      const SizedBox(height: 16),
      const _LogCard(),
    ]);
  }
}

InputDecoration _dec(String hint) => InputDecoration(hintText: hint, isDense: true);

// ---------------------------------------------------------------- connection
class _ConnectionCard extends StatefulWidget {
  const _ConnectionCard();
  @override
  State<_ConnectionCard> createState() => _ConnectionCardState();
}

class _ConnectionCardState extends State<_ConnectionCard> {
  final _link = TextEditingController();
  late final TextEditingController _owner, _repo, _branch, _token;
  final Map<String, TextEditingController> _wf = {};
  bool _showToken = false;
  bool _testing = false;
  GhCfg? _seen;

  @override
  void initState() {
    super.initState();
    final cfg = context.app.ghCfg;
    _owner = TextEditingController(text: cfg.owner);
    _repo = TextEditingController(text: cfg.repo);
    _branch = TextEditingController(text: cfg.branch);
    _token = TextEditingController(text: cfg.token);
    for (final k in context.app.accountKeys) {
      _wf[k] = TextEditingController(text: cfg.workflows[k] ?? '');
    }
    _seen = cfg;
  }

  @override
  void dispose() {
    for (final c in [_link, _owner, _repo, _branch, _token, ..._wf.values]) {
      c.dispose();
    }
    super.dispose();
  }

  GhCfg _collect() => GhCfg(
        owner: _owner.text.trim(),
        repo: _repo.text.trim(),
        branch: _branch.text.trim().isEmpty ? 'main' : _branch.text.trim(),
        token: _token.text.trim(),
        workflows: {for (final e in _wf.entries) e.key: e.value.text.trim()},
      );

  @override
  Widget build(BuildContext context) {
    final app = context.appWatch;
    final p = app.palette;
    // remote sync (Firebase) may replace the cfg - mirror it into the fields once
    if (!identical(_seen, app.ghCfg)) {
      _seen = app.ghCfg;
      _owner.text = app.ghCfg.owner;
      _repo.text = app.ghCfg.repo;
      _branch.text = app.ghCfg.branch;
      _token.text = app.ghCfg.token;
      for (final e in _wf.entries) {
        e.value.text = app.ghCfg.workflows[e.key] ?? '';
      }
    }
    final stColor = switch (app.ghConnStatusCls) { 'ok' => p.ok, 'err' => p.danger, _ => p.muted };
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionTitle('Connection', icon: 'fa-plug'),
        const SizedBox(height: 12),
        Field('Repo link / path (auto-fills owner + repo)', child: TextField(controller: _link, decoration: _dec('https://github.com/owner/repo'), onChanged: (v) {
          final r = ghParseRepoLink(v);
          if (r != null) {
            _owner.text = r.$1;
            _repo.text = r.$2;
          }
        })),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          Field('Owner (user/org)', width: 200, child: TextField(controller: _owner, decoration: _dec('owner'))),
          Field('Repository', width: 200, child: TextField(controller: _repo, decoration: _dec('repo'))),
          Field('Branch', width: 140, child: TextField(controller: _branch, decoration: _dec('main'))),
        ]),
        const SizedBox(height: 10),
        Field(
          'Personal Access Token',
          child: TextField(
            controller: _token,
            obscureText: !_showToken,
            decoration: InputDecoration(hintText: 'ghp_…', isDense: true, suffixIcon: IconButton(icon: Icon(_showToken ? Icons.visibility_off : Icons.visibility, size: 18), onPressed: () => setState(() => _showToken = !_showToken))),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          ZButton('Save', icon: 'fa-save', small: true, onPressed: () => app.ghSaveCfg(_collect())),
          ZButton('Test Connection', icon: 'fa-vial', small: true, kind: ZBtnKind.soft, busy: _testing, onPressed: _testing
              ? null
              : () async {
                  setState(() => _testing = true);
                  await app.ghSaveCfg(_collect());
                  await app.ghTestConnection();
                  if (mounted) setState(() => _testing = false);
                }),
          Text(app.ghConnStatus.isEmpty ? 'Not connected' : app.ghConnStatus, style: TextStyle(fontSize: 12.5, color: stColor, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 14),
        Text('Workflow files per account (for VPN test & triggers)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: p.text)),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final e in _wf.entries) Field(app.accountLabel(e.key), width: 160, child: TextField(controller: e.value, decoration: _dec('${e.key}.yml'))),
        ]),
        const SizedBox(height: 8),
        Text('File names inside .github/workflows/. Leave blank to use the defaults.', style: TextStyle(fontSize: 11.5, color: p.muted)),
        const SizedBox(height: 6),
        Text.rich(TextSpan(style: TextStyle(fontSize: 11.5, color: p.muted, height: 1.5), children: const [
          TextSpan(text: 'Fine-grained PAT: this repo only + '),
          TextSpan(text: 'Actions: Read and write', style: TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: ' + '),
          TextSpan(text: 'Contents: Read and write', style: TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: '. Classic PAT: '),
          TextSpan(text: 'repo', style: TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: ' + '),
          TextSpan(text: 'workflow', style: TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: ' scopes.'),
        ])),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Gemini session
class _SessionCard extends StatefulWidget {
  const _SessionCard();
  @override
  State<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<_SessionCard> {
  late final TextEditingController _c = TextEditingController(text: context.app.ghSession);
  String? _seen;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.appWatch;
    final p = app.palette;
    if (_seen != app.ghSession) {
      _seen = app.ghSession;
      if (_c.text != app.ghSession) _c.text = app.ghSession;
    }
    final stColor = switch (app.ghSessionStatusCls) { 'ok' => p.ok, 'err' => p.danger, _ => p.muted };
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionTitle('Gemini Cookie / Session JSON', icon: 'fa-user-secret'),
        const SizedBox(height: 12),
        TextField(
          controller: _c,
          minLines: 6,
          maxLines: 12,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
          decoration: _dec('Paste storageState JSON or a raw cookie array here…'),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          ZButton('Save Session', icon: 'fa-save', small: true, onPressed: () => app.ghSaveSession(_c.text)),
          ZButton('Validate JSON', icon: 'fa-check', small: true, kind: ZBtnKind.soft, onPressed: () async {
            final raw = _c.text.trim();
            if (raw.isEmpty) {
              await alertDialog(context, 'Paste session JSON first.');
              return;
            }
            try {
              final info = ghSessionInfo(raw);
              if (context.mounted) await alertDialog(context, 'Valid JSON.\nFormat: ${info.format}\nCookies: ${info.cookies}\nSize: ${(raw.length / 1024).toStringAsFixed(1)} KB', title: 'Session JSON');
            } catch (e) {
              if (context.mounted) await alertDialog(context, 'Invalid JSON: ${e.toString().replaceFirst('FormatException: ', '')}', title: 'Session JSON');
            }
          }),
          Text(app.ghSessionStatus.isEmpty ? 'No session saved' : app.ghSessionStatus, style: TextStyle(fontSize: 12.5, color: stColor, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        Text.rich(TextSpan(style: TextStyle(fontSize: 11.5, color: p.muted, height: 1.5), children: const [
          TextSpan(text: 'Saved session is auto-attached as the '),
          TextSpan(text: 'gemini_session', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800)),
          TextSpan(text: ' input when you trigger a workflow below - it overrides the repo secret '),
          TextSpan(text: 'GEMINI_SESSION', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800)),
          TextSpan(text: ' for that run. Both generator modes already normalize storageState & raw cookie-array formats.'),
        ])),
      ]),
    );
  }
}

// ---------------------------------------------------------------- ringtone generator trigger
class _RingtoneCard extends StatefulWidget {
  const _RingtoneCard();
  @override
  State<_RingtoneCard> createState() => _RingtoneCardState();
}

class _RingtoneCardState extends State<_RingtoneCard> {
  final _count = TextEditingController(text: '10');
  final _length = TextEditingController(text: '5');
  String _auto = 'true';
  final _volume = TextEditingController(text: '200');
  final _silence = TextEditingController(text: '0.02');
  final _pad = TextEditingController(text: '100');
  String _target = 'zedge_2';
  bool _attach = true;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_count, _length, _volume, _silence, _pad]) {
      c.dispose();
    }
    super.dispose();
  }

  String _v(TextEditingController c, String d) => c.text.trim().isEmpty ? d : c.text.trim();

  @override
  Widget build(BuildContext context) {
    final app = context.appWatch;
    final p = app.palette;
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionTitle('Trigger: Ringtone Generator', icon: 'fa-music', trailing: Wrap(spacing: 6, children: [Pill('generator.yml', small: true, color: p.tintChip, fg: p.text), Pill('mode: ringtone', small: true, color: p.primary.withValues(alpha: 0.15), fg: p.primary)])),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          Field('Auto-generate count', width: 150, child: TextField(controller: _count, decoration: _dec('10'), keyboardType: TextInputType.number)),
          Field('Length (seconds)', width: 150, child: TextField(controller: _length, decoration: _dec('5'), keyboardType: TextInputType.number)),
          Field('Auto-process audio', width: 150, child: ZDropdown<String>(value: _auto, items: const [('true', 'true'), ('false', 'false')], onChanged: (v) => setState(() => _auto = v))),
          Field('Volume boost %', width: 150, child: TextField(controller: _volume, decoration: _dec('200'), keyboardType: TextInputType.number)),
          Field('Silence threshold', width: 150, child: TextField(controller: _silence, decoration: _dec('0.02'), keyboardType: TextInputType.number)),
          Field('Edge padding ms', width: 150, child: TextField(controller: _pad, decoration: _dec('100'), keyboardType: TextInputType.number)),
          Field('Target account', width: 170, child: ZDropdown<String>(value: _target, items: const [('zedge_1', 'zedge_1'), ('zedge_2', 'zedge_2'), ('zedge_3', 'zedge_3'), ('zedge_4', 'zedge_4'), ('all_accounts', 'all_accounts')], onChanged: (v) => setState(() => _target = v))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Checkbox(value: _attach, onChanged: (v) => setState(() => _attach = v ?? true)),
          Text('Attach saved session JSON', style: TextStyle(fontSize: 12.5, color: p.text)),
        ]),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: ZButton('Run Ringtone Generator', icon: 'fa-play', busy: _busy, onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  final inputs = app.ghMaybeAttachSession(_attach, {
                    'mode': 'ringtone',
                    'auto_generate_count': _v(_count, '10'),
                    'length_seconds': _v(_length, '5'),
                    'auto_process': _auto,
                    'volume_boost_pct': _v(_volume, '200'),
                    'silence_threshold': _v(_silence, '0.02'),
                    'pad_ms': _v(_pad, '100'),
                    'target_account': _target,
                  });
                  await app.ghTriggerWorkflow('generator.yml', inputs, 'Ringtone Generator (mode: ringtone)');
                  if (mounted) setState(() => _busy = false);
                }),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- metadata generator trigger
class _MetadataCard extends StatefulWidget {
  const _MetadataCard();
  @override
  State<_MetadataCard> createState() => _MetadataCardState();
}

class _MetadataCardState extends State<_MetadataCard> {
  final _path = TextEditingController(text: 'wallpaperQueue');
  bool _attach = true;
  bool _busy = false;

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.appWatch;
    final p = app.palette;
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionTitle('Trigger: Metadata Generator', icon: 'fa-tags', trailing: Wrap(spacing: 6, children: [Pill('generator.yml', small: true, color: p.tintChip, fg: p.text), Pill('mode: metadata', small: true, color: p.primary.withValues(alpha: 0.15), fg: p.primary)])),
        const SizedBox(height: 12),
        Field('Firebase queue path', width: 260, child: TextField(controller: _path, decoration: _dec('wallpaperQueue'))),
        const SizedBox(height: 10),
        Row(children: [
          Checkbox(value: _attach, onChanged: (v) => setState(() => _attach = v ?? true)),
          Text('Attach saved session JSON', style: TextStyle(fontSize: 12.5, color: p.text)),
        ]),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: ZButton('Run Metadata Generator', icon: 'fa-play', busy: _busy, onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  final qp = _path.text.trim().isEmpty ? 'wallpaperQueue' : _path.text.trim();
                  await app.ghTriggerWorkflow('generator.yml', app.ghMaybeAttachSession(_attach, {'mode': 'metadata', 'image_queue_path': qp}), 'Metadata Generator (mode: metadata)');
                  if (mounted) setState(() => _busy = false);
                }),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- runs
class _RunsCard extends StatelessWidget {
  const _RunsCard();

  String _runIcon(Map<String, dynamic> run) {
    if (run['status'] != 'completed') return run['status'] == 'in_progress' ? 'fa-spinner' : 'fa-clock';
    if (run['conclusion'] == 'success') return 'fa-circle-check';
    if (run['conclusion'] == 'cancelled') return 'fa-ban';
    return 'fa-circle-xmark';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.appWatch;
    final p = app.palette;
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionTitle('Recent Action Runs', icon: 'fa-list-check', trailing: Wrap(spacing: 8, children: [
          ZButton('Refresh', icon: 'fa-arrows-rotate', small: true, kind: ZBtnKind.soft, busy: app.ghRunsLoading, onPressed: app.ghRunsLoading ? null : app.ghLoadRuns),
          ZButton('Clean completed runs', icon: 'fa-broom', small: true, kind: ZBtnKind.danger, busy: app.ghCleaning, onPressed: app.ghCleaning
              ? null
              : () async {
                  if (!app.ghCfg.ready) {
                    await alertDialog(context, 'Configure owner / repo / token first.');
                    return;
                  }
                  final ok = await confirmDialog(context, 'Delete ALL completed workflow runs from the Actions history? Queued / running runs are kept. This cannot be undone.', title: 'Clean runs', okLabel: 'Clean', danger: true);
                  if (!ok) return;
                  try {
                    await app.ghCleanRuns();
                  } catch (e) {
                    app.showToast(e.toString().replaceFirst('Exception: ', ''), 'err');
                  }
                }),
        ])),
        const SizedBox(height: 12),
        if (app.ghRunsLoading)
          const EmptyNote('Loading runs...', icon: 'fa-spinner')
        else if (app.ghRunsError != null)
          EmptyNote(app.ghRunsError!, icon: 'fa-exclamation-triangle')
        else if (app.ghRuns.isEmpty)
          const EmptyNote('Save connection & hit Refresh to see runs.', icon: 'fa-list')
        else
          for (final run in app.ghRuns) _runRow(context, app, p, run),
      ]),
    );
  }

  Widget _runRow(BuildContext context, AppState app, dynamic p, Map<String, dynamic> run) {
    final started = DateTime.tryParse('${run['run_started_at'] ?? run['created_at'] ?? ''}');
    final updated = DateTime.tryParse('${run['updated_at'] ?? ''}');
    String when = '';
    var durMin = 0;
    if (started != null) {
      final dk = started.toUtc().add(const Duration(hours: 6));
      when = '${dk.day.toString().padLeft(2, '0')} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][dk.month - 1]} ${dk.hour.toString().padLeft(2, '0')}:${dk.minute.toString().padLeft(2, '0')}';
      final end = run['status'] == 'completed' ? (updated ?? DateTime.now()) : DateTime.now();
      durMin = (end.difference(started).inSeconds / 60).round().clamp(0, 1 << 30);
    }
    final icon = _runIcon(run);
    final color = switch (icon) { 'fa-circle-check' => p.ok, 'fa-circle-xmark' => p.danger, 'fa-spinner' => p.info, _ => p.muted };
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: p.tintSoft, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Fa(icon, size: 14, color: color),
        const SizedBox(width: 10),
        Expanded(child: Tooltip(message: '${run['name'] ?? ''}', child: Text('${run['name'] ?? run['path'] ?? 'run'}', style: TextStyle(fontWeight: FontWeight.w700, color: p.text, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis))),
        const SizedBox(width: 10),
        Text('#${run['run_number']} | $when | ${durMin}m', style: TextStyle(fontSize: 11.5, color: p.muted)),
        const SizedBox(width: 8),
        TextButton(onPressed: () => launchUrl(Uri.parse('${run['html_url']}')), child: const Text('open')),
        if (run['status'] == 'completed')
          ZIconButton('fa-trash', tooltip: 'Delete this run from history', danger: true, size: 30, onPressed: () async {
            final ok = await confirmDialog(context, 'Delete run #${run['run_number']} (${run['name']}) from history?', title: 'Delete run', okLabel: 'Delete', danger: true);
            if (ok) await app.ghDeleteRun(run);
          }),
      ]),
    );
  }
}

// ---------------------------------------------------------------- repo files
class _FilesCard extends StatelessWidget {
  const _FilesCard();
  @override
  Widget build(BuildContext context) {
    final app = context.appWatch;
    final p = app.palette;
    final items = [...app.ghFiles]..sort((a, b) => a['type'] == b['type'] ? '${a['name']}'.compareTo('${b['name']}') : (a['type'] == 'dir' ? -1 : 1));
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionTitle('Repo Files (browse / push / delete)', icon: 'fa-folder-open', trailing: Wrap(spacing: 8, children: [
          ZButton('Up', icon: 'fa-level-up-alt', small: true, kind: ZBtnKind.ghost, onPressed: app.ghCurrentPath.isEmpty
              ? null
              : () {
                  final parts = app.ghCurrentPath.split('/')..removeLast();
                  app.ghListPath(parts.join('/'));
                }),
          ZButton('Refresh', icon: 'fa-arrows-rotate', small: true, kind: ZBtnKind.soft, busy: app.ghFilesLoading, onPressed: app.ghFilesLoading ? null : () => app.ghListPath(app.ghCurrentPath)),
          ZButton('Push file(s) here', icon: 'fa-upload', small: true, onPressed: () async {
            final files = await pickLocalFiles(title: 'Push files to /${app.ghCurrentPath}');
            if (files.isEmpty) return;
            await app.ghPushFiles([for (final f in files) (f.name, f.size, () async => (await f.bytes()).toList())]);
          }),
        ])),
        const SizedBox(height: 10),
        Text('/${app.ghCurrentPath}', style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: p.text, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (app.ghFilesLoading)
          const EmptyNote('Loading...', icon: 'fa-spinner')
        else if (app.ghFilesError != null)
          EmptyNote(app.ghFilesError!, icon: 'fa-exclamation-triangle')
        else if (items.isEmpty && app.ghCurrentPath.isEmpty && app.ghFiles.isEmpty)
          const EmptyNote('Save connection & hit Refresh to browse the repo.', icon: 'fa-folder-open')
        else if (items.isEmpty)
          const EmptyNote('Empty folder.')
        else
          for (final it in items)
            InkWell(
              onTap: it['type'] == 'dir' ? () => app.ghListPath('${it['path']}') : null,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: p.tintSoft, borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  Fa(it['type'] == 'dir' ? 'fa-folder' : 'fa-file-code', size: 14, color: it['type'] == 'dir' ? p.warn : p.muted),
                  const SizedBox(width: 10),
                  Expanded(child: Text('${it['name']}', style: TextStyle(fontWeight: FontWeight.w700, color: p.text, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Text(it['type'] == 'dir' ? 'folder' : '${(((it['size'] as num?) ?? 0) / 1024).toStringAsFixed(1)} KB', style: TextStyle(fontSize: 11.5, color: p.muted)),
                  if (it['type'] != 'dir') ...[
                    const SizedBox(width: 8),
                    ZIconButton('fa-trash', tooltip: 'Delete this file from the repo', danger: true, size: 30, onPressed: () async {
                      final ok = await confirmDialog(context, 'Delete "${it['path']}" from the repo? This creates a commit on ${app.ghCfg.branch.isEmpty ? 'main' : app.ghCfg.branch}.', title: 'Delete file', okLabel: 'Delete', danger: true);
                      if (ok) await app.ghDeleteFile(it);
                    }),
                  ],
                ]),
              ),
            ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- activity log
class _LogCard extends StatelessWidget {
  const _LogCard();
  @override
  Widget build(BuildContext context) {
    final app = context.appWatch;
    final p = app.palette;
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionTitle('Activity Log', icon: 'fa-terminal'),
        const SizedBox(height: 10),
        Container(
          height: 220,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(p.radiusSm)),
          child: ListView(
            reverse: true,
            children: [
              for (final l in app.ghLog.reversed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: SelectableText.rich(TextSpan(style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: p.onInk.withValues(alpha: 0.9)), children: [
                    TextSpan(text: '[${l.time}] ', style: TextStyle(color: p.onInk.withValues(alpha: 0.55))),
                    TextSpan(text: l.msg, style: TextStyle(color: l.kind == 'ok' ? p.ok : (l.kind == 'err' ? const Color(0xffff8080) : null))),
                  ])),
                ),
              Padding(padding: const EdgeInsets.only(bottom: 3), child: Text('[ready] GitHub Control panel loaded.', style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: p.onInk.withValues(alpha: 0.6)))),
            ],
          ),
        ),
      ]),
    );
  }
}
