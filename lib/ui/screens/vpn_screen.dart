import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/media.dart';
import '../../domain/vpn.dart';
import '../../state/app_state.dart';
import '../shell/app_shell.dart';
import '../widgets/common.dart';
import '../widgets/dropzone.dart';
import '../widgets/fa.dart';
import '../widgets/responsive.dart';

/// VPN tab (`initVpnPanel` / `vpnRender`): account tiles, mode, profiles, editor,
/// per-account GitHub connection, live test stepper + last result.
class VpnScreen extends StatelessWidget {
  const VpnScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.appWatch;
    final p = app.palette;
    final acc = app.vpnCurrent.toUpperCase();
    return PageBody(children: [
      GlassCard(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionTitle('VPN Control', icon: 'fa-shield-halved', trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: app.vpnLive ? p.ok : p.muted)),
            const SizedBox(width: 6),
            Text(app.vpnLive ? 'live' : 'connecting…', style: TextStyle(fontSize: 11.5, color: p.muted, fontWeight: FontWeight.w700)),
          ])),
          const SizedBox(height: 8),
          Text.rich(TextSpan(style: TextStyle(fontSize: 12.5, color: p.muted, height: 1.5), children: const [
            TextSpan(text: 'Route each Zedge runner through your own '),
            TextSpan(text: 'OpenVPN (.ovpn)', style: TextStyle(fontWeight: FontWeight.w800)),
            TextSpan(text: ' or '),
            TextSpan(text: 'WireGuard (.conf)', style: TextStyle(fontWeight: FontWeight.w800)),
            TextSpan(text: '. Each Zedge account has its own profiles, GitHub connection and live test status in its own Firebase database (shared with the Android app) - nothing is mixed between accounts.'),
          ])),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: p.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(p.radiusSm), border: Border.all(color: p.primary.withValues(alpha: 0.3))),
            child: Text.rich(TextSpan(style: TextStyle(fontSize: 12.5, color: p.text, height: 1.5), children: [
              const TextSpan(text: 'Working on '),
              TextSpan(text: acc, style: const TextStyle(fontWeight: FontWeight.w900)),
              const TextSpan(text: " - the account selected in the header. Everything on this page (profiles, mode, GitHub connection, test) is read from and saved to "),
              const TextSpan(text: "that account's Firebase only", style: TextStyle(fontWeight: FontWeight.w800)),
              const TextSpan(text: '. Switch account from the header dropdown or click a tile.'),
            ])),
          ),
          const SizedBox(height: 14),
          AutoGrid(minTile: 210, gap: 10, children: [for (final k in app.accountKeys) _Tile(account: k)]),
        ]),
      ),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (context, c) {
        final two = c.maxWidth >= Bp.md;
        final left = <Widget>[const _ProfilesCard(), const SizedBox(height: 16), _EditorCard(key: ValueKey('vpn-editor-${app.vpnCurrent}-${app.vpnEditorVersion}'))];
        final right = <Widget>[_ConnCard(key: ValueKey('vpn-conn-${app.vpnCurrent}')), const SizedBox(height: 16), const _TestCard()];
        if (!two) return Column(children: [...left, const SizedBox(height: 16), ...right]);
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 6, child: Column(children: left)),
          const SizedBox(width: 16),
          Expanded(flex: 5, child: Column(children: right)),
        ]);
      }),
    ]);
  }
}

String _vpnAgo(num? ts) {
  if (ts == null || ts == 0) return '';
  final s = ((DateTime.now().millisecondsSinceEpoch - ts) / 1000).round().clamp(0, 1 << 40);
  if (s < 60) return '${s}s ago';
  if (s < 3600) return '${(s / 60).round()} min ago';
  final d = DateTime.fromMillisecondsSinceEpoch(ts.toInt(), isUtc: true).add(const Duration(hours: 6));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year}, ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

Color _statusColor(String cls, dynamic p) => switch (cls) { 'ok' => p.ok, 'fail' => p.danger, 'busy' => p.warn, _ => p.muted };

