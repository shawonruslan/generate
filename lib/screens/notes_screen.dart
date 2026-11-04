import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../widgets/app_widgets.dart';

/// Private notes, Google-Keep-like. Parity with the web app's Notes view:
/// pinned section, checklist notes, 11 colors, labels, archive view, search.
class NotesScreen extends StatefulWidget {
  /// Set by the shell: opens the editor for a new note.
  static VoidCallback? requestNew;

  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

// 11 note colors, light + dark palettes (lifted from the web app).
const _colorKeys = [
  'default',
  'red',
  'orange',
  'yellow',
  'green',
  'teal',
  'blue',
  'purple',
  'pink',
  'brown',
  'gray'
];
const _lightCols = {
  'default': 0xFFFFFFFF,
  'red': 0xFFFAAFA8,
  'orange': 0xFFF39F76,
  'yellow': 0xFFFFF8B8,
  'green': 0xFFE2F6D3,
  'teal': 0xFFB4DDD3,
  'blue': 0xFFD4E4ED,
  'purple': 0xFFD3BFDB,
  'pink': 0xFFF6E2DD,
  'brown': 0xFFE9E3D4,
  'gray': 0xFFEFEFF1,
};
const _darkCols = {
  'default': 0xFF1E293B,
  'red': 0xFF5C1F2B,
  'orange': 0xFF5E2B14,
  'yellow': 0xFF5A4410,
  'green': 0xFF264D3B,
  'teal': 0xFF0F4C48,
  'blue': 0xFF1F4A5E,
  'purple': 0xFF3F2B55,
  'pink': 0xFF5A2D40,
  'brown': 0xFF4B3F30,
  'gray': 0xFF2B3140,
};

Color _noteBg(String? key, Brightness b) {
  final map = b == Brightness.dark ? _darkCols : _lightCols;
  return Color(map[key] ?? map['default']!);
}

Color _noteFg(String? key, Brightness b) {
  final bg = _noteBg(key, b);
  return ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
      ? Colors.white
      : Colors.black87;
}

class _NotesScreenState extends State<NotesScreen> {
  List<Note> _notes = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  bool _showArchived = false;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    NotesScreen.requestNew = _openNew;
    _load();
  }

  @override
  void dispose() {
    NotesScreen.requestNew = null;
    _searchCtrl.dispose();
    super.dispose();
  }

