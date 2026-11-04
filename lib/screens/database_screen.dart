import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';

/// Database / record lists screen — mirrors the web app's Database view.
///
/// - Page header: "Database" + gray "N lists", blue "+ New list" (admin).
/// - Match check card: pale icon tile, description, input + list-scope
///   dropdown + blue Check button.
/// - List tabs: active = light-blue pill + count.
/// - Active list card: title, purple permission pills, "N row · updated …",
///   toolbar (search, Match/duplicate chip, Add row, import/export/edit/delete
///   icon buttons), data table (Member, columns, Match, Added, actions).
class DatabaseScreen extends StatefulWidget {
  const DatabaseScreen({super.key});

  /// Wired by the home shell's "+ New" button / FAB.
  static VoidCallback? requestNew;

  @override
  State<DatabaseScreen> createState() => _DatabaseScreenState();
}

/// Extra list fields the worker sends (access / count / updatedAt / desc)
/// that RecordList doesn't parse — captured from the raw JSON.
class _ListMeta {
  final String access; // all | own | admin
  final int? count;
  final int updatedAt;
  final String desc;
  _ListMeta(
      {required this.access,
      this.count,
      required this.updatedAt,
      required this.desc});
}

/// Server-computed duplicate info per row (worker: rowDups).
class _DupInfo {
  final String col;
  final int n;
  final List<String> withOwners;
  _DupInfo({required this.col, required this.n, required this.withOwners});
}

class _DatabaseScreenState extends State<DatabaseScreen> {
  List<RecordList> _lists = [];
  Map<String, _ListMeta> _meta = {};
  String? _selId;
  Map<String, RecordRow> _rows = {};
  Map<String, List<_DupInfo>> _dup = {};
  bool _loading = true;
  String? _error;
  bool _loadingRows = false;
  bool _dupOnly = false;

  final _checkCtrl = TextEditingController();
  String? _checkScope; // null = all lists ("Sob list e")
  RecordCheckResult? _checkResult;
  bool _checking = false;

  final _rowSearchCtrl = TextEditingController();
  String _rowSearch = '';
  final Set<String> _selected = {};
  String? _highlightRid;

  /// Web access-level map (RC_ACC): label + icon.
  static const _accLabels = {
    'all': 'Sobai sob row dekhe',
    'own': 'Member nijer row dekhe',
    'admin': 'Shudhu admin',
  };
  static const _accIcons = {
    'all': Icons.visibility_outlined,
    'own': Icons.lock_person_outlined,
    'admin': Icons.shield_outlined,
  };

  @override
  void initState() {
    super.initState();
    DatabaseScreen.requestNew = _onNew;
    _loadLists();
  }

  @override
  void dispose() {
    DatabaseScreen.requestNew = null;
    _checkCtrl.dispose();
    _rowSearchCtrl.dispose();
    super.dispose();
  }

  SessionProvider get _session =>
      Provider.of<SessionProvider>(context, listen: false);
  bool get _isAdmin => _session.isAdmin;

  RecordList? get _list {
    final id = _selId;
    if (id == null) return null;
    for (final l in _lists) {
      if (l.id == id) return l;
    }
    return null;
  }

  /// Raw GET with the session's bearer token, converting transport errors
  /// into the app's ApiException / UnauthorizedException so guard() works.
  Future<Response<dynamic>> _rawGet(
      String path, [Map<String, dynamic>? query]) async {
    final api = _session.api;
    try {
      return await Dio().get('${api.baseUrl}$path',
          queryParameters: query,
          options: Options(
              headers: {'Authorization': 'Bearer ${api.token ?? ''}'}));
    } on DioException catch (e) {
      final s = e.response?.statusCode ?? 0;
      if (s == 401) throw UnauthorizedException();
      final d = e.response?.data;
      var msg = 'Request failed ($s)';
      if (d is Map) {
        final m = d['error'] ?? d['message'];
        if (m != null) msg = m.toString();
      } else if (d is String && d.isNotEmpty) {
        msg = d.length > 200 ? d.substring(0, 200) : d;
      }
      throw ApiException(s, msg);
    }
  }

  // ---------------- loading ----------------