class _Tile extends StatelessWidget {
  const _Tile({required this.account});
  final String account;
  @override
  Widget build(BuildContext context) {
    final app = context.appWatch;
    final p = app.palette;
    final s = app.vpnStates[account] ?? VpnState(null);
    final act = s.activeProfile;
    final lt = s.lastTest;
    final cls = vpnStatusClass(lt);
    final n = s.profiles.length;
    final on = s.mode != 'none' && act != null;
    final selected = account == app.vpnCurrent;
    return InkWell(
      onTap: selected ? null : () => app.connectToDatabase(account),
      borderRadius: BorderRadius.circular(p.radiusMd),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? p.primary.withValues(alpha: 0.1) : p.tintSoft,
          borderRadius: BorderRadius.circular(p.radiusMd),
          border: Border.all(color: selected ? p.primary : p.border, width: selected ? 1.6 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(account.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w900, color: p.text, letterSpacing: 0.4))),
            Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: _statusColor(cls, p))),
          ]),
          const SizedBox(height: 6),
          Text(on ? '${s.mode == 'wireguard' ? 'WireGuard' : 'OpenVPN'} · ${act['name']}' : 'Off - proxy / direct', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? p.ok : p.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Text('$n profile${n == 1 ? '' : 's'}${lt != null ? ' · test ${lt['status'] == 'ok' ? 'passed' : (lt['status'] == 'fail' ? 'failed' : lt['status'])} ${_vpnAgo(lt['at'] as num?)}' : ' · never tested'}', style: TextStyle(fontSize: 11, color: p.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- profiles + mode
class _ProfilesCard extends StatefulWidget {
  const _ProfilesCard();
  @override
  State<_ProfilesCard> createState() => _ProfilesCardState();
}

class _ProfilesCardState extends State<_ProfilesCard> {
  String? _mode;
  bool? _keep;
  String? _seenAcc;

  @override
  Widget build(BuildContext context) {
    final app = context.appWatch;
    final p = app.palette;
    final st = app.vpnState;
    if (_seenAcc != app.vpnCurrent) {
      _seenAcc = app.vpnCurrent;
      _mode = null;
      _keep = null;
    }
    final mode = _mode ?? st.mode;
    final keep = _keep ?? st.keepProxy;
    final items = st.profiles.values.toList()..sort((a, b) => ((b['updatedAt'] as num?) ?? 0).compareTo((a['updatedAt'] as num?) ?? 0));
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionTitle('Profiles', icon: 'fa-list', subtitle: app.vpnCurrent.toUpperCase(), trailing: ZButton('New profile', icon: 'fa-plus', small: true, kind: ZBtnKind.soft, onPressed: app.vpnEditorReset)),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.end, children: [
          Field('Mode for real runs', child: ZDropdown<String>(
            value: const ['none', 'openvpn', 'wireguard'].contains(mode) ? mode : 'none',
            width: 260,
            items: const [('none', 'Off - proxy / direct (as before)'), ('openvpn', 'OpenVPN - active profile'), ('wireguard', 'WireGuard - active profile')],
            onChanged: (v) => setState(() => _mode = v),
          )),
          Tooltip(
            message: 'Keep the HTTP proxy configured in the workflow active inside the VPN tunnel (proxy → VPN chain)',
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Checkbox(value: keep, onChanged: (v) => setState(() => _keep = v ?? false)),
              Text('Keep HTTP proxy inside VPN', style: TextStyle(fontSize: 12.5, color: p.text)),
            ]),
          ),
          ZButton('Save mode', icon: 'fa-save', small: true, onPressed: () async {
            await app.vpnSaveMode(mode, keep);
            setState(() {
              _mode = null;
              _keep = null;
            });
          }),
        ]),
        const SizedBox(height: 14),
        if (items.isEmpty)
          EmptyNote('No profiles for ${app.vpnCurrent.toUpperCase()} yet - add one in the editor below.', icon: 'fa-shield-halved')
        else
          for (final pr in items) _profileRow(context, app, p, pr, pr['id'] == st.activeProfileId),
      ]),
    );
  }

  Widget _profileRow(BuildContext context, AppState app, dynamic p, Map<String, dynamic> pr, bool active) {
    final a = vpnAnalyze('${pr['config'] ?? ''}', '${pr['type'] ?? ''}');
    final hasFiles = kVpnFileFields.any((f) => '${pr[f.key] ?? ''}'.isNotEmpty);
    final tags = <String>[
      pr['type'] == 'wireguard' ? 'WireGuard' : 'OpenVPN',
      if (a.remote.isNotEmpty) a.remote,
      if ('${pr['username'] ?? ''}'.isNotEmpty) 'user/pass' else if (pr['type'] == 'openvpn') 'cert / no login',
      if (hasFiles) 'files attached' else if (a.inline.isNotEmpty) 'certs embedded',
      if ('${pr['extra'] ?? ''}'.isNotEmpty) 'extra lines',
    ];
    final id = '${pr['id']}';
    final name = '${pr['name'] ?? ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: active ? p.ok.withValues(alpha: 0.08) : p.tintSoft,
        borderRadius: BorderRadius.circular(p.radiusSm),
        border: Border.all(color: active ? p.ok.withValues(alpha: 0.5) : p.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (active) ...[Fa('fa-circle-check', size: 13, color: p.ok), const SizedBox(width: 6)],
          Expanded(child: Text(name, style: TextStyle(fontWeight: FontWeight.w800, color: p.text, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (active) Pill('ACTIVE', small: true, color: p.ok, fg: Colors.white),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, children: [for (final t in tags) Pill(t, small: true, color: p.tintChip, fg: p.muted)]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          ZButton('Test', icon: 'fa-vial', small: true, tooltip: 'Run a connection test on GitHub', busy: app.vpnTestBusy, onPressed: app.vpnTestBusy ? null : () => app.vpnRunTest(id, confirm: (m) => confirmDialog(context, m, title: 'VPN test', okLabel: 'Start anyway'))),
          if (!active) ZButton('Set active', icon: 'fa-bolt', small: true, kind: ZBtnKind.soft, onPressed: () => app.vpnSetActive(id)),
          ZIconButton('fa-pen', tooltip: 'Edit', size: 30, onPressed: () {
            app.vpnEditId = id;
            app.vpnEditorVersion++;
            app.touch();
          }),
          ZIconButton('fa-clone', tooltip: 'Copy to all ${app.accountKeys.length} accounts', size: 30, onPressed: () async {
            final ok = await confirmDialog(context, 'Copy "$name" to all ${app.accountKeys.length} accounts? Existing profiles with the same id are overwritten.', title: 'Copy profile', okLabel: 'Copy');
            if (ok) await app.vpnCopyProfile(id);
          }),
          ZIconButton('fa-trash', tooltip: 'Delete', size: 30, danger: true, onPressed: () async {
            final ok = await confirmDialog(context, 'Delete profile "$name" from ${app.vpnCurrent.toUpperCase()}?', title: 'Delete profile', okLabel: 'Delete', danger: true);
            if (ok) await app.vpnDeleteProfile(id);
          }),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------- editor
class _EditorCard extends StatefulWidget {
  const _EditorCard({super.key});
  @override
  State<_EditorCard> createState() => _EditorCardState();
}

class _EditorCardState extends State<_EditorCard> {
  final _name = TextEditingController();
  final _config = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _extra = TextEditingController();
  String _type = 'openvpn';
  bool _paste = false;
  bool _copyAll = false;
  bool _saving = false;
  String _editId = '';
  Map<String, String> get _files => context.app.vpnFiles;

  @override
  void initState() {
    super.initState();
    final app = context.app;
    _editId = app.vpnEditId;
    final p = _editId.isEmpty ? null : app.vpnState.profiles[_editId];
    if (p != null) {
      _name.text = '${p['name'] ?? ''}';
      _type = '${p['type'] ?? 'openvpn'}';
      _config.text = '${p['config'] ?? ''}';
      _user.text = '${p['username'] ?? ''}';
      _pass.text = '${p['password'] ?? ''}';
      _extra.text = '${p['extra'] ?? ''}';
      app.vpnFiles.clear();
      for (final f in kVpnFileFields) {
        if ('${p[f.key] ?? ''}'.isNotEmpty) app.vpnFiles[f.key] = '${p[f.key]}';
      }
      app.vpnAuthForced = _user.text.isNotEmpty;
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _config, _user, _pass, _extra]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _collect(AppState app) {
    final raw = _config.text.replaceAll('\r', '').trim();
    final a = vpnAnalyze(raw, _type);
    final name = _name.text.trim();
    if (name.isEmpty) throw Exception('Give the profile a name');
    if (a.empty) throw Exception('Drop or paste the .ovpn / .conf first');
    if (a.type == 'openvpn' && a.needsAuth && _user.text.trim().isEmpty) throw Exception('This .ovpn requires a username and password (auth-user-pass)');
    if (a.type == 'wireguard' && a.warnings.any((w) => w.contains('Missing'))) throw Exception(a.warnings.where((w) => w.contains('Missing')).join('; '));
    final missing = a.external.where((x) {
      final f = vpnFieldFor(x.directive);
      return f != null && (_files[f] ?? '').isEmpty;
    }).toList();
    if (missing.isNotEmpty) throw Exception('Upload the referenced file(s): ${missing.map((x) => x.file).join(', ')}');
    final unsupported = a.external.where((x) => vpnFieldFor(x.directive) == null).toList();
    if (unsupported.isNotEmpty) throw Exception('Unsupported external directive(s): ${unsupported.map((x) => x.directive).join(', ')} - embed them in the .ovpn');
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _editId.isNotEmpty ? _editId : 'vpn_${now.toRadixString(36)}${(now * 7919 % 1679616).toRadixString(36).padLeft(4, '0').substring(0, 4)}';
    final prev = app.vpnState.profiles[id] ?? const <String, dynamic>{};
    final p = <String, dynamic>{
      'id': id,
      'name': name,
      'type': a.type,
      'config': raw,
      'username': a.type == 'openvpn' ? _user.text.trim() : '',
      'password': a.type == 'openvpn' ? _pass.text : '',
      'extra': _extra.text.trim(),
      'createdAt': prev['createdAt'] ?? now,
      'updatedAt': now,
    };
    for (final f in kVpnFileFields) {
      p[f.key] = a.type == 'openvpn' && a.external.any((x) => vpnFieldFor(x.directive) == f.key) ? (_files[f.key] ?? '') : '';
    }
    return p;
  }

  Future<void> _save(bool andTest) async {
    final app = context.app;
    Map<String, dynamic> p;
    try {
      p = _collect(app);
    } catch (e) {
      final m = e.toString().replaceFirst('Exception: ', '');
      app.showToast(m, 'err');
      app.vpnLog(m, 'err');
      return;
    }
    setState(() => _saving = true);
    try {
      await app.vpnSaveProfile(p, copyAll: _copyAll);
      app.vpnEditorReset();
      if (andTest && mounted) await app.vpnRunTest('${p['id']}', confirm: (m) => confirmDialog(context, m, title: 'VPN test', okLabel: 'Start anyway'));
    } catch (e) {
      app.vpnLog('Save failed: $e', 'err');
      app.showToast('$e', 'err');
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _loadConfig(LocalFile f) async {
    final txt = utf8.decode(await f.bytes(), allowMalformed: true);
    setState(() {
      _config.text = txt;
      if (_name.text.trim().isEmpty) _name.text = f.name.replaceAll(RegExp(r'\.(ovpn|conf|txt)$', caseSensitive: false), '');
      final a = vpnAnalyze(txt, _type);
      if (!a.empty) _type = a.type;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.appWatch;
    final p = app.palette;
    final a = vpnAnalyze(_config.text, _type);
    if (!a.empty && a.type != _type) _type = a.type;
    final showAuth = a.type == 'openvpn' && (a.needsAuth || app.vpnAuthForced || _user.text.isNotEmpty);
    final missing = a.external.where((x) {
      final f = vpnFieldFor(x.directive);
      return f == null || (_files[f] ?? '').isEmpty;
    }).length;

    Widget step(String n, String title, {String? req, bool soft = false}) => Row(children: [
          Container(width: 22, height: 22, alignment: Alignment.center, decoration: BoxDecoration(gradient: p.primaryGradient, borderRadius: BorderRadius.circular(6)), child: Text(n, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: p.onPrimary))),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: p.text, fontSize: 13.5)),
          if (req != null) ...[const SizedBox(width: 8), Pill(req, small: true, color: soft ? p.tintChip : p.warn.withValues(alpha: 0.18), fg: soft ? p.muted : p.warn)],
        ]);

    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionTitle(_editId.isEmpty ? 'New profile' : 'Edit - ${_name.text}', icon: 'fa-pen-to-square', trailing: _editId.isEmpty ? null : ZButton('Cancel edit', small: true, kind: ZBtnKind.ghost, onPressed: app.vpnEditorReset)),
        const SizedBox(height: 14),
        step('1', 'Config file'),
        const SizedBox(height: 8),
        if (a.empty && !_paste)
          DropZone(
            title: 'Drop your .ovpn / WireGuard .conf here',
            subtitle: 'Type, login requirement and embedded certificates are detected automatically.',
            icon: 'fa-shield-halved',
            buttonLabel: 'Browse',
            extensions: const ['ovpn', 'conf', 'txt'],
            multiple: false,
            height: 120,
            dense: true,
            extra: TextButton(onPressed: () => setState(() => _paste = true), child: const Text('or paste text')),
            onFiles: (fl) async {
              if (fl.isNotEmpty) await _loadConfig(fl.first);
            },
          )
        else
          TextField(
            controller: _config,
            minLines: 6,
            maxLines: 14,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
            decoration: InputDecoration(hintText: 'Paste the .ovpn / .conf text here…', isDense: true, suffixIcon: _config.text.isEmpty ? null : IconButton(icon: const Icon(Icons.clear, size: 18), tooltip: 'Clear config', onPressed: () => setState(() {
              _config.clear();
              _paste = false;
            }))),
            onChanged: (_) => setState(() {}),
          ),
        if (!a.empty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            Pill(a.type == 'wireguard' ? 'WireGuard' : 'OpenVPN', small: true, color: p.primary.withValues(alpha: 0.18), fg: p.primary),
            if (a.remote.isNotEmpty) Pill(a.remote, small: true, color: p.tintChip, fg: p.text),
            if (a.type == 'openvpn') Pill(a.needsAuth ? 'username / password required' : 'no login required', small: true, color: (a.needsAuth ? p.warn : p.ok).withValues(alpha: 0.18), fg: a.needsAuth ? p.warn : p.ok),
            if (a.inline.isNotEmpty) Pill('certs embedded (${a.inline.length})', small: true, color: p.ok.withValues(alpha: 0.18), fg: p.ok),
            if (a.external.isNotEmpty) Pill('${a.external.length} external file${a.external.length > 1 ? 's' : ''}${missing > 0 ? ' - $missing to upload' : ' - all attached'}', small: true, color: (missing > 0 ? p.warn : p.ok).withValues(alpha: 0.18), fg: missing > 0 ? p.warn : p.ok),
          ]),
          if (a.warnings.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Fa('fa-triangle-exclamation', size: 12, color: p.warn), const SizedBox(width: 6), Expanded(child: Text(a.warnings.join(' · '), style: TextStyle(fontSize: 12, color: p.warn, fontWeight: FontWeight.w700)))])),
          if (a.hints.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Fa('fa-info-circle', size: 12, color: p.muted), const SizedBox(width: 6), Expanded(child: Text(a.hints.join(' · '), style: TextStyle(fontSize: 12, color: p.muted)))])),
        ],
        const SizedBox(height: 16),
        step('2', 'Details'),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.end, children: [
          Field('Profile name', width: 260, child: TextField(controller: _name, decoration: const InputDecoration(hintText: 'e.g. Frankfurt - ProtonVPN', isDense: true), onChanged: (_) => setState(() {}))),
          Field('Type', child: Segmented<String>(options: const [('openvpn', 'OpenVPN (.ovpn)'), ('wireguard', 'WireGuard (.conf)')], value: _type, onChanged: (v) => setState(() => _type = v))),
        ]),
        if (showAuth) ...[
          const SizedBox(height: 16),
          step('3', 'Login', req: a.needsAuth ? 'required by this config (auth-user-pass)' : 'optional', soft: !a.needsAuth),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 10, children: [
            Field('Username', width: 220, child: TextField(controller: _user, decoration: const InputDecoration(isDense: true), onChanged: (_) => setState(() {}))),
            Field('Password', width: 220, child: TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(isDense: true))),
          ]),
        ] else if (a.type == 'openvpn' && !a.empty) ...[
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () {
            app.vpnAuthForced = true;
            app.touch();
          }, icon: const Icon(Icons.add, size: 16), label: const Text('This VPN also needs a username / password'))),
        ],
        if (a.type == 'openvpn' && a.external.isNotEmpty) ...[
          const SizedBox(height: 16),
          step(showAuth ? '4' : '3', 'Referenced files', req: 'this .ovpn points to separate files', soft: true),
          const SizedBox(height: 8),
          for (final x in a.external) _fileRow(app, p, x),
        ],
        const SizedBox(height: 16),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('Advanced - extra config lines', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.text)),
          children: [TextField(controller: _extra, minLines: 3, maxLines: 8, style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5), decoration: const InputDecoration(hintText: 'Appended to the config on the runner (one directive per line)', isDense: true))],
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          ZButton('Save profile', icon: 'fa-save', busy: _saving, onPressed: _saving ? null : () => _save(false)),
          ZButton('Save & test', icon: 'fa-vial', kind: ZBtnKind.soft, busy: _saving, onPressed: _saving ? null : () => _save(true)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Checkbox(value: _copyAll, onChanged: (v) => setState(() => _copyAll = v ?? false)),
            Text('Save to all ${app.accountKeys.length} accounts', style: TextStyle(fontSize: 12.5, color: p.text)),
          ]),
        ]),
      ]),
    );
  }

  Widget _fileRow(AppState app, dynamic p, VpnExternalRef x) {
    final f = vpnFieldFor(x.directive);
    if (f == null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: p.warn.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Expanded(child: Text('${x.directive} ${x.file}', style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: p.text))),
          Text('not supported inline - convert to an embedded <tag> block', style: TextStyle(fontSize: 11.5, color: p.warn, fontWeight: FontWeight.w700)),
        ]),
      );
    }
    final field = vpnFieldByKey(f)!;
    final have = (_files[f] ?? '').isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: p.tintSoft, borderRadius: BorderRadius.circular(10), border: Border.all(color: have ? p.ok.withValues(alpha: 0.4) : p.border)),
      child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, runSpacing: 6, children: [
        Text.rich(TextSpan(children: [TextSpan(text: '${field.label} ', style: TextStyle(fontWeight: FontWeight.w800, color: p.text, fontSize: 12.5)), TextSpan(text: x.file, style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: p.muted))])),
        Pill(have ? 'attached (${_files[f]!.length} chars)' : 'needed', icon: have ? 'fa-check' : null, small: true, color: (have ? p.ok : p.warn).withValues(alpha: 0.18), fg: have ? p.ok : p.warn),
        ZButton(have ? 'Replace' : 'Upload', icon: 'fa-upload', small: true, kind: ZBtnKind.soft, onPressed: () async {
          final fl = await pickLocalFiles(multiple: false, extensions: [...field.accept.split(',').map((e) => e.replaceAll('.', '').trim()), 'txt'], title: field.label);
          if (fl.isEmpty) return;
          app.vpnFiles[f] = utf8.decode(await fl.first.bytes(), allowMalformed: true);
          setState(() {});
        }),
        if (have) ZIconButton('fa-times', tooltip: 'Remove', size: 28, danger: true, onPressed: () => setState(() => app.vpnFiles.remove(f))),
      ]),
    );
  }
}