  ApiClient get _api => context.read<SessionProvider>().api;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final notes = await guard(context, () => _api.getNotes());
    if (!mounted) return;
    setState(() {
      _loading = false;
      _notes = notes ?? [];
      if (notes == null) _error = 'Could not load notes.';
    });
  }

  void _openNew() {
    if (!mounted) return;
    _openEditor(null);
  }

  Future<void> _openEditor(Note? note) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _NoteEditorPage(note: note)),
    );
    if (changed == true && mounted) _load();
  }

  List<Note> get _visible {
    var list = _notes.where((n) => n.archived == _showArchived).toList();
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((n) {
        if (n.title.toLowerCase().contains(q)) return true;
        if (n.body.toLowerCase().contains(q)) return true;
        if (n.labels.any((l) => l.toLowerCase().contains(q))) return true;
        if (n.items?.any((i) => i.t.toLowerCase().contains(q)) ?? false) {
          return true;
        }
        return false;
      }).toList();
    }
    return list;
  }

  Widget _noteCard(Note n) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final bg = _noteBg(n.color, b);
    final fg = _noteFg(n.color, b);
    final items = n.items ?? [];
    final done = items.where((i) => i.d).length;

    Widget? preview;
    if (items.isNotEmpty) {
      final undone = items.where((i) => !i.d).toList();
      final doneList = items.where((i) => i.d).toList();
      final shown = [...undone, ...doneList].take(10).toList();
      preview = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final it in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                      it.d
                          ? Icons.check_box_outlined
                          : Icons.check_box_outline_blank,
                      size: 15,
                      color: fg.withOpacity(0.7)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(it.t,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            color: fg,
                            decoration: it.d
                                ? TextDecoration.lineThrough
                                : null)),
                  ),
                ],
              ),
            ),
          if (items.length > 10)
            Text('+${items.length - 10} more',
                style: TextStyle(fontSize: 12, color: fg.withOpacity(0.7))),
        ],
      );
    } else if (n.body.isNotEmpty) {
      preview = Text(n.body,
          maxLines: 6,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: fg));
    }

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openEditor(n),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: n.title.isEmpty
                      ? const SizedBox.shrink()
                      : Text(n.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.w700, color: fg)),
                ),
                if (n.pinned)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(Icons.push_pin,
                        size: 15, color: fg.withOpacity(0.6)),
                  ),
              ],
            ),
            if (preview != null) ...[
              const SizedBox(height: 6),
              preview,
            ],
            if (items.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('$done/${items.length} done',
                  style: TextStyle(
                      fontSize: 11, color: fg.withOpacity(0.6))),
            ],
            if (n.labels.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final l in n.labels)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: fg.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(l,
                          style:
                              TextStyle(fontSize: 11, color: fg)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Text(label.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: Theme.of(context).colorScheme.primary)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
        actions: [
          IconButton(
            tooltip: _showArchived ? 'Show notes' : 'Archived',
            icon: Icon(_showArchived
                ? Icons.note_outlined
                : Icons.archive_outlined),
            onPressed: () =>
                setState(() => _showArchived = !_showArchived),
          ),
          IconButton(
              tooltip: 'New note',
              icon: const Icon(Icons.add),
              onPressed: _openNew),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search notes…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        }),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        ),
      ),
      body: _loading
          ? const LoadingView(label: 'Loading notes…')
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: Builder(builder: (context) {
                    final vis = _visible;
                    if (vis.isEmpty) {
                      return ListView(
                        physics:
                            const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                              height: MediaQuery.of(context)
                                      .size
                                      .height *
                                  0.6,
                              child: EmptyView(
                                  icon: Icons.note_outlined,
                                  message: _showArchived
                                      ? 'No archived notes.'
                                      : 'No notes yet — tap + to create one.')),
                        ],
                      );
                    }
                    final pinned =
                        _showArchived ? <Note>[] : vis.where((n) => n.pinned).toList();
                    final others =
                        _showArchived ? vis : vis.where((n) => !n.pinned).toList();
                    return LayoutBuilder(builder: (context, cons) {
                      final cols = cons.maxWidth >= 600 ? 2 : 1;
                      Widget grid(List<Note> list) => GridView.builder(
                            shrinkWrap: true,
                            physics:
                                const NeverScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(
                                12, 0, 12, 12),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: cols,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio:
                                  cols == 1 ? 2.6 : 1.15,
                            ),
                            itemCount: list.length,
                            itemBuilder: (_, i) =>
                                _noteCard(list[i]),
                          );
                      return ListView(
                        physics:
                            const AlwaysScrollableScrollPhysics(),
                        children: [
                          if (!_showArchived && pinned.isNotEmpty) ...[
                            _section('Pinned'),
                            grid(pinned),
                          ],
                          if (others.isNotEmpty) ...[
                            if (pinned.isNotEmpty &&
                                !_showArchived)
                              _section('Others'),
                            if (_showArchived)
                              _section('Archived'),
                            grid(others),
                          ],
                          const SizedBox(height: 80),
                        ],
                      );
                    });
                  }),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openNew,
        tooltip: 'New note',
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ---------------- note editor ----------------

/// Full-screen note editor: title, body, checklist, color, pin, archive,
/// labels, save, delete. Auto-deletes an existing note saved empty
/// (web-app behavior).
class _NoteEditorPage extends StatefulWidget {
  final Note? note;
  const _NoteEditorPage({this.note});

