import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../utils/format.dart';
import 'app_widgets.dart';

/// Value used by the pool picker for "let the system choose".
const String kPoolAuto = 'auto';

/// Dropdown that lets an admin pick which R2 storage pool a member's files
/// go to. Fetches the assignable pools (kind != 'binding', not read-only)
/// via GET /api/storage when it mounts.
///
/// [value] is 'auto' or a pool id. [onChanged] always reports a non-null
/// selection. [onLoaded] reports the fetched pool list (for confirmation
/// messages); it is not called when the fetch fails.
class PoolDropdown extends StatefulWidget {
  final ApiClient api;
  final String value;
  final ValueChanged<String> onChanged;
  final ValueChanged<List<StoragePool>>? onLoaded;
  const PoolDropdown({
    super.key,
    required this.api,
    required this.value,
    required this.onChanged,
    this.onLoaded,
  });
  @override
  State<PoolDropdown> createState() => _PoolDropdownState();
}

class _PoolDropdownState extends State<PoolDropdown> {
  List<StoragePool>? _pools;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final all = await widget.api.getStorage();
      if (!mounted) return;
      final pools =
          all.where((p) => p.kind != 'binding' && !p.readOnly).toList();
      widget.onLoaded?.call(pools);
      setState(() => _pools = pools);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  String _label(StoragePool p) {
    final use = '${formatBytes(p.used)} / ${formatBytes(p.limit)}';
    final bucket = p.bucket.isNotEmpty ? ' (${p.bucket})' : '';
    final name = p.name.isNotEmpty ? p.name : p.id;
    return '$name$bucket — $use';
  }

  @override
  Widget build(BuildContext context) {
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(
        value: kPoolAuto,
        child: Text('Auto (let the system choose)'),
      ),
    ];
    if (_pools != null) {
      for (final p in _pools!) {
        items.add(DropdownMenuItem(
          value: p.id,
          child: Text(_label(p), overflow: TextOverflow.ellipsis),
        ));
      }
      // The member's current pool may no longer be assignable (e.g. it
      // became read-only). Keep it selectable so the dropdown value
      // always matches one of the items.
      if (widget.value != kPoolAuto &&
          _pools!.every((p) => p.id != widget.value)) {
        items.add(DropdownMenuItem(
          value: widget.value,
          child: Text('Current pool (${widget.value})',
              overflow: TextOverflow.ellipsis),
        ));
      }
    }
    final effective =
        items.any((i) => i.value == widget.value) ? widget.value : kPoolAuto;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<String>(
          value: effective,
          isExpanded: true,
          decoration:
              const InputDecoration(labelText: 'Storage pool (R2)'),
          items: items,
          onChanged: (v) {
            if (v != null) widget.onChanged(v);
          },
        ),
        if (_pools == null && !_failed) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
          const SizedBox(height: 4),
          Text('Loading storage pools…',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
        if (_failed)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Could not load pools — Auto will be used.',
                style: TextStyle(fontSize: 12, color: Colors.red)),
          ),
      ],
    );
  }
}

String _poolDisplayName(List<StoragePool> pools, String id) {
  if (id.isEmpty || id == kPoolAuto) return 'Auto';
  for (final p in pools) {
    if (p.id == id) return p.name.isNotEmpty ? p.name : p.id;
  }
  return id;
}

/// Shows the member quota dialog: quota (GB or unlimited) plus the R2
/// storage-pool picker. Saves via PATCH /api/members/quota, including an
/// explicit pool reset to auto when the admin picks Auto for a member
/// that currently has a pool assigned.
///
/// Returns true when the save succeeded (caller should reload its list).
Future<bool> showMemberQuotaDialog(
    BuildContext context, ApiClient api, TeamMember m) async {
  final quotaCtrl = TextEditingController(
      text: m.quotaGB != null ? m.quotaGB.toString() : '');
  bool unlimited = m.quotaGB == null;
  String poolSel = m.pool.isEmpty ? kPoolAuto : m.pool;
  List<StoragePool> pools = [];
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setDlg) => AlertDialog(
        title: Text('Quota — ${m.username}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Unlimited quota'),
                value: unlimited,
                onChanged: (v) => setDlg(() => unlimited = v ?? true),
              ),
              TextField(
                controller: quotaCtrl,
                enabled: !unlimited,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Quota (GB)', hintText: 'e.g. 20'),
              ),
              const SizedBox(height: 12),
              PoolDropdown(
                api: api,
                value: poolSel,
                onChanged: (v) => setDlg(() => poolSel = v),
                onLoaded: (p) => pools = p,
              ),
            ],
          ),
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
  final quotaText = quotaCtrl.text.trim();
  quotaCtrl.dispose();
  if (ok != true) return false;
  double? quotaGB;
  if (!unlimited) {
    quotaGB = double.tryParse(quotaText);
    if (quotaGB == null || quotaGB <= 0) {
      showMsg(context, 'Enter a valid quota in GB, or tick Unlimited.',
          error: true);
      return false;
    }
  }
  // Pool handling: 'auto' on a member that has a pool assigned must be
  // sent explicitly (''), otherwise the worker keeps the old assignment.
  // An unchanged pool is omitted entirely.
  String? poolToSend;
  var clearPool = false;
  if (poolSel == kPoolAuto) {
    if (m.pool.isNotEmpty) clearPool = true;
  } else if (poolSel != m.pool) {
    poolToSend = poolSel;
  }
  final poolName =
      _poolDisplayName(pools, poolSel == kPoolAuto ? '' : poolSel);
  final saved = await guard(context, () async {
    await api.setMemberQuota(
      username: m.username,
      quotaGB: quotaGB,
      pool: poolToSend,
      clearPool: clearPool,
    );
    return true;
  });
  if (saved != true) return false;
  showMsg(context,
      'Quota for "${m.username}" updated — storage pool: $poolName.');
  return true;
}