// ---------------------------------------------------------------- per-account GitHub connection
class _ConnCard extends StatefulWidget {
  const _ConnCard({super.key});
  @override
  State<_ConnCard> createState() => _ConnCardState();
}

class _ConnCardState extends State<_ConnCard> {
  final _link = TextEditingController();
  final _owner = TextEditingController();
  final _repo = TextEditingController();
  final _branch = TextEditingController();
  final _wf = TextEditingController();
  final _token = TextEditingController();
  bool _show = false;
  String _status = '';
  String _statusCls = '';
  bool _checking = false;
  VpnGhCfg? _cfg;
  String? _seenGithub;

  @override
  void initState() {
    super.initState();
    _fill();
  }

  Future<void> _fill() async {
    final app = context.app;
    final cfg = await app.vpnGhCfg();
    if (!mounted) return;
    setState(() {
      _cfg = cfg;
      _link.text = cfg.owner.isNotEmpty && cfg.repo.isNotEmpty ? 'https://github.com/${cfg.owner}/${cfg.repo}' : '';
      _owner.text = cfg.owner;
      _repo.text = cfg.repo;
      _branch.text = cfg.branch;
      _wf.text = cfg.workflow;
      _token.text = cfg.token;
    });
  }

  @override
  void dispose() {
    for (final c in [_link, _owner, _repo, _branch, _wf, _token]) {
      c.dispose();
    }
    super.dispose();
  }

