import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';

/// Database / record lists screen.
///
/// - List selector (dropdown) showing the record lists visible to the user.
/// - Rows view with per-column cards; tap to edit, long-press for multi-select
///   delete. Add row via [requestNew] / the + button (memberAdd-gated).
/// - Match check: search a value across lists; tap a hit to jump to its row.
/// - Admin "Manage lists": create / edit / delete list, import rows.
class DatabaseScreen extends StatefulWidget {
  const DatabaseScreen({super.key});

  /// Wired by the home shell's "+ New" button / FAB.
  static VoidCallback? requestNew;

  @override
  State<DatabaseScreen> createState() => _DatabaseScreenState();
}

class _DatabaseScreenState extends State<DatabaseScreen> {
  List<RecordList> _lists = [];
  String? _selId;
  Map<String, RecordRow> _rows = {};
  bool _loading = true;
  String? _error;
  bool _loadingRows = false;

  final _checkCtrl = TextEditingController();
  RecordCheckResult? _checkResult;
  bool _checking = false;

  final _rowSearchCtrl = TextEditingController();
  String _rowSearch = '';
  final Set<String> _selected = {};
  String? _highlightRid;

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

  SessionProvider get _session => Provider.of<SessionProvider>(context, listen: false);
  bool get _isAdmin => _session.isAdmin;

  RecordList? get _list {
    final id = _selId;
    if (id == null) return null;
    for (final l in _lists) {
      if (l.id == id) return l;
    }
    return null;
  }

  // ---------------- loading ----------------