  @override
  State<_NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<_NoteEditorPage> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _bodyCtrl;
  late final TextEditingController _labelsCtrl;
  late List<NoteItem> _items;
  late List<FocusNode> _itemFocus;
  late List<TextEditingController> _itemCtrls;
  late String _color;
  late bool _pinned;
  late bool _archived;
  bool _saving = false;
  bool _checklist = false;

  @override
  void initState() {
    super.initState();
    final n = widget.note;
    _titleCtrl = TextEditingController(text: n?.title ?? '');
    _bodyCtrl = TextEditingController(text: n?.body ?? '');
    _labelsCtrl =
        TextEditingController(text: (n?.labels ?? []).join(', '));
    _items = (n?.items ?? []).map((i) => NoteItem(t: i.t, d: i.d)).toList();
    _itemFocus = List.generate(_items.length, (_) => FocusNode());
    _itemCtrls = _items.map((i) => TextEditingController(text: i.t)).toList();
    _color = n?.color ?? 'default';
    _pinned = n?.pinned ?? false;
    _archived = n?.archived ?? false;
    _checklist = _items.isNotEmpty;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _labelsCtrl.dispose();
    for (final f in _itemFocus) {
      f.dispose();
    }
    for (final c in _itemCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  ApiClient get _api => context.read<SessionProvider>().api;

  bool get _isEmpty =>
      _titleCtrl.text.trim().isEmpty &&
      _bodyCtrl.text.trim().isEmpty &&
      _items.every((i) => i.t.trim().isEmpty);

  List<String> _labels() => _labelsCtrl.text
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .take(10)
      .map((s) => s.length > 40 ? s.substring(0, 40) : s)
      .toList();

  void _addItem([String text = '']) {
    setState(() {
      _items.add(NoteItem(t: text, d: false));
      _itemFocus.add(FocusNode());
      _itemCtrls.add(TextEditingController(text: text));
      _checklist = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _itemFocus.last.requestFocus();
    });
  }

  void _removeItem(int i) {
    setState(() {
      _itemFocus[i].dispose();
      _itemFocus.removeAt(i);
      _itemCtrls[i].dispose();
      _itemCtrls.removeAt(i);
      _items.removeAt(i);
      if (_items.isEmpty) _checklist = false;
    });
  }

  void _toggleChecklist() {
    setState(() {
      _checklist = !_checklist;
      if (_checklist && _items.isEmpty) {
        _items.add(NoteItem(t: '', d: false));
        _itemFocus.add(FocusNode());
        _itemCtrls.add(TextEditingController());
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    // Sync checklist text fields back into the item models.
    for (var i = 0; i < _items.length && i < _itemCtrls.length; i++) {
      _items[i].t = _itemCtrls[i].text;
    }
    final id = widget.note?.id;
    if (_isEmpty) {
      // Web-app behavior: auto-delete a note saved empty.
      if (id != null) {
        final ok = await guard(context, () async {
          await _api.deleteNote(id);
          return true;
        });
        if (ok == true && mounted) Navigator.pop(context, true);
      } else if (mounted) {
        Navigator.pop(context, false);
      }
      return;
    }
    setState(() => _saving = true);
    try {
      final note = Note(
        id: id,
        title: _titleCtrl.text.trim().length > 500
            ? _titleCtrl.text.trim().substring(0, 500)
            : _titleCtrl.text.trim(),
        body: _bodyCtrl.text.length > 50000
            ? _bodyCtrl.text.substring(0, 50000)
            : _bodyCtrl.text,
        items: _checklist
            ? _items
                .where((i) => i.t.trim().isNotEmpty)
                .take(500)
                .map((i) => NoteItem(
                    t: i.t.length > 2000
                        ? i.t.substring(0, 2000)
                        : i.t,
                    d: i.d))
                .toList()
            : null,
        color: _color,
        pinned: _pinned,
        archived: _archived,
        labels: _labels(),
      );
      final savedId = await guard(context, () => _api.saveNote(note));
      if (savedId != null && mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final id = widget.note?.id;
    if (id == null) {
      Navigator.pop(context, false);
      return;
    }
    final yes = await confirmDialog(context,
        title: 'Delete note?',
        message: 'This note will be permanently deleted.');
    if (!yes) return;
    final ok = await guard(context, () async {
      await _api.deleteNote(id);
      return true;
    });
    if (ok == true && mounted) Navigator.pop(context, true);
  }

  Widget _checklistEditor(Color fg) {
    return Column(
      children: [
        for (var i = 0; i < _items.length; i++)
          Row(
            children: [
              Checkbox(
                value: _items[i].d,
                onChanged: (v) =>
                    setState(() => _items[i].d = v ?? false),
              ),
              Expanded(
                child: TextField(
                  focusNode: _itemFocus[i],
                  controller: _itemCtrls[i],
                  style: TextStyle(
                      color: fg,
                      decoration: _items[i].d
                          ? TextDecoration.lineThrough
                          : null),
                  decoration: const InputDecoration(
                      hintText: 'List item',
                      border: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero),
                  onChanged: (v) => _items[i].t = v,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _addItem(),
                  onEditingComplete: () {},
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                color: fg.withOpacity(0.6),
                onPressed: () => _removeItem(i),
              ),
            ],
          ),
        TextButton.icon(
          onPressed: () => _addItem(),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add item'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = _noteBg(_color, theme.brightness);
    final fg = _noteFg(_color, theme.brightness);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: fg,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: _pinned ? 'Unpin' : 'Pin',
            icon: Icon(_pinned ? Icons.push_pin : Icons.push_pin_outlined),
            onPressed: () => setState(() => _pinned = !_pinned),
          ),
          IconButton(
            tooltip: _archived ? 'Unarchive' : 'Archive',
            icon: Icon(_archived
                ? Icons.unarchive_outlined
                : Icons.archive_outlined),
            onPressed: () => setState(() => _archived = !_archived),
          ),
          if (widget.note?.id != null)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: fg))
                : Text('Save',
                    style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Color picker.
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _colorKeys.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final k = _colorKeys[i];
                  final c = _noteBg(k, theme.brightness);
                  final selected = k == _color;
                  return GestureDetector(
                    onTap: () => setState(() => _color = k),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? theme.colorScheme.primary
                              : theme.dividerColor,
                          width: selected ? 2.5 : 1,
                        ),
                      ),
                      child: selected
                          ? Icon(Icons.check,
                              size: 16,
                              color: _noteFg(k, theme.brightness))
                          : null,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleCtrl,
              maxLength: 500,
              style: TextStyle(
                  color: fg,
                  fontSize: 20,
                  fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: 'Title',
                hintStyle: TextStyle(color: fg.withOpacity(0.5)),
                border: InputBorder.none,
                filled: false,
                counterText: '',
                contentPadding: EdgeInsets.zero,
              ),
            ),
            TextField(
              controller: _labelsCtrl,
              style: TextStyle(color: fg),
              decoration: InputDecoration(
                hintText: 'Labels (comma-separated)',
                hintStyle: TextStyle(color: fg.withOpacity(0.5)),
                border: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
                prefixIcon: Icon(Icons.label_outline,
                    size: 18, color: fg.withOpacity(0.6)),
              ),
            ),
            const SizedBox(height: 4),
            if (!_checklist)
              TextField(
                controller: _bodyCtrl,
                maxLines: null,
                minLines: 8,
                style: TextStyle(color: fg),
                decoration: InputDecoration(
                  hintText: 'Note…',
                  hintStyle:
                      TextStyle(color: fg.withOpacity(0.5)),
                  border: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                ),
              )
            else
              _checklistEditor(fg),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _toggleChecklist,
              icon: Icon(_checklist
                  ? Icons.notes_outlined
                  : Icons.checklist_outlined),
              label: Text(
                  _checklist ? 'Remove checklist' : 'Add checklist'),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