  VpnGhCfg _current() {
    final link = ghParseRepoLink(_link.text);
    return VpnGhCfg(
      owner: (_owner.text.trim().isNotEmpty ? _owner.text.trim() : (link?.$1 ?? '')),
      repo: (_repo.text.trim().isNotEmpty ? _repo.text.trim() : (link?.$2 ?? '')),
      branch: _branch.text.trim().isEmpty ? 'main' : _branch.text.trim(),
      workflow: _wf.text.trim().isEmpty ? '${context.app.vpnCurrent}.yml' : _wf.text.trim(),
      token: _token.text.trim(),
    );
  }

  Future<void> _save() async {
    final app = context.app;
    final c = _current();
    if (c.owner.isEmpty || c.repo.isEmpty || c.token.isEmpty) {
      app.showToast('Owner, repository and token are required for ${app.vpnCurrent.toUpperCase()}', 'err');
      return;
    }
    try {
      await app.vpnConnSave({'owner': c.owner, 'repo': c.repo, 'branch': c.branch, 'workflow': c.workflow, 'token': c.token});
    } catch (e) {
      app.vpnLog('Save failed: $e', 'err');
      app.showToast('$e', 'err');
    }
    await _fill();
  }

  Future<void> _check() async {
    final app = context.app;
    final key = app.vpnCurrent;
    final cfg = await app.vpnGhCfg(key);
    if (!cfg.ready) {
      setState(() => _cfg = cfg);
      return;
    }
    setState(() {
      _checking = true;
      _status = 'checking...';
      _statusCls = '';
    });
    try {
      final repo = await app.vpnGhApi(key, '/repos/${cfg.owner}/${cfg.repo}') as Map;
      final wf = await app.vpnGhApi(key, '/repos/${cfg.owner}/${cfg.repo}/actions/workflows/${Uri.encodeComponent(cfg.workflow)}') as Map;
      bool? v24;
      try {
        final file = await app.vpnGhApi(key, '/repos/${cfg.owner}/${cfg.repo}/contents/.github/workflows/${Uri.encodeComponent(cfg.workflow)}?ref=${Uri.encodeComponent(cfg.branch)}') as Map;
        final txt = utf8.decode(base64.decode('${file['content'] ?? ''}'.replaceAll('\n', '')));
        v24 = txt.contains('run_mode:') && txt.contains('vpn_profile:');
      } catch (_) {}
      final okState = wf['state'] == 'active';
      final good = okState && v24 != false;
      setState(() {
        _status = okState ? (v24 == false ? 'workflow is not v24' : 'OK') : 'workflow ${wf['state']}';
        _statusCls = good ? 'ok' : 'err';
      });
      app.vpnLog('Check: ${repo['full_name']} (${repo['private'] == true ? 'private' : 'public'}) - ${wf['name']} [${wf['state']}]${v24 == null ? '' : (v24 ? ' - v24 inputs present' : ' - MISSING run_mode/vpn_profile inputs, upload the v24 workflow')}', good ? 'ok' : 'err');
      app.showToast(good ? 'Connection OK for ${key.toUpperCase()}' : 'Check failed - see Activity Log', good ? 'ok' : 'err');
    } catch (e) {
      setState(() {
        _status = 'error';
        _statusCls = 'err';
      });
      app.vpnLog('Check failed: $e', 'err');
      app.showToast('$e', 'err');
    }
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.appWatch;
    final p = app.palette;
    final acc = app.vpnCurrent.toUpperCase();
    final gh = jsonEncode(app.vpnState.github ?? const {});
    if (_seenGithub != null && _seenGithub != gh) {
      _seenGithub = gh;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fill());
    }
    _seenGithub ??= gh;
    final cfg = _cfg;
    final ready = cfg?.ready ?? false;
    final miss = cfg == null ? '' : [if (cfg.owner.isEmpty) 'owner', if (cfg.repo.isEmpty) 'repository', if (cfg.workflow.isEmpty) 'workflow file', if (cfg.token.isEmpty) 'token'].join(', ');
    final st = _status.isNotEmpty ? _status : (ready ? 'ready' : 'missing');
    final stCls = _status.isNotEmpty ? _statusCls : (ready ? 'ok' : 'err');
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionTitle('GitHub connection', icon: 'fa-github', subtitle: acc, trailing: Text(st, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: stCls == 'ok' ? p.ok : (stCls == 'err' ? p.danger : p.muted)))),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: (ready ? p.ok : p.danger).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Fa(ready ? 'fa-link' : 'fa-triangle-exclamation', size: 13, color: ready ? p.ok : p.danger),
            const SizedBox(width: 8),
            Expanded(
              child: cfg == null
                  ? Text('-', style: TextStyle(color: p.muted))
                  : ready
                      ? Text.rich(TextSpan(style: TextStyle(fontSize: 12.5, color: p.text), children: [
                          TextSpan(text: '${cfg.owner}/${cfg.repo}', style: const TextStyle(fontWeight: FontWeight.w800)),
                          const TextSpan(text: ' · '),
                          TextSpan(text: cfg.workflow, style: const TextStyle(fontFamily: 'monospace')),
                          TextSpan(text: ' · ${cfg.branch} · token •••${cfg.token.length > 4 ? cfg.token.substring(cfg.token.length - 4) : ''}'),
                        ]))
                      : Text("$acc has no GitHub connection yet - enter this account's $miss above and Save. Test cannot run until then.", style: TextStyle(fontSize: 12.5, color: p.danger, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        Text.rich(TextSpan(style: TextStyle(fontSize: 12, color: p.muted, height: 1.5), children: [
          TextSpan(text: acc, style: const TextStyle(fontWeight: FontWeight.w800)),
          const TextSpan(text: ' has its '),
          const TextSpan(text: 'own GitHub account, repo and token', style: TextStyle(fontWeight: FontWeight.w800)),
          const TextSpan(text: ". Enter them here - they are saved only in this account's Firebase and used for this account's Test / real runs. Nothing is shared with other accounts or with GitHub Control."),
        ])),
        const SizedBox(height: 12),
        Field('Repo link / path', child: TextField(controller: _link, decoration: const InputDecoration(hintText: 'https://github.com/owner/repo', isDense: true), onChanged: (v) {
          final r = ghParseRepoLink(v);
          if (r != null) {
            _owner.text = r.$1;
            _repo.text = r.$2;
          }
        })),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          Field('Owner (user/org)', width: 170, child: TextField(controller: _owner, decoration: const InputDecoration(isDense: true))),
          Field('Repository', width: 170, child: TextField(controller: _repo, decoration: const InputDecoration(isDense: true))),
          Field('Branch', width: 120, child: TextField(controller: _branch, decoration: const InputDecoration(hintText: 'main', isDense: true))),
          Field('Workflow file', width: 170, child: TextField(controller: _wf, decoration: InputDecoration(hintText: '${app.vpnCurrent}.yml', isDense: true))),
        ]),
        const SizedBox(height: 10),
        Field('Token (Actions + Contents read/write)', child: TextField(controller: _token, obscureText: !_show, decoration: InputDecoration(isDense: true, suffixIcon: IconButton(icon: Icon(_show ? Icons.visibility_off : Icons.visibility, size: 18), onPressed: () => setState(() => _show = !_show))))),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ZButton('Save', icon: 'fa-save', small: true, onPressed: _save),
          ZButton('Check repo & workflow', icon: 'fa-vial', small: true, kind: ZBtnKind.soft, busy: _checking, onPressed: _checking ? null : _check),
        ]),
        const SizedBox(height: 10),
        Text.rich(TextSpan(style: TextStyle(fontSize: 11.5, color: p.muted, height: 1.5), children: const [
          TextSpan(text: "Saved in this account's Firebase ("),
          TextSpan(text: 'dashboardSettings/vpn/github', style: TextStyle(fontFamily: 'monospace')),
          TextSpan(text: ') + this device, so the Android app uses the same connection for this account. '),
          TextSpan(text: 'Check', style: TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: ' verifies the token, the repo and that the workflow file on GitHub is v24 (has the '),
          TextSpan(text: 'run_mode', style: TextStyle(fontFamily: 'monospace')),
          TextSpan(text: ' input).'),
        ])),
      ]),
    );
  }
}

