import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/images.dart';
import '../widgets/app_widgets.dart';

const _moods = [
  ('', 'None', '—'),
  ('happy', 'Happy', '😊'),
  ('calm', 'Calm', '😌'),
  ('love', 'Love', '😍'),
  ('excited', 'Excited', '🤩'),
  ('tired', 'Tired', '😴'),
  ('sad', 'Sad', '😢'),
  ('angry', 'Angry', '😠'),
];

String _moodEmoji(String mood) {
  for (final m in _moods) {
    if (m.$1 == mood) return m.$3;
  }
  return '';
}

/// Private diary (server never exposes another user's diary, not even to
/// admin). Home-screen "New" button hooks in via [DiaryScreen.requestNew]
/// to open today's entry editor.
class DiaryScreen extends StatefulWidget {
  const DiaryScreen({super.key});

  /// Opens today's entry editor.
  static VoidCallback? requestNew;

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  late final VoidCallback _requestNewCb;
  int _year = DateTime.now().year;
  int _month = DateTime.now().month;
  DiaryYear? _diary;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _requestNewCb = () {
      if (mounted) _openEditor(dateKey(DateTime.now()));
    };
    DiaryScreen.requestNew = _requestNewCb;
    _load();
  }

  @override
  void dispose() {
    if (identical(DiaryScreen.requestNew, _requestNewCb)) {
      DiaryScreen.requestNew = null;
    }
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    setState(() => _error = false);
    final api = context.read<SessionProvider>().api;
    final res = await guard(context, () => api.getDiary(_year));
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res != null) {
        _diary = res;
      } else if (_diary == null) {
        _error = true;
      }
    });
  }

  List<int> _yearOptions() {
    final s = <int>{_year, DateTime.now().year};
    final keys = _diary?.years.keys;
    if (keys != null) {
      for (final k in keys) {
        final y = int.tryParse(k);
        if (y != null) s.add(y);
      }
    }
    final l = s.toList()..sort((a, b) => b.compareTo(a));
    return l;
  }

  void _prevMonth() {
    setState(() {
      if (_month == 1) {
        _month = 12;
        _year -= 1;
      } else {
        _month -= 1;
      }
    });
    _load();
  }

  void _nextMonth() {
    setState(() {
      if (_month == 12) {
        _month = 1;
        _year += 1;
      } else {
        _month += 1;
      }
    });
    _load();
  }

  Future<void> _openEditor(String date) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _DiaryEditorScreen(
            date: date, existing: _diary?.entries[date]),
      ),
    );
    if (changed == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final night = theme.brightness == Brightness.dark;
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;

    Widget body;
    if (_loading && _diary == null) {
      body = const LoadingView(label: 'Loading diary…');
    } else if (_error && _diary == null) {
      body = ErrorView(
          message: 'Could not load diary.', onRetry: () => _load());
    } else {
      body = RefreshIndicator(
        onRefresh: () => _load(silent: true),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _monthGrid(muted),
            const SizedBox(height: 16),
            _monthSummary(muted),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.book_outlined, size: 20),
            SizedBox(width: 8),
            Text('Diary'),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 14),
                SizedBox(width: 4),
                Text('Private', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
          IconButton(
              tooltip: 'Refresh',
              onPressed: () => _load(),
              icon: const Icon(Icons.refresh_outlined)),
        ],
      ),
      body: Column(
        children: [
          _headerBar(muted),
          Expanded(child: body),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(dateKey(DateTime.now())),
        icon: const Icon(Icons.edit_outlined),
        label: const Text("Today's entry"),
      ),
    );
  }

  Widget _headerBar(Color muted) {
    final years = _yearOptions();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          DropdownButton<int>(
            value: _year,
            underline: const SizedBox(),
            items: years
                .map((y) => DropdownMenuItem(
                    value: y, child: Text('$y',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 17))))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() => _year = v);
              _load();
            },
          ),
          const Spacer(),
          IconButton(
              tooltip: 'Previous month',
              onPressed: _prevMonth,
              icon: const Icon(Icons.chevron_left)),
          SizedBox(
            width: 110,
            child: Text(
                DateFormat('MMMM').format(DateTime(_year, _month)),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 15)),
          ),
          IconButton(
              tooltip: 'Next month',
              onPressed: _nextMonth,
              icon: const Icon(Icons.chevron_right)),
          TextButton(
            onPressed: () {
              final now = DateTime.now();
              setState(() {
                _year = now.year;
                _month = now.month;
              });
              _load();
            },
            child: const Text('Today'),
          ),
        ],
      ),
    );
  }

  Widget _monthGrid(Color muted) {
    final daysInMonth = DateTime(_year, _month + 1, 0).day;
    final lead = DateTime(_year, _month, 1).weekday - 1; // Monday-first
    final entries = _diary?.entries ?? {};
    final today = dateKey(DateTime.now());
    const wd = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

    final cells = <Widget>[];
    for (final d in wd) {
      cells.add(Center(
          child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(d,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: muted)))));
    }
    for (var i = 0; i < lead; i++) {
      cells.add(const SizedBox());
    }
    for (var d = 1; d <= daysInMonth; d++) {
      final dt = DateTime(_year, _month, d);
      final key = dateKey(dt);
      final entry = entries[key];
      final isToday = key == today;
      cells.add(_dayCell(dt, key, entry, isToday, muted));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          children: cells,
        ),
      ),
    );
  }

  Widget _dayCell(
      DateTime dt, String key, DiaryEntry? entry, bool isToday, Color muted) {
    final mood = entry != null && entry.mood.isNotEmpty
        ? _moodEmoji(entry.mood)
        : '';
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _openEditor(key),
      child: Container(
        decoration: BoxDecoration(
          color: isToday
              ? Theme.of(context).colorScheme.primary.withOpacity(0.15)
              : null,
          borderRadius: BorderRadius.circular(10),
          border: isToday
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary, width: 1.2)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${dt.day}',
                style: TextStyle(
                    fontWeight:
                        isToday ? FontWeight.w800 : FontWeight.w500,
                    fontSize: 14)),
            SizedBox(
              height: 16,
              child: entry == null
                  ? null
                  : mood.isNotEmpty
                      ? Text(mood, style: const TextStyle(fontSize: 12))
                      : Container(
                          margin: const EdgeInsets.only(top: 5),
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _monthSummary(Color muted) {
    final entries = _diary?.entries ?? {};
    final inMonth = entries.keys
        .where((k) => k.startsWith(
            '${_year.toString().padLeft(4, '0')}-${_month.toString().padLeft(2, '0')}'))
        .toList()
      ..sort();
    if (inMonth.isEmpty) {
      return EmptyView(
          icon: Icons.calendar_month_outlined,
          message:
              'No entries in ${DateFormat('MMMM yyyy').format(DateTime(_year, _month))} yet.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text('${inMonth.length} entries',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: muted, fontSize: 13)),
        ),
        ...inMonth.map((k) {
          final e = entries[k]!;
          final mood = e.mood.isNotEmpty ? '${_moodEmoji(e.mood)} ' : '';
          var preview = e.text.replaceAll(RegExp(r'\s+'), ' ').trim();
          if (preview.length > 80) preview = '${preview.substring(0, 80)}…';
          return Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              leading: Text(
                  DateFormat('d').format(DateTime.parse(k)),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16)),
              title: Text('$mood${preview.isEmpty ? '(photos only)' : preview}',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                  '${DateFormat('EEEE').format(DateTime.parse(k))}${e.stickers.isNotEmpty ? ' · ${e.stickers.length} photos' : ''}',
                  style: TextStyle(fontSize: 12, color: muted)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openEditor(k),
            ),
          );
        }),
      ],
    );
  }
}