  Future<void> _loadLists() async {
    final api = _session.api;
    setState(() {
      _loading = true;
      _error = null;
    });
    final lists = await guard(context, () => api.getRecordLists());
    if (!mounted) return;
    if (lists == null) {
      setState(() {
        _loading = false;
        _error = 'Could not load record lists.';
      });
      return;
    }
    setState(() {
      _lists = lists;
      _loading = false;
      if (lists.isNotEmpty &&
          (_selId == null || !lists.any((l) => l.id == _selId))) {
        _selId = lists.first.id;
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
    final rows = await guard(context, () => _session.api.getRecordRows(id));
    if (!mounted) return;
    setState(() {
      _rows = rows ?? {};
      _loadingRows = false;
    });
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
            listId: list.id, rid: row!.rid, cells: cells);
      } else {
        await _session.api.addRecordRow(
            listId: list.id,
            cells: cells,
            owner: ownerText.isEmpty ? null : ownerText);
      }
    });
    if (ok != null) {
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
    final res = await guard(context, () => _session.api.deleteRecordRows(
        listId: list.id, rids: _selected.toList()));
    if (res != null) {
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
        () => _session.api.checkRecord(listId: _selId, value: value));
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
      final res = await guard(
          context, () => _session.api.createRecordList(spec));
      if (res != null) {
        showMsg(context, 'List created.');
        await _loadLists();
      }
    } else {
      final res = await guard(
          context, () => _session.api.updateRecordList(list.id, spec));
      if (res != null) {
        showMsg(context, 'List updated.');
        await _loadLists();
      }
    }
  }

  Future<void> _deleteList(RecordList list) async {
    final ok = await confirmDialog(context,
        title: 'Delete list',
        message: 'Delete "${list.name}" and all its rows? This cannot be undone.');
    if (!ok) return;
    final res = await guard(context, () => _session.api.deleteRecordList(list.id));
    if (res != null) {
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
              : m..remove('owner')..remove('cells'),
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
        title: 'Importing rows…',
        task: (progress) async {
          await _session.api.importRecordList(list.id, rows);
        });
    if (done) {
      showMsg(context, 'Imported ${rows.length} row(s).');
      await _loadRows();
    }
  }

  // ---------------- build ----------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final night = theme.brightness == Brightness.dark;
    if (_loading) return const LoadingView(label: 'Loading record lists…');
    if (_error != null) return ErrorView(message: _error!, onRetry: _loadLists);
    if (_lists.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const EmptyView(
              icon: Icons.table_chart_outlined,
              message: 'No record lists yet.'),
          const SizedBox(height: 12),
          if (_isAdmin)
            ElevatedButton.icon(
              onPressed: _showListEditor,
              icon: const Icon(Icons.add),
              label: const Text('Create list'),
            ),
        ]),
      );
    }
    final list = _list;
    if (list == null) return const SizedBox.shrink();

    final rows = _filteredRows(list);
    final canAdd = _isAdmin || list.memberAdd;

    return Column(
      children: [
        _buildHeader(theme, night, list),
        _buildCheckCard(theme, night),
        if (_selected.isNotEmpty) _buildSelectionBar(theme, night),
        Expanded(child: _buildRows(theme, night, list, rows, canAdd)),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme, bool night, RecordList list) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _selId,
              decoration: const InputDecoration(
                labelText: 'Record list',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: _lists
                  .map((l) => DropdownMenuItem(
                      value: l.id, child: Text(l.name)))
                  .toList(),
              onChanged: (v) {
                if (v == null || v == _selId) return;
                setState(() {
                  _selId = v;
                  _highlightRid = null;
                });
                _loadRows();
              },
            ),
          ),
          if (_isAdmin) ...[
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Manage lists',
              onSelected: (v) {
                switch (v) {
                  case 'new':
                    _showListEditor();
                    break;
                  case 'edit':
                    _showListEditor(list: list);
                    break;
                  case 'delete':
                    _deleteList(list);
                    break;
                  case 'import':
                    _importRows(list);
                    break;
                }
              },
              itemBuilder: (c) => const [
                PopupMenuItem(
                    value: 'new',
                    child: ListTile(
                        leading: Icon(Icons.add), title: Text('New list'))),
                PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Edit list'))),
                PopupMenuItem(
                    value: 'import',
                    child: ListTile(
                        leading: Icon(Icons.file_upload_outlined),
                        title: Text('Import rows'))),
                PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text('Delete list'))),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCheckCard(ThemeData theme, bool night) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Match check',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: night
                          ? AppColors.nightMuted
                          : AppColors.dayMuted,
                      fontSize: 12)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _checkCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Enter a token, number or ID…',
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      onSubmitted: (_) => _runCheck(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _checking ? null : _runCheck,
                    child: _checking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Check'),
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

  Widget _buildCheckResults(ThemeData theme, bool night) {
    final r = _checkResult!;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              r.matches.isEmpty
                  ? 'No matches for "${r.value}".'
                  : '${r.matches.length} match${r.matches.length == 1 ? '' : 'es'}${r.more ? ' (showing first 100)' : ''}:',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          ...r.matches.map((m) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.search, size: 18),
                title: Text('${m.listName} · ${m.colName}'),
                subtitle: Text(
                    'Owner: ${m.owner.isEmpty ? '—' : m.owner} · ${timeAgo(m.at)}'),
                trailing:
                    m.own ? const Chip(label: Text('yours')) : null,
                onTap: () => _jumpToMatch(m),
              )),
        ],
      ),
    );
  }

  Widget _buildSelectionBar(ThemeData theme, bool night) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
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

  List<RecordRow> _filteredRows(RecordList list) {
    final all = _rows.values.toList()
      ..sort((a, b) => b.at.compareTo(a.at));
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

  Widget _buildRows(ThemeData theme, bool night, RecordList list,
      List<RecordRow> rows, bool canAdd) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _rowSearchCtrl,
            decoration: InputDecoration(
              hintText: 'Search rows…',
              prefixIcon: const Icon(Icons.search, size: 20),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              suffixIcon: _rowSearch.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _rowSearchCtrl.clear();
                        setState(() => _rowSearch = '');
                      })
                  : null,
            ),
            onChanged: (v) => setState(() => _rowSearch = v.trim()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
          child: Row(
            children: [
              Text('${rows.length} row${rows.length == 1 ? '' : 's'}',
                  style: TextStyle(
                      fontSize: 12,
                      color:
                          night ? AppColors.nightMuted : AppColors.dayMuted)),
              if (list.memberAdd)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Chip(
                      label: Text('members can add'),
                      visualDensity: VisualDensity.compact),
                ),
              const Spacer(),
              if (canAdd)
                TextButton.icon(
                  onPressed: () => _showRowDialog(list: list),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add row'),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loadingRows
              ? const LoadingView(label: 'Loading rows…')
              : rows.isEmpty
                  ? const EmptyView(
                      icon: Icons.table_rows_outlined,
                      message: 'No rows yet.')
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: rows.length,
                      itemBuilder: (c, i) =>
                          _rowCard(theme, night, list, rows[i]),
                    ),
        ),
      ],
    );
  }

  Widget _rowCard(
      ThemeData theme, bool night, RecordList list, RecordRow row) {
    final selected = _selected.contains(row.rid);
    final highlighted = _highlightRid == row.rid;
    final title = list.cols.isNotEmpty
        ? (row.cells[list.cols.first.k] ?? '').toString()
        : 'Row';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: selected
          ? theme.colorScheme.primary.withOpacity(0.14)
          : highlighted
              ? AppColors.warn.withOpacity(0.14)
              : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
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
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (selected)
                    Icon(Icons.check_circle,
                        color: theme.colorScheme.primary, size: 20),
                  if (selected) const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        title.isEmpty ? '(empty)' : title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  Chip(
                    label: Text(row.owner.isEmpty ? '—' : row.owner),
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.person_outline, size: 14),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ...list.cols.skip(1).map((c) {
                final v = (row.cells[c.k] ?? '').toString();
                if (v.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text.rich(TextSpan(
                    children: [
                      TextSpan(
                          text: '${c.name}: ',
                          style: TextStyle(
                              color: night
                                  ? AppColors.nightMuted
                                  : AppColors.dayMuted)),
                      TextSpan(text: v),
                    ],
                  )),
                );
              }),
              const SizedBox(height: 4),
              Text('Added ${timeAgo(row.at)}${row.by.isNotEmpty ? ' by ${row.by}' : ''}',
                  style: TextStyle(
                      fontSize: 12,
                      color:
                          night ? AppColors.nightMuted : AppColors.dayMuted)),
            ],
          ),
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
                initialValue: _access,
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