// ---------------------------------------------------------------- live test
class _TestCard extends StatelessWidget {
  const _TestCard();
  @override
  Widget build(BuildContext context) {
    final app = context.appWatch;
    final p = app.palette;
    final st = app.vpnState;
    final r = st.lastTest;
    final acc = app.vpnCurrent.toUpperCase();
    final canTest = st.activeProfile != null && !app.vpnTestBusy;
    return ValueListenableBuilder<int>(
      valueListenable: app.clockTick,
      builder: (context, _, __) => GlassCard(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionTitle('Live test', icon: 'fa-vial', subtitle: acc, trailing: ZButton('Test active profile', icon: 'fa-play', small: true, busy: app.vpnTestBusy, onPressed: canTest ? () => app.vpnRunTest(null, confirm: (m) => confirmDialog(context, m, title: 'VPN test', okLabel: 'Start anyway')) : null)),
          const SizedBox(height: 14),
          if (r == null)
            EmptyNote('No test yet for $acc. Save a profile and press Test.', icon: 'fa-vial')
          else ...[
            _stepper(p, r),
            const SizedBox(height: 12),
            _result(p, r),
          ],
          const SizedBox(height: 12),
          Text.rich(TextSpan(style: TextStyle(fontSize: 11.5, color: p.muted, height: 1.5), children: const [
            TextSpan(text: "Test = this account's workflow runs in "),
            TextSpan(text: 'vpn_test', style: TextStyle(fontFamily: 'monospace')),
            TextSpan(text: ' mode (automation skipped): IP before → connect → IP after + zedge.net check → disconnect. The runner writes every stage to '),
            TextSpan(text: 'dashboardSettings/vpn/lastTest', style: TextStyle(fontFamily: 'monospace')),
            TextSpan(text: " in this account's Firebase, which streams here and to the Android app in real time."),
          ])),
        ]),
      ),
    );
  }

  Widget _stepper(dynamic p, Map<String, dynamic> r) {
    var idx = kVpnStages.indexWhere((s) => s[0] == r['stage']);
    if (idx < 0) idx = 0;
    final failed = r['status'] == 'fail', done = r['status'] == 'ok';
    final children = <Widget>[];
    for (var i = 0; i < kVpnStages.length; i++) {
      final cls = (i < idx || done) ? 'done' : (i == idx ? (failed ? 'fail' : 'current') : '');
      final color = switch (cls) { 'done' => p.ok, 'fail' => p.danger, 'current' => p.warn, _ => p.border };
      children.add(Expanded(
        child: Column(children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: cls.isEmpty ? p.tintSoft : color.withValues(alpha: 0.18), border: Border.all(color: color, width: 1.5)),
            child: cls == 'done'
                ? Fa('fa-check', size: 11, color: color)
                : cls == 'fail'
                    ? Fa('fa-xmark', size: 11, color: color)
                    : cls == 'current'
                        ? SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: color))
                        : Text('${i + 1}', style: TextStyle(fontSize: 11, color: p.muted, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 4),
          Text(kVpnStages[i][1], textAlign: TextAlign.center, style: TextStyle(fontSize: 9.5, color: cls.isEmpty ? p.muted : p.text, fontWeight: FontWeight.w700)),
        ]),
      ));
      if (i < kVpnStages.length - 1) children.add(Container(width: 14, height: 2, margin: const EdgeInsets.only(bottom: 18), color: (i < idx || done) ? p.ok : p.border));
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget _result(dynamic p, Map<String, dynamic> r) {
    final cls = vpnStatusClass(r);
    final color = _statusColor(cls, p);
    final done = r['status'] == 'ok', failed = r['status'] == 'fail';
    final rows = <(String, Widget)>[];
    Widget t(String s, {bool bold = false, String? mono}) => Text.rich(TextSpan(children: [TextSpan(text: s, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500)), if (mono != null) TextSpan(text: ' · $mono', style: const TextStyle(fontFamily: 'monospace'))]), style: TextStyle(fontSize: 12.5, color: p.text));
    rows.add(('Profile', Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [t('${r['profileName'] ?? r['profileId'] ?? '-'}'), if (r['type'] != null) Pill('${r['type']}', small: true, color: p.tintChip, fg: p.muted)])));
    if (r['repo'] != null) rows.add(('Workflow', t('${r['repo']}', mono: '${r['workflow'] ?? ''}')));
    if (r['ipBefore'] != null) rows.add(('IP before', t(vpnFmtIp(r['ipBefore']))));
    if (r['ipAfter'] != null) rows.add(('IP after', t(vpnFmtIp(r['ipAfter']), bold: true)));
    if (r['zedgeOk'] != null) rows.add(('zedge.net', r['zedgeOk'] == true ? Pill('reachable${r['zedgeStatus'] != null ? ' (HTTP ${r['zedgeStatus']})' : ''}', small: true, color: p.ok.withValues(alpha: 0.18), fg: p.ok) : Pill('NOT reachable', small: true, color: p.warn.withValues(alpha: 0.18), fg: p.warn)));
    if (r['durationMs'] is num) rows.add(('Duration', t('${((r['durationMs'] as num) / 1000).round()}s')));
    if (r['runner'] != null) rows.add(('Runner', t('${r['runner']}')));
    rows.add(('Updated', Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
      t(_vpnAgo(r['at'] as num?)),
      if (r['runUrl'] != null) InkWell(onTap: () => launchUrl(Uri.parse('${r['runUrl']}')), child: Text('open run ↗', style: TextStyle(fontSize: 12.5, color: p.info, decoration: TextDecoration.underline))),
    ])));
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(p.radiusSm), border: Border.all(color: color.withValues(alpha: 0.4))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
          const SizedBox(width: 8),
          Text(done ? 'VPN works' : (failed ? 'Test failed' : (r['status'] == 'queued' ? 'Queued on GitHub' : 'Running')), style: TextStyle(fontWeight: FontWeight.w900, color: p.text, fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(child: Text('${r['message'] ?? ''}', style: TextStyle(fontSize: 12.5, color: p.muted), maxLines: 2, overflow: TextOverflow.ellipsis)),
        ]),
        if (r['detail'] != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${r['detail']}', style: TextStyle(fontSize: 12, color: p.text))),
        const SizedBox(height: 10),
        for (final (k, v) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 90, child: Text(k, style: TextStyle(fontSize: 11.5, color: p.muted, fontWeight: FontWeight.w700))),
              Expanded(child: v),
            ]),
          ),
        if (r['logTail'] != null)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Runner log tail', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.text)),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(8)),
                child: SelectableText('${r['logTail']}', style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: p.onInk)),
              ),
            ],
          ),
      ]),
    );
  }
}