/// Entry editor: date header, mood chips, text (≤6000), photo stickers,
/// save / delete. Existing html/draw/stk fields round-trip untouched.
class _DiaryEditorScreen extends StatefulWidget {
  final String date; // YYYY-MM-DD
  final DiaryEntry? existing;
  const _DiaryEditorScreen({required this.date, this.existing});

  @override
  State<_DiaryEditorScreen> createState() => _DiaryEditorScreenState();
}

class _DiaryEditorScreenState extends State<_DiaryEditorScreen> {
  late final TextEditingController _textCtrl;
  late String _mood;
  late List<DiarySticker> _stickers;
  String? _html;
  String? _draw;
  bool _saving = false;

  bool get _existed => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _textCtrl = TextEditingController(text: e?.text ?? '');
    _mood = e?.mood ?? '';
    _stickers = List.of(e?.stickers ?? []);
    _html = e?.html;
    _draw = e?.draw;
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  String get _prettyDate {
    try {
      return DateFormat('EEEE, d MMMM yyyy')
          .format(DateTime.parse(widget.date));
    } catch (_) {
      return widget.date;
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final text = _textCtrl.text;
    final empty = text.trim().isEmpty && _stickers.isEmpty;
    if (empty) {
      if (!_existed) {
        showMsg(context, 'Nothing to save.');
        return;
      }
      // Server deletes an entry saved empty — confirm before clearing.
      final ok = await confirmDialog(context,
          title: 'Clear entry?',
          message:
              'Removing all text and photos will delete this diary entry.',
          okLabel: 'Delete entry');
      if (!ok) return;
    }
    setState(() => _saving = true);
    final api = context.read<SessionProvider>().api;
    final entry = DiaryEntry(
      date: widget.date,
      text: text,
      mood: _mood,
      at: widget.existing?.at ?? 0,
      html: _html,
      draw: _draw,
      stickers: _stickers,
    );
    final deleted = await guard(context, () => api.saveDiaryEntry(entry));
    if (!mounted) return;
    setState(() => _saving = false);
    if (deleted == null) return; // error already shown by guard
    showMsg(context, deleted ? 'Entry deleted.' : 'Entry saved.');
    Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context,
        title: 'Delete entry?',
        message: 'Delete the diary entry for $_prettyDate? '
            'This cannot be undone.');
    if (!ok || !mounted) return;
    final api = context.read<SessionProvider>().api;
    var done = false;
    await guard(context, () async {
      await api.deleteDiaryEntry(widget.date);
      done = true;
    });
    if (done && mounted) {
      showMsg(context, 'Entry deleted.');
      Navigator.pop(context, true);
    }
  }

