import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';
import '../widgets/pool_picker.dart';

/// Admin-only storage overview mirroring the web app's Storage view:
/// heading + Check again, summary card, per-R2 pool cards, member-storage
/// card, member stats, MEMBER table with per-member limits, and the
/// R2 setup-instructions card.
class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});
  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  List<StoragePool>? _pools;
  Map<String, dynamic>? _settings;
  List<TeamMember>? _members;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  ApiClient get _api => context.read<SessionProvider>().api;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = _api;
    final pools = await guard(context, () => api.getStorage());
    final settings =
        pools == null ? null : await guard(context, () => api.getSettings());
    final members =
        pools == null ? null : await guard(context, () => api.getMembers());
    if (!mounted) return;
    setState(() {
      _pools = pools;
      _settings = settings;
      _members = members;
      _loading = false;
      if (pools == null) _error = 'Could not load storage info.';
    });
  }

  Future<void> _toggleMembersOnExtra(bool v) async {
    final ok = await guard(context, () async {
      await _api.updateSettings({'membersOnExtra': v});
      return true;
    });
    if (!mounted || ok != true) return;
    showMsg(
        context,
        v
            ? 'Member ra ekhon shudhu extra R2 use korbe'
            : 'Member ra sob storage use korte parbe');
    _load();
  }

  Future<void> _setQuota(TeamMember m) async {
    final saved = await showMemberQuotaDialog(context, _api, m);
    if (!mounted || !saved) return;
    _load();
  }

  /// Default-limit picker (Custom / Unlimited / Upload off), saved to
  /// settings.defaultQuotaGB — mirrors the web's limitPicker.
  Future<void> _changeDefaultLimit() async {
    final cur = _defaultGB;
    String mode = cur == -1 ? 'unl' : cur == 0 ? 'off' : 'custom';
    final numCtrl = TextEditingController(
        text: cur > 0
            ? (cur < 1 ? (cur * 1024).round().toString() : _trimNum(cur))
            : '500');
    String unit = (cur > 0 && cur < 1) ? 'MB' : 'GB';
    final night = context.read<ThemeProvider>().night;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDlg) => AlertDialog(
          title: const Text('Default storage limit'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('all members (jader custom limit nai)',
                  style: TextStyle(
                      fontSize: 12,
                      color:
                          night ? AppColors.nightMuted : AppColors.dayMuted)),
              const SizedBox(height: 12),
              _limitOpt(
                  night: night,
                  selected: mode == 'custom',
                  icon: Icons.storage,
                  title: 'Custom',
                  sub: 'Nijer moto MB / GB set korun',
                  onTap: () => setDlg(() => mode = 'custom'),
                  extra: mode == 'custom'
                      ? Row(children: [
                          Expanded(
                            child: TextField(
                              controller: numCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                  labelText: 'Amount'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          DropdownButton<String>(
                            value: unit,
                            items: const [
                              DropdownMenuItem(
                                  value: 'MB', child: Text('MB')),
                              DropdownMenuItem(
                                  value: 'GB', child: Text('GB')),
                            ],
                            onChanged: (v) => setDlg(() => unit = v ?? 'MB'),
                          ),
                        ])
                      : null),
              _limitOpt(
                  night: night,
                  selected: mode == 'unl',
                  icon: Icons.all_inclusive,
                  title: 'Unlimited',
                  sub: 'Kono limit nai (R2 er total jayga porjonto)',
                  onTap: () => setDlg(() => mode = 'unl')),
              _limitOpt(
                  night: night,
                  selected: mode == 'off',
                  icon: Icons.block_outlined,
                  title: 'Upload off',
                  sub: 'Shudhu dekhte/download korte parbe',
                  onTap: () => setDlg(() => mode = 'off')),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    final numText = numCtrl.text.trim();
    numCtrl.dispose();
    if (ok != true || !mounted) return;
    double q;
    if (mode == 'unl') {
      q = -1;
    } else if (mode == 'off') {
      q = 0;
    } else {
      final n = double.tryParse(numText);
      if (n == null || n <= 0) {
        showMsg(context, 'Enter a valid amount.', error: true);
        return;
      }
      q = unit == 'MB' ? n / 1024 : n;
    }
    final saved = await guard(context, () async {
      await _api.updateSettings({'defaultQuotaGB': q});
      return true;
    });
    if (!mounted || saved != true) return;
    showMsg(context, 'Default limit: ${_qLabel(q)}');
    _load();
  }

  double get _defaultGB {
    final v = _settings?['defaultQuotaGB'];
    return v is num ? v.toDouble() : 0.5;
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final night = context.watch<ThemeProvider>().night;
    if (!session.isAdmin) {
      return const Scaffold(
        body: EmptyView(
            icon: Icons.lock_outline,
            message: 'Storage is for admins only.'),
      );
    }
    return Scaffold(body: _buildBody(night));
  }

  Widget _buildBody(bool night) {
    if (_loading) return const LoadingView(label: 'Loading storage…');
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    final pools = _pools ?? [];
    final settings = _settings ?? {};
    final members = (_members ?? []).toList()
      ..sort((a, b) => a.username.compareTo(b.username));
    final avatars = context.read<SessionProvider>().drive?.avatars ?? {};

    final used = pools.fold<int>(0, (s, p) => s + p.used);
    final limit = pools.fold<int>(0, (s, p) => s + p.limit);
    final files = pools.fold<int>(0, (s, p) => s + p.files);
    final free = max(0, limit - used);
    final bad = pools.where((p) => !p.ok).length;
    StoragePool? next;
    for (final p in pools) {
      if (p.ok && !p.readOnly && p.used < p.limit) {
        next = p;
        break;
      }
    }

    final extra =
        pools.where((p) => p.kind != 'binding' && !p.readOnly).toList();
    final on = settings['membersOnExtra'] != false;
    final isolate = extra.isNotEmpty && on;
    final capPools =
        (isolate ? extra : pools.where((p) => !p.readOnly)).toList();
    final cap = capPools.fold<int>(0, (s, p) => s + p.limit);
    final alloc =
        members.fold<int>(0, (s, m) => s + (m.quota > 0 ? m.quota : 0));
    final unl = members.where((m) => m.quota == -1).length;
    final mUsed = members.fold<int>(0, (s, m) => s + m.size);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _headerRow(night),
          const SizedBox(height: 14),
          _summaryCard(used, limit, files, free, next, pools.length, night),
          if (bad > 0) ...[
            const SizedBox(height: 12),
            _warnBox(
                night,
                '$bad ta storage connect hocche na — oi account er file download hobe na. Key / Account ID check korun.'),
          ],
          const SizedBox(height: 14),
          _poolGrid(pools, on, night),
          const SizedBox(height: 14),
          _memberStorageCard(extra, isolate, on, night),
          const SizedBox(height: 14),
          _statsCard(members, alloc, unl, mUsed, cap, isolate, night),
          const SizedBox(height: 14),
          _memberTableCard(members, avatars, night),
          const SizedBox(height: 14),
          _setupCard(night),
        ],
      ),
    );
  }

  Widget _headerRow(bool night) => Row(
        children: [
          const Text('Storage',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const Spacer(),
          // White pill, gray text, magnifier — subtle/disabled look, refreshes.
          Opacity(
            opacity: 0.55,
            child: Material(
              color: night ? AppColors.nightPanel : Colors.white,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _load,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: night
                            ? AppColors.nightLine
                            : const Color(0xFFE5E5E5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search_outlined,
                          size: 14,
                          color: night
                              ? AppColors.nightMuted
                              : const Color(0xFF6B7280)),
                      const SizedBox(width: 6),
                      Text('Check again',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: night
                                  ? AppColors.nightMuted
                                  : const Color(0xFF6B7280))),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );

  /// Summary card: 3 columns + thin blue progress bar along the bottom.
  Widget _summaryCard(int used, int limit, int files, int free,
      StoragePool? next, int poolCount, bool night) {
    final ok = night ? AppColors.okDark : AppColors.okLight;
    final frac = limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0.0;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: _cardDeco(night),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: _stat('Total capacity', formatBytes(limit),
                      '$poolCount R2 account${poolCount == 1 ? '' : 's'}',
                      night)),
              Expanded(
                  child:
                      _stat('Used', formatBytes(used), '$files files', night)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Free',
                        style: TextStyle(
                            fontSize: 12,
                            color: night
                                ? AppColors.nightMuted
                                : AppColors.dayMuted)),
                    Text(formatBytes(free),
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: ok)),
                    Text(
                        next != null
                            ? 'Next upload → ${next.name}'
                            : 'No space left',
                        style: TextStyle(
                            fontSize: 12,
                            color: night
                                ? AppColors.nightMuted
                                : AppColors.dayMuted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _thinBar(frac, night, night ? AppColors.brandDark : AppColors.brandLight),
        ],
      ),
    );
  }

  Widget _stat(String label, String big, String small, bool night) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: night ? AppColors.nightMuted : AppColors.dayMuted)),
          const SizedBox(height: 2),
          Text(big,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          Text(small,
              style: TextStyle(
                  fontSize: 12,
                  color: night ? AppColors.nightMuted : AppColors.dayMuted)),
        ],
      );

  /// Per-R2 pool cards, two side by side on wide screens.
  Widget _poolGrid(List<StoragePool> pools, bool on, bool night) {
    return LayoutBuilder(builder: (c, cons) {
      final two = cons.maxWidth > 700;
      final w = two ? (cons.maxWidth - 14) / 2 : cons.maxWidth;
      return Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [
          for (var i = 0; i < pools.length; i++)
            SizedBox(width: w, child: _poolCard(pools[i], i, pools, on, night)),
        ],
      );
    });
  }

  Widget _poolCard(
      StoragePool p, int i, List<StoragePool> pools, bool on, bool night) {
    final brand = night ? AppColors.brandDark : AppColors.brandLight;
    final danger = night ? AppColors.dangerDark : AppColors.dangerLight;
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    final isBinding = p.kind == 'binding';
    final hasExtraWritable =
        pools.any((x) => x.kind != 'binding' && !x.readOnly);
    final showTags = pools.length > 1 && on && hasExtraWritable;
    final frac = p.limit > 0 ? (p.used / p.limit).clamp(0.0, 1.0) : 0.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: _cardDeco(night),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: p.ok
                      ? (night
                          ? AppColors.nightBrandTint
                          : const Color(0xFFEEF2FF))
                      : (night
                          ? const Color(0xFF3A2222)
                          : const Color(0xFFFEF2F2)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                    isBinding
                        ? Icons.house_outlined
                        : Icons.cloud_outlined,
                    size: 19,
                    color: p.ok ? brand : danger),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${i + 1}. ${p.name}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14),
                        overflow: TextOverflow.ellipsis),
                    Text(
                        isBinding
                            ? "This Worker's bucket (MEDIA_BUCKET)"
                            : 'id: ${p.id} · bucket: ${p.bucket}',
                        style: TextStyle(fontSize: 12, color: muted),
                        overflow: TextOverflow.ellipsis),
                    if (showTags)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: isBinding
                            ? _tag('Admin only', Icons.shield_outlined,
                                const Color(0xFFF3E8FF), const Color(0xFF7E22CE),
                                const Color(0xFF3B1D5A), const Color(0xFFD8B4FE),
                                night)
                            : _tag(
                                'Members + admin',
                                Icons.group_outlined,
                                const Color(0xFFE0F2FE),
                                const Color(0xFF0369A1),
                                const Color(0xFF1C2F45),
                                const Color(0xFF7DD3FC),
                                night),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              p.ok
                  ? _pill('Connected', Icons.check_circle_outline,
                      const Color(0xFFECFDF5), const Color(0xFF15803D),
                      const Color(0xFF0F2E22), const Color(0xFF4ADE80), night)
                  : _pill('Error', Icons.error_outline,
                      const Color(0xFFFEF2F2), danger,
                      const Color(0xFF3A2222), danger, night),
            ],
          ),
          const SizedBox(height: 12),
          _thinBar(frac, night, brand),
          const SizedBox(height: 8),
          Row(
            children: [
              RichText(
                text: TextSpan(
                  style: TextStyle(
                      fontSize: 13,
                      color: night
                          ? AppColors.nightText
                          : AppColors.dayText),
                  children: [
                    TextSpan(
                        text: formatBytes(p.used),
                        style:
                            const TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: ' / ${formatBytes(p.limit)}'),
                  ],
                ),
              ),
              const Spacer(),
              Text('${p.files} files${p.readOnly ? ' · read-only' : ''}',
                  style: TextStyle(fontSize: 12, color: muted)),
            ],
          ),
          if (!p.ok && (p.error ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(p.error!, style: TextStyle(fontSize: 12, color: danger)),
          ],
        ],
      ),
    );
  }

  /// "Member storage" card: database tile, description, blue checkbox
  /// right-aligned.
  Widget _memberStorageCard(
      List<StoragePool> extra, bool isolate, bool on, bool night) {
    final brand = night ? AppColors.brandDark : AppColors.brandLight;
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    final canToggle = extra.isNotEmpty;
    final desc = isolate
        ? 'Member der file shudhu extra R2 te (${extra.map((p) => p.name).join(', ')}) jabe — Main R2 admin er jonno thakbe.'
        : extra.isNotEmpty
            ? 'Member ra sob R2 (Main soho) use korche.'
            : 'Ekhon shudhu Main R2 ache, tai member ra o Main R2 use korche. Extra R2 add korle member der oikhane pathano jabe.';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: night ? const Color(0xFF232323) : const Color(0xFFFAFBFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: night
                  ? AppColors.nightBrandTint
                  : const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(Icons.storage_outlined, size: 17, color: brand),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Member storage',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text(desc, style: TextStyle(fontSize: 12, color: muted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Opacity(
            opacity: canToggle ? 1.0 : 0.5,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: on,
                  activeColor: brand,
                  onChanged: canToggle
                      ? (v) => _toggleMembersOnExtra(v ?? true)
                      : null,
                ),
                const Text('Main R2 shudhu admin er jonno',
                    style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Stats row: default limit + Change, allocated, member usage, blue bar.
  Widget _statsCard(List<TeamMember> members, int alloc, int unl, int mUsed,
      int cap, bool isolate, bool night) {
    final brand = night ? AppColors.brandDark : AppColors.brandLight;
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    final frac = cap > 0 ? (alloc / cap).clamp(0.0, 1.0) : 0.0;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: _cardDeco(night),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Default limit / member',
                        style: TextStyle(fontSize: 12, color: muted)),
                    const SizedBox(height: 2),
                    Text(_qLabel(_defaultGB),
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    _smallWhitePill(
                        label: 'Change',
                        icon: Icons.edit_outlined,
                        onTap: _changeDefaultLimit),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Member der dewa hoyeche',
                        style: TextStyle(fontSize: 12, color: muted)),
                    const SizedBox(height: 2),
                    Text(formatBytes(alloc),
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w700)),
                    Text(
                        'of ${formatBytes(cap)} ${isolate ? 'extra R2' : 'total'}${unl > 0 ? ' · $unl unlimited' : ''}',
                        style: TextStyle(fontSize: 12, color: muted)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Member ra use korche',
                        style: TextStyle(fontSize: 12, color: muted)),
                    const SizedBox(height: 2),
                    Text(formatBytes(mUsed),
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w700)),
                    Text('${members.length} member',
                        style: TextStyle(fontSize: 12, color: muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _thinBar(frac, night, brand),
          if (alloc > cap) ...[
            const SizedBox(height: 12),
            _warnBox(night,
                'Member der limit er jogfol (${formatBytes(alloc)}) ${isolate ? 'extra R2' : 'storage'} er jayga (${formatBytes(cap)}) er cheye beshi. Sobai full use korle jayga kom porbe — limit komaan ba notun R2 add korun.'),
          ],
        ],
      ),
    );
  }

  /// MEMBER table: avatar + name + files, used/limit + bar + %, Set limit.
  Widget _memberTableCard(
      List<TeamMember> members, Map<String, String> avatars, bool night) {
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    return Container(
      decoration: _cardDeco(night),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text('MEMBER',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: muted)),
          ),
          if (members.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                  child: Text('Kono member nai — Members page theke add korun.',
                      style: TextStyle(fontSize: 13, color: muted))),
            )
          else
            for (var i = 0; i < members.length; i++) ...[
              if (i > 0)
                Divider(
                    height: 1,
                    color: night
                        ? AppColors.nightLine2
                        : AppColors.dayLine),
              _memberRow(members[i], avatars, night),
            ],
        ],
      ),
    );
  }

  Widget _memberRow(TeamMember m, Map<String, String> avatars, bool night) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AvatarWidget(
                  url: avatars[m.username], name: m.username, radius: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.username,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13),
                        overflow: TextOverflow.ellipsis),
                    Text('${m.files} files',
                        style: TextStyle(
                            fontSize: 12,
                            color: night
                                ? AppColors.nightMuted
                                : AppColors.dayMuted)),
                  ],
                ),
              ),
              _smallWhitePill(
                  label: 'Set limit',
                  icon: Icons.pie_chart_outline,
                  onTap: () => _setQuota(m)),
            ],
          ),
          const SizedBox(height: 8),
          _quotaCell(m, night),
        ],
      ),
    );
  }

  /// Web quotaCell: bold used, gray " / limit", optional (default) tag,
  /// progress bar (blue, red >90%, orange >70%), gray "% used".
  Widget _quotaCell(TeamMember m, bool night) {
    final brand = night ? AppColors.brandDark : AppColors.brandLight;
    final danger = night ? AppColors.dangerDark : AppColors.dangerLight;
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    final custom = m.quotaGB != null;
    final baseStyle = TextStyle(
        fontSize: 13, color: night ? AppColors.nightText : AppColors.dayText);
    if (m.quota == -1) {
      return RichText(
        text: TextSpan(style: baseStyle, children: [
          TextSpan(
              text: formatBytes(m.size),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(
              text: ' / Unlimited', style: TextStyle(color: muted)),
          if (!custom)
            TextSpan(
                text: ' (default)',
                style: TextStyle(color: muted, fontSize: 12)),
        ]),
      );
    }
    if (m.quota == 0) {
      return Row(children: [
        Text(formatBytes(m.size),
            style:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: danger.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text('Upload off',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: danger)),
        ),
      ]);
    }
    final pct =
        m.quota > 0 ? min(100.0, m.size / m.quota * 100) : 0.0;
    final barColor =
        pct > 90 ? danger : pct > 70 ? AppColors.warn : brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(style: baseStyle, children: [
            TextSpan(
                text: formatBytes(m.size),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(
                text: ' / ${formatBytes(m.quota)}',
                style: TextStyle(color: muted)),
            if (!custom)
              TextSpan(
                  text: ' (default)',
                  style: TextStyle(color: muted, fontSize: 12)),
          ]),
        ),
        const SizedBox(height: 6),
        _thinBar(pct / 100, night, barColor),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
              '${pct.toStringAsFixed(pct < 10 ? 1 : 0)}% used',
              style: TextStyle(fontSize: 12, color: muted)),
        ),
      ],
    );
  }

  /// R2 setup instructions card (Bengali steps, bold keywords).
  Widget _setupCard(bool night) {
    final brand = night ? AppColors.brandDark : AppColors.brandLight;
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    final text = night ? AppColors.nightText : AppColors.dayText;
    TextSpan b(String s) => TextSpan(
        text: s, style: TextStyle(fontWeight: FontWeight.w700, color: text));
    TextSpan code(String s) => TextSpan(
        text: s,
        style: TextStyle(
            fontWeight: FontWeight.w700,
            color: text,
            fontFamily: 'monospace',
            fontSize: 12));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: _cardDeco(night),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.add_circle_outline, color: brand, size: 18),
            const SizedBox(width: 8),
            const Text('Notun R2 account add korben kivabe',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          _step(1, [const TextSpan(text: 'Notun Cloudflare account e '), b('R2 → Create bucket')], muted),
          _step(2, [b('R2 → Manage API tokens → Create API token'), const TextSpan(text: ' (Object Read & Write, oi bucket) → Access Key ID, Secret, Account ID copy')], muted),
          _step(3, [const TextSpan(text: 'Main Worker e '), code('EXTRA_STORAGE'), const TextSpan(text: ' list e add korun (ba Secret hisebe) → '), b('Deploy')], muted),
          _step(4, [const TextSpan(text: 'Ei page e '), b('Check again'), const TextSpan(text: ' — "Connected" dekhale ready. Details: SETUP.md')], muted),
        ],
      ),
    );
  }

  Widget _step(int n, List<InlineSpan> spans, Color muted) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 20,
                child: Text('$n.',
                    style: TextStyle(fontSize: 13, color: muted))),
            Expanded(
              child: RichText(
                text: TextSpan(
                    style: TextStyle(
                        fontSize: 13, color: muted, height: 1.7),
                    children: spans),
              ),
            ),
          ],
        ),
      );

  // ---------------- small components ----------------

  Widget _thinBar(double frac, bool night, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: frac.clamp(0.0, 1.0),
        minHeight: 5,
        backgroundColor:
            night ? AppColors.nightLine : AppColors.dayLine,
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }

  Widget _tag(String label, IconData icon, Color dayBg, Color dayFg,
      Color nightBg, Color nightFg, bool night) {
    final bg = night ? nightBg : dayBg;
    final fg = night ? nightFg : dayFg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 4),
          Text(label,
              style:
                  TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }

  Widget _pill(String label, IconData icon, Color dayBg, Color dayFg,
      Color nightBg, Color nightFg, bool night) {
    final bg = night ? nightBg : dayBg;
    final fg = night ? nightFg : dayFg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(label,
              style:
                  TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }

  Widget _warnBox(bool night, String text) {
    final fg = night ? const Color(0xFFF0B77A) : const Color(0xFF9A3412);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: night ? const Color(0xFF2A2118) : const Color(0xFFFFF7ED),
        border: Border.all(
            color: night ? const Color(0xFF5A3A1A) : const Color(0xFFFED7AA)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_outlined, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text, style: TextStyle(fontSize: 13, color: fg))),
        ],
      ),
    );
  }

  Widget _smallWhitePill(
      {required String label,
      required IconData icon,
      required VoidCallback onTap}) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE5E5E5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: const Color(0xFF555555)),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF333333))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _limitOpt(
      {required bool night,
      required bool selected,
      required IconData icon,
      required String title,
      required String sub,
      required VoidCallback onTap,
      Widget? extra}) {
    final brand = night ? AppColors.brandDark : AppColors.brandLight;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected
                  ? brand
                  : (night ? AppColors.nightLine : AppColors.dayLine)),
          color: selected ? brand.withOpacity(0.08) : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: brand),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(sub,
                      style: TextStyle(
                          fontSize: 12,
                          color: night
                              ? AppColors.nightMuted
                              : AppColors.dayMuted)),
                  if (selected && extra != null) ...[
                    const SizedBox(height: 8),
                    extra,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- helpers ----------------

  BoxDecoration _cardDeco(bool night) => BoxDecoration(
        color: night ? AppColors.nightPanel : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: night ? AppColors.nightLine : AppColors.dayLine),
      );

  String _trimNum(double v) {
    var s = v.toStringAsFixed(2);
    s = s.replaceAll(RegExp(r'0+$'), '');
    s = s.replaceAll(RegExp(r'\.$'), '');
    return s;
  }

  String _qLabel(double g) {
    if (g == -1) return 'Unlimited';
    if (g == 0) return 'Upload off';
    if (g < 1) return '${(g * 1024).round()} MB';
    return '${_trimNum(g)} GB';
  }
}