  Future<void> _loadLists() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await guard(context, () async {
      final r = await _rawGet('/api/records');
      final d = r.data;
      final arr = d is List
          ? d
          : ((d as Map<String, dynamic>?)?['lists'] as List? ?? []);
      final lists = <RecordList>[];
      final meta = <String, _ListMeta>{};
      for (final e in arr) {
        final m = Map<String, dynamic>.from(e as Map);
        lists.add(RecordList.fromJson(m));
        meta[m['id'].toString()] = _ListMeta(
          access: (m['access'] ?? 'all').toString(),
          count: (m['count'] as num?)?.toInt(),
          updatedAt: (m['updatedAt'] as num?)?.toInt() ?? 0,
          desc: (m['desc'] ?? '').toString(),
        );
      }
      return (lists, meta);
    });
    if (!mounted) return;
    if (res == null) {
      setState(() {
        _loading = false;
        _error = 'Could not load record lists.';
      });
      return;
    }
    setState(() {
      _lists = res.$1;
      _meta = res.$2;
      _loading = false;
      if (_lists.isNotEmpty &&
          (_selId == null || !_lists.any((l) => l.id == _selId))) {
        _selId = _lists.first.id;
      }
    });
    if (_selId != null) await _loadRows();
  }

  Future<void> _loadRows() async {
    final id = _selId;
    if (id == null) return;
    setState(() {
      _loadingRows = true;
      _selected.clear();
    });
    final res = await guard(context, () async {
      final r = await _rawGet('/api/records/rows', {'id': id});
      final m = Map<String, dynamic>.from(r.data as Map);
      final rows = <String, RecordRow>{};
      final dup = <String, List<_DupInfo>>{};
      for (final e in ((m['rows'] as List?) ?? [])) {
        final rm = Map<String, dynamic>.from(e as Map);
        final row = RecordRow.fromJsonMap(rm);
        rows[row.rid] = row;
        final dl = <_DupInfo>[];
        for (final dd in ((rm['dup'] as List?) ?? [])) {
          final dm = Map<String, dynamic>.from(dd as Map);
          dl.add(_DupInfo(
            col: (dm['col'] ?? '').toString(),
            n: (dm['n'] as num?)?.toInt() ?? 0,
            withOwners:
                ((dm['with'] as List?) ?? []).map((x) => x.toString()).toList(),
          ));
        }
        dup[row.rid] = dl;
      }
      _ListMeta? lm;
      if (m['list'] is Map) {
        final jm = Map<String, dynamic>.from(m['list'] as Map);
        lm = _ListMeta(
          access: (jm['access'] ?? 'all').toString(),
          count: (jm['count'] as num?)?.toInt(),
          updatedAt: (jm['updatedAt'] as num?)?.toInt() ?? 0,
          desc: (jm['desc'] ?? '').toString(),
        );
      }
      return (rows, dup, lm);
    });
    if (!mounted) return;
    setState(() {
      _rows = res?.$1 ?? {};
      _dup = res?.$2 ?? {};
      if (res?.$3 != null && id == _selId) _meta[id] = res!.$3!;
      _loadingRows = false;
    });
  }

  void _openList(String id) {
    if (id == _selId) return;
    setState(() {
      _selId = id;
      _highlightRid = null;
      _dupOnly = false;
      _rowSearch = '';
      _rowSearchCtrl.clear();
    });
    _loadRows();
  }

  // ---------------- "new" flow ----------------

  void _onNew() {
    if (_isAdmin && _lists.isEmpty) {
      _showListEditor();
      return;
    }
    final list = _list;
    if (list == null) return;
    if (!_isAdmin && !list.memberAdd) {
      showMsg(context, 'Adding rows is disabled for this list.');
      return;
    }
    _showRowDialog(list: list);
  }

  // ---------------- row add / edit ----------------

  Future<void> _showRowDialog({required RecordList list, RecordRow? row}) async {
    final isEdit = row != null;
    final ctrls = <String, TextEditingController>{
      for (final c in list.cols)
        c.k: TextEditingController(
            text: (row?.cells[c.k] ?? '').toString()),
    };
    final ownerCtrl =
        TextEditingController(text: _isAdmin && !isEdit ? '' : (row?.owner ?? ''));
    final res = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(isEdit ? 'Edit row' : 'Add row'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isAdmin && !isEdit)
                  TextField(
                    controller: ownerCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Owner (optional — blank = you)',
                      hintText: 'member username',
                    ),
                  ),
                if (_isAdmin && !isEdit) const SizedBox(height: 8),
                for (final c in list.cols)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: ctrls[c.k],
                      maxLength: 300,
                      decoration: InputDecoration(
                        labelText: c.name,
                        hintText: c.k,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(isEdit ? 'Save' : 'Add')),
        ],
      ),
    );
    // Capture field values BEFORE disposing the controllers.
    final cells = <String, dynamic>{
      for (final c in list.cols) c.k: ctrls[c.k]!.text,
    };
    final ownerText = ownerCtrl.text.trim();
    for (final x in ctrls.values) {
      x.dispose();
    }
    ownerCtrl.dispose();
    if (res != true) return;

    final ok = await guard(context, () async {
      if (isEdit) {
        await _session.api.updateRecordRow(
            listId: list.id, rid: row.rid, cells: cells);
      } else {
        await _session.api.addRecordRow(
            listId: list.id,
            cells: cells,
            owner: ownerText.isEmpty ? null : ownerText);
      }
      return true;
    });
    if (ok == true) {
      showMsg(context, isEdit ? 'Row updated.' : 'Row added.');
      await _loadRows();
    }
  }

  Future<void> _deleteSelected() async {
    final list = _list;
    if (list == null || _selected.isEmpty) return;
    final ok = await confirmDialog(context,
        title: 'Delete rows',
        message: 'Delete ${_selected.length} selected row(s)?');
    if (!ok) return;
    final res = await guard(context, () async {
      await _session.api.deleteRecordRows(
          listId: list.id, rids: _selected.toList());
      return true;
    });
    if (res == true) {
      showMsg(context, 'Deleted.');
      await _loadRows();
    }
  }

  Future<void> _deleteRow(RecordList list, RecordRow row) async {
    final ok = await confirmDialog(context,
        title: 'Delete row', message: 'Delete this row?');
    if (!ok) return;
    final res = await guard(context, () async {
      await _session.api.deleteRecordRows(listId: list.id, rids: [row.rid]);
      return true;
    });
    if (res == true) {
      showMsg(context, 'Deleted.');
      await _loadRows();
    }
  }

  // ---------------- match check ----------------

  Future<void> _runCheck() async {
    final value = _checkCtrl.text.trim();
    if (value.length < 2) {
      showMsg(context, 'Enter at least 2 characters.', error: true);
      return;
    }
    setState(() {
      _checking = true;
      _checkResult = null;
    });
    final res = await guard(context,
        () => _session.api.checkRecord(listId: _checkScope, value: value));
    if (!mounted) return;
    setState(() {
      _checking = false;
      _checkResult = res;
    });
  }

  void _jumpToMatch(RecordCheckMatch m) {
    setState(() {
      _selId = m.list;
      _highlightRid = m.rid;
      _checkResult = null;
      _checkCtrl.clear();
    });
    _loadRows();
  }

  // ---------------- admin: manage lists ----------------

  Future<void> _showListEditor({RecordList? list}) async {
    final spec = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (c) => _ListEditorDialog(existing: list),
    );
    if (spec == null) return;
    if (list == null) {
      final res =
          await guard(context, () => _session.api.createRecordList(spec));
      if (res != null) {
        showMsg(context, 'List created.');
        await _loadLists();
      }
    } else {
      final res = await guard(context, () async {
        await _session.api.updateRecordList(list.id, spec);
        return true;
      });
      if (res == true) {
        showMsg(context, 'List updated.');
        await _loadLists();
      }
    }
  }

  Future<void> _deleteList(RecordList list) async {
    final ok = await confirmDialog(context,
        title: 'Delete list',
        message:
            'Delete "${list.name}" and all its rows? This cannot be undone.');
    if (!ok) return;
    final res = await guard(context, () async {
      await _session.api.deleteRecordList(list.id);
      return true;
    });
    if (res == true) {
      showMsg(context, 'List deleted.');
      setState(() => _selId = null);
      await _loadLists();
    }
  }

  Future<void> _importRows(RecordList list) async {
    final text = await promptDialog(context,
        title: 'Import rows',
        hint: 'Paste a JSON array: [{"owner": "...", "cells": {...}}, ...]',
        okLabel: 'Import',
        maxLines: 8);
    if (text == null || text.trim().isEmpty) return;
    List<Map<String, dynamic>> rows;
    try {
      final decoded = jsonDecode(text.trim());
      if (decoded is! List) throw const FormatException('not a list');
      rows = decoded.map<Map<String, dynamic>>((e) {
        final m = Map<String, dynamic>.from(e as Map);
        final cells = m['cells'];
        return {
          if (m['owner'] != null) 'owner': m['owner'].toString(),
          'cells': cells is Map
              ? Map<String, dynamic>.from(cells)
              : m
                ..remove('owner')
                ..remove('cells'),
        };
      }).toList();
    } catch (e) {
      showMsg(context, 'Invalid JSON: $e', error: true);
      return;
    }
    if (rows.isEmpty) {
      showMsg(context, 'No rows to import.', error: true);
      return;
    }
    final done = await ProgressDialog.show(context,
        title: 'Importing rows…', task: (progress) async {
      await _session.api.importRecordList(list.id, rows);
    });
    if (done) {
      showMsg(context, 'Imported ${rows.length} row(s).');
      await _loadRows();
    }
  }

  Future<void> _exportCsv(RecordList list, List<RecordRow> rows) async {
    final sb = StringBuffer();
    sb.writeln(['owner', ...list.cols.map((c) => c.name)].map(_csvCell).join(','));
    for (final r in rows) {
      sb.writeln([
        r.owner,
        ...list.cols.map((c) => (r.cells[c.k] ?? '').toString())
      ].map(_csvCell).join(','));
    }
    await Clipboard.setData(ClipboardData(text: sb.toString()));
    if (mounted) {
      showMsg(context, 'CSV copied to clipboard (${rows.length} rows).');
    }
  }

  String _csvCell(String v) {
    if (v.contains(RegExp(r'[",\n]'))) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  // ---------------- build ----------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final night = theme.brightness == Brightness.dark;
    if (_loading) return const LoadingView(label: 'Loading record lists…');
    if (_error != null) return ErrorView(message: _error!, onRetry: _loadLists);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pageHeader(theme, night),
        _buildCheckCard(theme, night),
        if (_lists.isNotEmpty) _listTabs(theme, night),
        if (_lists.isEmpty)
          Expanded(child: _emptyLists(theme, night))
        else
          Expanded(child: _listCard(theme, night)),
      ],
    );
  }

  Widget _pageHeader(ThemeData theme, bool night) {
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: [
          const Text('Database',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(width: 10),
          Text(
              _lists.isEmpty
                  ? ''
                  : '${_lists.length} list${_lists.length == 1 ? '' : 's'}',
              style: TextStyle(color: muted, fontSize: 13)),
          const Spacer(),
          if (_isAdmin)
            ElevatedButton.icon(
              onPressed: () => _showListEditor(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New list'),
            ),
        ],
      ),
    );
  }

  // ---------------- match check card ----------------

  Widget _buildCheckCard(ThemeData theme, bool night) {
    final brand = night ? AppColors.brandDark : AppColors.brandLight;
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: brand.withOpacity(0.13),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(Icons.manage_search, color: brand, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Match check',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          'Token / number / ID likhun — kon list e, kar data r sathe match kore dekhabe (boro/choto hater okkhor, space, - _ . / ignore kore)',
                          style: TextStyle(fontSize: 12.5, color: muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _checkCtrl,
                      maxLength: 300,
                      decoration: const InputDecoration(
                        hintText: 'e.g. AB-1234',
                        counterText: '',
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      onSubmitted: (_) => _runCheck(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 168,
                    child: DropdownButtonFormField<String?>(
                      value: _checkScope,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('Sob list e')),
                        ..._lists.map((l) => DropdownMenuItem<String?>(
                            value: l.id, child: Text(l.name))),
                      ],
                      onChanged: (v) =>
                          setState(() => _checkScope = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _checking ? null : _runCheck,
                    icon: _checking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.search, size: 18),
                    label: const Text('Check'),
                  ),
                ],
              ),
              if (_checkResult != null) _buildCheckResults(theme, night),
            ],
          ),
        ),
      ),
    );
  }

  Widget _msgBanner(ThemeData theme, bool night, IconData icon, String text,
      Color bg, Color fg) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 9),
          Expanded(
              child: Text(text,
                  style: TextStyle(fontSize: 13.5, color: fg))),
        ],
      ),
    );
  }

  Widget _buildCheckResults(ThemeData theme, bool night) {
    final r = _checkResult!;
    final okBg = night ? const Color(0xFF0F2E22) : const Color(0xFFDCFCE7);
    final okFg = night ? const Color(0xFF86EFAC) : const Color(0xFF166534);
    final warnBg = night ? const Color(0xFF3A2A0B) : const Color(0xFFFEF3C7);
    final warnFg = night ? const Color(0xFFFCD34D) : const Color(0xFF92400E);
    if (r.matches.isEmpty) {
      return _msgBanner(theme, night, Icons.check_circle_outline,
          '“${r.value}” kono list e nai — match nei.', okBg, okFg);
    }
    final owners =
        r.matches.map((m) => m.owner).where((o) => o.isNotEmpty).toSet();
    final avatars = _session.drive?.avatars ?? {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _msgBanner(
            theme,
            night,
            Icons.warning_amber_outlined,
            '${r.matches.length}${r.more ? '+' : ''} ta match pawa geche'
            '${owners.isNotEmpty ? ' — ${owners.join(', ')} er data er sathe' : ''}',
            warnBg,
            warnFg),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: r.matches.map((m) {
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _jumpToMatch(m),
              child: Container(
                width: 250,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: night
                          ? AppColors.nightLine
                          : AppColors.dayLine),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (m.owner.isNotEmpty)
                          AvatarWidget(
                              url: avatars[m.owner],
                              name: m.owner,
                              radius: 11)
                        else
                          const Icon(Icons.database_outlined, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                              m.owner.isNotEmpty ? m.owner : '(kono member na)',
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        if (m.own)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: night
                                  ? const Color(0xFF3B1D5A)
                                  : const Color(0xFFF3E8FF),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text('Apnar',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: night
                                        ? const Color(0xFFD8B4FE)
                                        : const Color(0xFF7E22CE))),
                          ),
                        const SizedBox(width: 6),
                        Text(formatRelative(m.at),
                            style: TextStyle(
                                fontSize: 11,
                                color: night
                                    ? AppColors.nightMuted
                                    : AppColors.dayMuted)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text.rich(TextSpan(children: [
                      TextSpan(
                          text: m.listName,
                          style:
                              const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(
                          text: ' · ${m.colName}',
                          style: TextStyle(
                              color: night
                                  ? AppColors.nightMuted
                                  : AppColors.dayMuted)),
                    ])),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ---------------- list tabs ----------------

  Widget _listTabs(ThemeData theme, bool night) {
    final brand = night ? AppColors.brandDark : AppColors.brandLight;
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    final line = night ? AppColors.nightLine : AppColors.dayLine;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _lists.map((l) {
          final active = l.id == _selId;
          final meta = _meta[l.id];
          final accKey = meta?.access ?? 'all';
          return InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _openList(l.id),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: active ? brand.withOpacity(0.13) : Colors.transparent,
                border: Border.all(
                    color: active ? const Color(0xFFC7D2FE) : line),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_accIcons[accKey] ?? Icons.visibility_outlined,
                      size: 14, color: active ? brand : muted),
                  const SizedBox(width: 6),
                  Text(l.name,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: active ? brand : null)),
                  if (meta?.count != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(
                        color: active
                            ? (night
                                ? AppColors.nightPanel
                                : Colors.white)
                            : (night
                                ? AppColors.nightSide2
                                : const Color(0xFFF4F2ED)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('${meta!.count}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: muted)),
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _emptyLists(ThemeData theme, bool night) {
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const EmptyView(
              icon: Icons.table_chart_outlined, message: 'Kono list nai'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _isAdmin
                  ? 'Notun list banan — e.g. "Token list": column Token, Phone. Tarpor member der row add / import korun.'
                  : 'Admin ekhono kono list share kore ni.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 13),
            ),
          ),
          if (_isAdmin) ...[
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: () => _showListEditor(),
              icon: const Icon(Icons.add),
              label: const Text('New list'),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------- active list card ----------------

  Widget _listCard(ThemeData theme, bool night) {
    final list = _list;
    if (list == null) return const SizedBox.shrink();
    final meta = _meta[list.id];
    final rows = _filteredRows(list);
    final canAdd = _isAdmin || list.memberAdd;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Card(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _listTitleBar(theme, night, list, meta),
            _toolbarRow(theme, night, list, canAdd, rows),
            if (_selected.isNotEmpty) _buildSelectionBar(theme, night),
            Divider(
                height: 1,
                color: night ? AppColors.nightLine : AppColors.dayLine),
            Expanded(
              child: _loadingRows
                  ? const LoadingView(label: 'Loading rows…')
                  : _dataTable(theme, night, list, rows),
            ),
          ],
        ),
      ),
    );
  }

  Widget _permPill(
      ThemeData theme, bool night, IconData icon, String label) {
    final bg = night ? const Color(0xFF3B1D5A) : const Color(0xFFF3E8FF);
    final fg = night ? const Color(0xFFD8B4FE) : const Color(0xFF7E22CE);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(label,
              style:
                  TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }

  Widget _listTitleBar(
      ThemeData theme, bool night, RecordList list, _ListMeta? meta) {
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    final accKey = meta?.access ?? 'all';
    final totalRows = _rows.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(list.name,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _permPill(theme, night, _accIcons[accKey]!,
                  _accLabels[accKey] ?? accKey),
              if (list.memberAdd)
                _permPill(theme, night, Icons.edit_outlined,
                    'Member add korte pare'),
              Text(
                '$totalRows row · updated ${formatRelative(meta?.updatedAt ?? 0)}',
                style: TextStyle(fontSize: 12.5, color: muted),
              ),
            ],
          ),
          if ((meta?.desc ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(meta!.desc,
                  style: TextStyle(fontSize: 13, color: muted)),
            ),
        ],
      ),
    );
  }

  Widget _toolbarRow(ThemeData theme, bool night, RecordList list, bool canAdd,
      List<RecordRow> rows) {
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    final brand = night ? AppColors.brandDark : AppColors.brandLight;
    final dupN =
        _rows.values.where((r) => (_dup[r.rid]?.isNotEmpty ?? false)).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            width: 200,
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: night ? AppColors.nightSide2 : const Color(0xFFF4F2ED),
              border: Border.all(
                  color: night ? AppColors.nightLine : AppColors.dayLine),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.filter_list, size: 18, color: muted),
                const SizedBox(width: 7),
                Expanded(
                  child: TextField(
                    controller: _rowSearchCtrl,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Ei list e khujun…',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (v) =>
                        setState(() => _rowSearch = v.trim()),
                  ),
                ),
                if (_rowSearch.isNotEmpty)
                  InkWell(
                    onTap: () {
                      _rowSearchCtrl.clear();
                      setState(() => _rowSearch = '');
                    },
                    child: Icon(Icons.clear, size: 16, color: muted),
                  ),
              ],
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => setState(() => _dupOnly = !_dupOnly),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: _dupOnly ? brand.withOpacity(0.13) : Colors.transparent,
                border: Border.all(
                    color: _dupOnly
                        ? const Color(0xFFC7D2FE)
                        : (night
                            ? AppColors.nightLine
                            : AppColors.dayLine)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.copy_outlined,
                      size: 14, color: _dupOnly ? brand : muted),
                  const SizedBox(width: 6),
                  const Text('Match / duplicate',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(
                      color: dupN > 0
                          ? const Color(0xFFFDE68A)
                          : (night
                              ? AppColors.nightSide2
                              : const Color(0xFFF4F2ED)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$dupN',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: dupN > 0
                                ? const Color(0xFF92400E)
                                : muted)),
                  ),
                ],
              ),
            ),
          ),
          if (canAdd)
            ElevatedButton.icon(
              onPressed: () => _showRowDialog(list: list),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add row'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                textStyle: const TextStyle(fontSize: 13),
              ),
            ),
          if (_isAdmin) ...[
            IconButton(
              tooltip: 'Import CSV',
              icon: const Icon(Icons.file_upload_outlined, size: 20),
              onPressed: () => _importRows(list),
            ),
            IconButton(
              tooltip: 'Export',
              icon: const Icon(Icons.file_download_outlined, size: 20),
              onPressed: () => _exportCsv(list, _rows.values.toList()),
            ),
            IconButton(
              tooltip: 'Edit list',
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _showListEditor(list: list),
            ),
            IconButton(
              tooltip: 'Delete list',
              icon: Icon(Icons.delete_outline,
                  size: 20, color: theme.colorScheme.error),
              onPressed: () => _deleteList(list),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSelectionBar(ThemeData theme, bool night) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
              child: Text('${_selected.length} selected',
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          TextButton(
              onPressed: () => setState(_selected.clear),
              child: const Text('Clear')),
          ElevatedButton.icon(
            onPressed: _deleteSelected,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Delete'),
            style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.error),
          ),
        ],
      ),
    );
  }

  // ---------------- data table ----------------

  List<RecordRow> _filteredRows(RecordList list) {
    var all = _rows.values.toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    if (_dupOnly) {
      all = all
          .where((r) => (_dup[r.rid]?.isNotEmpty ?? false))
          .toList();
    }
    if (_rowSearch.isEmpty) return all;
    final q = _rowSearch.toLowerCase();
    return all.where((r) {
      if (r.owner.toLowerCase().contains(q)) return true;
      for (final c in list.cols) {
        if ((r.cells[c.k] ?? '').toString().toLowerCase().contains(q)) {
          return true;
        }
      }
      return false;
    }).toList();
  }

  Widget _dataTable(ThemeData theme, bool night, RecordList list,
      List<RecordRow> rows) {
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    if (rows.isEmpty) {
      final msg = _rowSearch.isNotEmpty
          ? 'Kichu pawa jay ni'
          : _dupOnly
              ? 'Kono match / duplicate nai'
              : 'Ei list e kono row nai';
      return EmptyView(
          icon: _rowSearch.isNotEmpty || _dupOnly
              ? Icons.search_outlined
              : Icons.table_rows_outlined,
          message: msg);
    }
    final showOwner = _isAdmin || (_meta[list.id]?.access == 'all');
    final avatars = _session.drive?.avatars ?? {};
    const ownerW = 168.0, colW = 150.0, matchW = 132.0, addedW = 108.0, actW = 84.0;
    final totalW = (showOwner ? ownerW : 0) +
        list.cols.length * colW +
        matchW +
        addedW +
        actW +
        32;
    final screenW = MediaQuery.of(context).size.width;
    return Scrollbar(
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints:
                BoxConstraints(minWidth: totalW > screenW ? totalW : screenW - 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _tableHead(theme, night, list, showOwner, ownerW, colW, matchW,
                    addedW, actW),
                for (final r in rows.take(1000))
                  _tableRow(theme, night, list, r, showOwner, avatars, ownerW,
                      colW, matchW, addedW, actW),
                if (rows.length > 1000)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                        'Prothom 1000 ta dekhano hocche (${rows.length}) — filter use korun',
                        style: TextStyle(fontSize: 12, color: muted)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _th(String label, double w, {Widget? trailing}) {
    return SizedBox(
      width: w,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.04 * 12,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.nightMuted
                          : AppColors.dayMuted)),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 4),
              trailing,
            ],
          ],
        ),
      ),
    );
  }

  Widget _tableHead(
      ThemeData theme,
      bool night,
      RecordList list,
      bool showOwner,
      double ownerW,
      double colW,
      double matchW,
      double addedW,
      double actW) {
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    return Container(
      color: night ? AppColors.nightSide2 : const Color(0xFFF4F2ED),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          if (showOwner) _th('MEMBER', ownerW),
          for (final c in list.cols)
            _th(c.name.toUpperCase(), colW,
                trailing: c.match
                    ? null
                    : Tooltip(
                        message: 'Match check off',
                        child: Icon(Icons.visibility_off_outlined,
                            size: 13, color: muted))),
          _th('MATCH', matchW),
          _th('ADDED', addedW),
          SizedBox(width: actW),
        ],
      ),
    );
  }

  Widget _matchPill(ThemeData theme, bool night, RecordRow row) {
    final dups = _dup[row.rid] ?? [];
    if (dups.isEmpty) {
      final bg = night ? const Color(0xFF0F2E22) : const Color(0xFFDCFCE7);
      final fg = night ? const Color(0xFF86EFAC) : const Color(0xFF166534);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check, size: 13, color: fg),
            const SizedBox(width: 4),
            Text('Unique',
                style:
                    TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
          ],
        ),
      );
    }
    final bg = night ? const Color(0xFF3A2A0B) : const Color(0xFFFEF3C7);
    final fg = night ? const Color(0xFFFCD34D) : const Color(0xFF92400E);
    final total = dups.fold<int>(0, (a, d) => a + d.n);
    final withNames =
        dups.expand((d) => d.withOwners).toSet().take(2).join(', ');
    return Tooltip(
      message: dups
          .map((d) =>
              '${_colName(row, d.col)}: aro ${d.n} ta row${d.withOwners.isNotEmpty ? ' — ${d.withOwners.join(', ')}' : ''}')
          .join('\n'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, size: 13, color: fg),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                  '$total match${withNames.isNotEmpty ? ' · $withNames' : ''}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
            ),
          ],
        ),
      ),
    );
  }

  String _colName(RecordRow row, String k) {
    final list = _list;
    if (list == null) return k;
    for (final c in list.cols) {
      if (c.k == k) return c.name;
    }
    return k;
  }

  Widget _tableRow(
      ThemeData theme,
      bool night,
      RecordList list,
      RecordRow row,
      bool showOwner,
      Map<String, String> avatars,
      double ownerW,
      double colW,
      double matchW,
      double addedW,
      double actW) {
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    final brand = night ? AppColors.brandDark : AppColors.brandLight;
    final selected = _selected.contains(row.rid);
    final highlighted = _highlightRid == row.rid;
    final dups = _dup[row.rid] ?? [];
    final dupCols = dups.map((d) => d.col).toSet();
    final line2 = night ? AppColors.nightLine2 : const Color(0xFFEDEAE2);
    return InkWell(
      onTap: () {
        if (_selected.isNotEmpty) {
          setState(() {
            if (selected) {
              _selected.remove(row.rid);
            } else {
              _selected.add(row.rid);
            }
          });
        } else {
          _showRowDialog(list: list, row: row);
        }
      },
      onLongPress: () => setState(() {
        if (selected) {
          _selected.remove(row.rid);
        } else {
          _selected.add(row.rid);
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? brand.withOpacity(0.14)
              : highlighted
                  ? AppColors.warn.withOpacity(0.14)
                  : dups.isNotEmpty
                      ? const Color(0xFFF59E0B).withOpacity(0.06)
                      : null,
          border: Border(bottom: BorderSide(color: line2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (showOwner)
              SizedBox(
                width: ownerW,
                child: row.owner.isEmpty
                    ? Text('—',
                        style: TextStyle(fontSize: 13, color: muted))
                    : Row(
                        children: [
                          AvatarWidget(
                              url: avatars[row.owner],
                              name: row.owner,
                              radius: 12),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(row.owner,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500)),
                          ),
                        ],
                      ),
              ),
            for (final c in list.cols)
              SizedBox(
                width: colW,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    (row.cells[c.k] ?? '').toString().isEmpty
                        ? '—'
                        : (row.cells[c.k] ?? '').toString(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: dupCols.contains(c.k)
                          ? (night
                              ? const Color(0xFFFBBF24)
                              : const Color(0xFFB45309))
                          : null,
                      fontWeight: dupCols.contains(c.k)
                          ? FontWeight.w600
                          : null,
                    ),
                  ),
                ),
              ),
            SizedBox(width: matchW, child: _matchPill(theme, night, row)),
            SizedBox(
              width: addedW,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(formatRelative(row.at),
                      style: TextStyle(fontSize: 12, color: muted)),
                  if (row.by.isNotEmpty && row.by != row.owner)
                    Text('by ${row.by}',
                        style: TextStyle(fontSize: 11, color: muted)),
                ],
              ),
            ),
            SizedBox(
              width: actW,
              child: row.canEdit
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: 'Edit',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 32, minHeight: 32),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () =>
                              _showRowDialog(list: list, row: row),
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 32, minHeight: 32),
                          icon: Icon(Icons.delete_outline,
                              size: 18, color: theme.colorScheme.error),
                          onPressed: () => _deleteRow(list, row),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Admin dialog for creating / editing a record list: name, columns