  Future<void> _addPhoto() async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.image, allowMultiple: false);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    String? path = f.path;
    if (path == null) {
      final bytes = f.bytes;
      if (bytes == null) {
        if (mounted) {
          showMsg(context, 'Could not read the image.', error: true);
        }
        return;
      }
      final tmp = File(
          '${Directory.systemTemp.path}/diary_${DateTime.now().millisecondsSinceEpoch}_${f.name}');
      await tmp.writeAsBytes(bytes);
      path = tmp.path;
    }
    final pickedPath = path;
    // Mirror the web app: shrink client-side so the longest side is ≤1400px.
    late final String localPath;
    try {
      localPath = (await shrinkForDiary(pickedPath)).path;
    } catch (_) {
      if (mounted) showMsg(context, 'Could not process the image.', error: true);
      return;
    }
    DiaryImage? img;
    final ok = await ProgressDialog.show(context,
        title: 'Uploading photo…',
        task: (prog) async {
          img = await context
              .read<SessionProvider>()
              .api
              .uploadDiaryImage(localPath);
        });
    if (!mounted) return;
    if (ok && img != null) {
      setState(() {
        _stickers.add(DiarySticker(
            id: img!.id, x: 0, y: 0, w: 120, a: 1, r: 0, url: img!.url));
      });
      showMsg(context, 'Photo added.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final night = theme.brightness == Brightness.dark;
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;

    return Scaffold(
      appBar: AppBar(
        title: Text(_prettyDate,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_existed)
            IconButton(
                tooltip: 'Delete entry',
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline)),
          IconButton(
            tooltip: 'Save',
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Mood',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: muted, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _moods
                .map((m) => ChoiceChip(
                      label: Text('${m.$3} ${m.$2}'),
                      selected: _mood == m.$1,
                      onSelected: (_) =>
                          setState(() => _mood = m.$1),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),
          Text('Entry',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: muted, fontSize: 13)),
          const SizedBox(height: 8),
          TextField(
            controller: _textCtrl,
            minLines: 8,
            maxLines: null,
            maxLength: 6000,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              hintText: 'Write about your day…',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Photos',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: muted,
                      fontSize: 13)),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _addPhoto,
                icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                label: const Text('Add photo'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_stickers.isEmpty)
            Text('No photos yet.',
                style: TextStyle(fontSize: 13, color: muted)),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _stickers
                .asMap()
                .entries
                .map((e) => _stickerTile(e.key, e.value))
                .toList(),
          ),
          const SizedBox(height: 80),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _save,
        icon: const Icon(Icons.save_outlined),
        label: const Text('Save'),
      ),
    );
  }

  Widget _stickerTile(int index, DiarySticker s) {
    final url = s.url;
    return Stack(
      children: [
        Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: Theme.of(context).dividerColor, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: url != null && url.isNotEmpty
              ? Image.network(url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image_outlined)))
              : const Center(child: Icon(Icons.image_outlined)),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: GestureDetector(
            onTap: () => setState(() => _stickers.removeAt(index)),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
