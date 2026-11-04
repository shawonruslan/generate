import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';

/// Admin-only storage overview: total summary card, per-pool cards,
/// and a generic app-settings section (editable string/number/bool values).
class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});
  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  List<StoragePool>? _pools;
  Map<String, dynamic>? _settings;
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
    final settings = pools == null
        ? null
        : await guard(context, () => api.getSettings());
    if (!mounted) return;
    setState(() {
      _pools = pools;
      _settings = settings;
      _loading = false;
      if (pools == null || settings == null) {
        _error = 'Could not load storage info.';
      }
    });
  }

  Future<void> _editSetting(String key, dynamic value) async {
    // Bools are handled by the SwitchListTile; this covers strings/numbers.
    dynamic newValue;
    if (value is num) {
      final text = await promptDialog(context,
          title: 'Edit "$key"',
          initial: value.toString(),
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          okLabel: 'Save');
      if (text == null || !mounted) return;
      final parsed = num.tryParse(text.trim());
      if (parsed == null) {
        showMsg(context, 'Enter a valid number.', error: true);
        return;
      }
      newValue = parsed;
    } else if (value is String) {
      final text = await promptDialog(context,
          title: 'Edit "$key"', initial: value, okLabel: 'Save');
      if (text == null || !mounted) return;
      newValue = text;
    } else {
      showMsg(context, '"$key" is read-only here.', error: true);
      return;
    }
    final ok = await guard(context, () async {
      await _api.updateSettings({key: newValue});
      return true;
    });
    if (!mounted || ok != true) return;
    showMsg(context, '"$key" updated.');
    _load();
  }

  Future<void> _toggleSetting(String key, bool value) async {
    final ok = await guard(context, () async {
      await _api.updateSettings({key: value});
      return true;
    });
    if (!mounted || ok != true) return;
    showMsg(context, '"$key" ${value ? 'enabled' : 'disabled'}.');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    if (!session.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Storage')),
        body: const EmptyView(
            icon: Icons.lock_outline,
            message: 'Storage is for admins only.'),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _load),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingView(label: 'Loading storage…');
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    final pools = _pools ?? [];
    final totalUsed = pools.fold<int>(0, (s, p) => s + p.used);
    final totalLimit = pools.fold<int>(0, (s, p) => s + p.limit);
    final totalFiles = pools.fold<int>(0, (s, p) => s + p.files);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _summaryCard(totalUsed, totalLimit, totalFiles, pools.length),
          const SizedBox(height: 16),
          _sectionTitle('Pools (${pools.length})'),
          const SizedBox(height: 8),
          if (pools.isEmpty)
            const EmptyView(
                icon: Icons.cloud_off_outlined,
                message: 'No storage pools configured.')
          else
            for (final p in pools) ...[
              _poolCard(p),
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 16),
          _sectionTitle('Settings'),
          const SizedBox(height: 8),
          _settingsCard(),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700));

  Widget _summaryCard(int used, int limit, int files, int poolCount) {
    final frac = limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            StorageRing(fraction: frac, size: 72, stroke: 9),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('TOTAL',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8)),
                  const SizedBox(height: 4),
                  Text('${formatBytes(used)} / ${formatBytes(limit)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text('$poolCount pools · $files files',
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _poolCard(StoragePool p) {
    final theme = Theme.of(context);
    final frac = p.limit > 0 ? (p.used / p.limit).clamp(0.0, 1.0) : 0.0;
    final okColor = p.ok ? AppColors.okLight : theme.colorScheme.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(p.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15),
                      overflow: TextOverflow.ellipsis),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: okColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(p.ok ? 'Connected' : 'Error',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: okColor)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Chip(
                    label: Text(p.kind.isEmpty ? 'pool' : p.kind),
                    visualDensity: VisualDensity.compact),
                if (p.bucket.isNotEmpty)
                  Chip(
                      label: Text(p.bucket,
                          overflow: TextOverflow.ellipsis),
                      visualDensity: VisualDensity.compact),
                if (p.readOnly)
                  const Chip(
                      label: Text('Read-only'),
                      visualDensity: VisualDensity.compact),
              ],
            ),
            if (p.error != null && p.error!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(p.error!,
                  style: TextStyle(
                      fontSize: 12, color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 8,
                backgroundColor:
                    theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${formatBytes(p.used)} / ${formatBytes(p.limit)}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                Text('${p.files} files',
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingsCard() {
    final settings = _settings ?? {};
    if (settings.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No app settings found.'),
        ),
      );
    }
    final keys = settings.keys.toList()..sort();
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < keys.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _settingRow(keys[i], settings[keys[i]]),
          ],
        ],
      ),
    );
  }

  Widget _settingRow(String key, dynamic value) {
    if (value is bool) {
      return SwitchListTile(
        title: Text(key),
        value: value,
        onChanged: (v) => _toggleSetting(key, v),
        dense: true,
      );
    }
    final display = value is Map || value is List
        ? '(complex value)'
        : value?.toString() ?? '—';
    return ListTile(
      title: Text(key, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(display,
          style: const TextStyle(fontSize: 12),
          maxLines: 2,
          overflow: TextOverflow.ellipsis),
      trailing: (value is String || value is num)
          ? const Icon(Icons.edit_outlined, size: 18)
          : null,
      onTap: (value is String || value is num)
          ? () => _editSetting(key, value)
          : null,
      dense: true,
    );
  }
}