/// (key auto-derived from name, match toggle), access level, memberAdd.
class _ListEditorDialog extends StatefulWidget {
  final RecordList? existing;
  const _ListEditorDialog({this.existing});

  @override
  State<_ListEditorDialog> createState() => _ListEditorDialogState();
}

class _ListEditorDialogState extends State<_ListEditorDialog> {
  late final TextEditingController _nameCtrl;
  late String _access;
  late bool _memberAdd;
  final List<_ColDraft> _cols = [];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _access = 'all';
    _memberAdd = e?.memberAdd ?? false;
    if (e != null) {
      for (final c in e.cols) {
        _cols.add(_ColDraft(
            key: c.k,
            name: TextEditingController(text: c.name),
            match: c.match));
      }
    } else {
      _cols.add(_ColDraft(
          key: 'col1',
          name: TextEditingController(text: 'Name'),
          match: true));
      _cols.add(_ColDraft(
          key: 'col2',
          name: TextEditingController(text: 'Value'),
          match: false));
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    for (final c in _cols) {
      c.name.dispose();
    }
    super.dispose();
  }

  String _slug(String s) {
    var k = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    k = k.replaceAll(RegExp(r'^_+|_+$'), '');
    return k.isEmpty ? 'col' : k;
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      showMsg(context, 'List name is required.', error: true);
      return;
    }
    if (_cols.isEmpty) {
      showMsg(context, 'Add at least one column.', error: true);
      return;
    }
    final seen = <String>{};
    final cols = <Map<String, dynamic>>[];
    for (var i = 0; i < _cols.length; i++) {
      final d = _cols[i];
      final colName = d.name.text.trim();
      if (colName.isEmpty) {
        showMsg(context, 'Column ${i + 1} needs a name.', error: true);
        return;
      }
      var k = d.key.isNotEmpty ? d.key : _slug(colName);
      if (seen.contains(k)) k = '${k}_${i + 1}';
      seen.add(k);
      cols.add({'k': k, 'name': colName, 'match': d.match});
    }
    if (cols.length > 12) {
      showMsg(context, 'A list can have at most 12 columns.', error: true);
      return;
    }
    Navigator.pop(context, {
      'name': name,
      'cols': cols,
      'access': _access,
      'memberAdd': _memberAdd,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'New list' : 'Edit list'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'List name'),
              ),
              const SizedBox(height: 12),
              const Text('Columns',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              ..._cols.asMap().entries.map((e) {
                final i = e.key;
                final d = e.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: d.name,
                          decoration: InputDecoration(
                              labelText: 'Column ${i + 1}',
                              hintText: d.key),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('Match'),
                      Switch(
                        value: d.match,
                        onChanged: (v) =>
                            setState(() => _cols[i].match = v),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline,
                            size: 20),
                        tooltip: 'Remove column',
                        onPressed: () =>
                            setState(() => _cols.removeAt(i)),
                      ),
                    ],
                  ),
                );
              }),
              TextButton.icon(
                onPressed: () => setState(() => _cols.add(_ColDraft(
                    key: 'col${_cols.length + 1}',
                    name: TextEditingController(),
                    match: false))),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add column'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _access,
                decoration:
                    const InputDecoration(labelText: 'Access level'),
                items: const [
                  DropdownMenuItem(
                      value: 'all', child: Text('All members see all rows')),
                  DropdownMenuItem(
                      value: 'own',
                      child: Text('Members see only their own rows')),
                  DropdownMenuItem(
                      value: 'admin', child: Text('Admin only')),
                ],
                onChanged: (v) =>
                    setState(() => _access = v ?? 'all'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Members can add rows'),
                value: _memberAdd,
                onChanged: (v) =>
                    setState(() => _memberAdd = v ?? false),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _ColDraft {
  String key;
  TextEditingController name;
  bool match;
  _ColDraft({required this.key, required this.name, required this.match});
}
