import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../providers/app_state.dart';
import '../utils/format.dart';
import '../utils/images.dart';
import '../widgets/app_widgets.dart';
import '../widgets/diary_book.dart';

/// Private diary as a book, mirroring the web app's 3D diary:
/// cover → tap to open → two-page spread (single page on phones).
/// Tap a page to write/draw/sticker it. Data format is 100% compatible
/// with the web app (same worker endpoints, same JSON shapes).
///
/// Home-screen "New" button hooks in via [DiaryScreen.requestNew]
/// to open today's entry editor.
class DiaryScreen extends StatefulWidget {
  const DiaryScreen({super.key});

  /// Opens today's entry editor.
  static VoidCallback? requestNew;

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

DateTime _clampDate(DateTime d) {
  if (d.isBefore(DateTime(1970))) return DateTime(1970);
  if (d.isAfter(DateTime(2100, 12, 31))) return DateTime(2100, 12, 31);
  return d;
}

class _DiaryScreenState extends State<DiaryScreen> {
  final Map<String, DiaryEntry> _entries = {};
  final Set<int> _yearsLoaded = {};
  final Map<String, int> _yearCounts = {}; // year -> entry count (all years)
  bool _open = false;
  late DateTime _anchor;
  Color _deskColor = diaryDesk;

  late final VoidCallback _requestNewCb;

  @override
  void initState() {
    super.initState();
    _anchor = diaryDateOnly(DateTime.now());
    _requestNewCb = () {
      if (mounted) _jumpTo(DateTime.now(), openEditor: true);
    };
    DiaryScreen.requestNew = _requestNewCb;
    _loadDeskColor();
    _ensureYear(_anchor.year);
  }

  Future<void> _loadDeskColor() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt('diary_desk');
    if (v != null && mounted) setState(() => _deskColor = Color(v));
  }

  int _totalEntries() =>
      _yearCounts.values.fold(0, (a, b) => a + b);

  @override
  void dispose() {
    if (identical(DiaryScreen.requestNew, _requestNewCb)) {
      DiaryScreen.requestNew = null;
    }
    super.dispose();
  }

  Future<void> _ensureYear(int y) async {
    if (_yearsLoaded.contains(y)) return;
    final api = context.read<SessionProvider>().api;
    final res = await guard(context, () => api.getDiary(y));
    if (!mounted) return;
    if (res != null) {
      setState(() {
        _yearsLoaded.add(y);
        _entries.addAll(res.entries);
        _yearCounts.addAll(res.years);
      });
    }
  }

  Future<void> _refresh() async {
    _yearsLoaded.clear();
    _entries.clear();
    _yearCounts.clear();
    setState(() {});
    await _ensureYear(_anchor.year);
    await _ensureYear(_anchor.add(const Duration(days: 1)).year);
  }

  Future<void> _jumpTo(DateTime d, {bool openEditor = false}) async {
    final d0 = diaryDateOnly(_clampDate(d));
    setState(() {
      _anchor = d0;
      _open = true;
    });
    await _ensureYear(d0.year);
    await _ensureYear(d0.add(const Duration(days: 1)).year);
    if (openEditor && mounted) _openEditor(dateKey(d0));
  }

  /// Dates shown in the book. Spread mode pairs an even 0-based day index
  /// with the next day, exactly like the web app (dyAnchor).
  List<DateTime> _visibleDates(bool spread) {
    var a = _anchor;
    if (spread && (diaryDayOfYear(a) - 1).isOdd) {
      a = a.subtract(const Duration(days: 1));
    }
    if (spread) return [a, a.add(const Duration(days: 1))];
    return [a];
  }

  void _flip(int dir, bool spread) {
    _jumpTo(_anchor.add(Duration(days: dir * (spread ? 2 : 1))));
  }

  Future<void> _openEditor(String date) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
          builder: (_) =>
              _DiaryPageEditor(date: date, existing: _entries[date])),
    );
    if (changed == true && mounted) {
      final y = int.tryParse(date.substring(0, 4)) ?? _anchor.year;
      _yearsLoaded.remove(y);
      await _ensureYear(y);
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _anchor,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100, 12, 31),
    );
    if (d != null && mounted) _jumpTo(d);
  }

  /// Table background picker (mirrors web dyBg). Flat colors only,
  /// persisted on-device.
  static const _deskChoices = [
    ('Default', Color(0xFF231709)),
    ('Leather', Color(0xFF4A2112)),
    ('Charcoal', Color(0xFF2A2A2A)),
    ('Slate', Color(0xFF1F2937)),
    ('Navy', Color(0xFF0F172A)),
    ('Maroon', Color(0xFF3B1F1F)),
    ('Forest', Color(0xFF1E3A2A)),
  ];

  Future<void> _pickDeskColor() async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Table er background'),
        content: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final (name, col) in _deskChoices)
              Tooltip(
                message: name,
                child: InkWell(
                  onTap: () => Navigator.pop(c, col),
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: col,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _deskColor.value == col.value
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                        width: _deskColor.value == col.value ? 3 : 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel')),
        ],
      ),
    );
    if (picked != null && mounted) {
      setState(() => _deskColor = picked);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('diary_desk', picked.value);
    }
  }

  /// "Sob entry" — centered frosted modal listing every entry across all
  /// years, grouped by month. Mirrors the web dyEntries modal.
  Future<void> _showEntries() async {
    // Load every year first, like the web app does.
    for (final y in _yearCounts.keys.toList()) {
      final yi = int.tryParse(y);
      if (yi != null) await _ensureYear(yi);
    }
    if (!mounted) return;
    final keys = _entries.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    final picked = await showDialog<String>(
      context: context,
      builder: (c) {
        final months = <String, List<String>>{};
        for (final k in keys) {
          final d = DateTime.parse(k);
          final m =
              '${DateFormat('MMMM').format(d).toUpperCase()} ${d.year}';
          months.putIfAbsent(m, () => []).add(k);
        }
        return Dialog(
          backgroundColor: Colors.white.withOpacity(0.94),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          child: Container(
            constraints: const BoxConstraints(
                maxWidth: 520, maxHeight: 620),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.book_outlined,
                        color: diaryEntryBrown, size: 22),
                    SizedBox(width: 8),
                    Text('Diary entries',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87)),
                  ],
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: keys.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 30),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Ekhono kichu likhen ni',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600)),
                                SizedBox(height: 6),
                                Text(
                                    'Page e click kore likhte shuru korun.',
                                    style:
                                        TextStyle(color: Colors.grey)),
                              ],
                            ),
                          ),
                        )
                      : ListView(
                          shrinkWrap: true,
                          children: [
                            for (final m in months.keys) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    8, 12, 8, 4),
                                child: Text(m,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.2,
                                        color: Colors.grey)),
                              ),
                              for (final k in months[m]!)
                                _entryRow(c, k),
                            ],
                          ],
                        ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(c),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      shape: const StadiumBorder(),
                      elevation: 1,
                    ),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null && mounted) _jumpTo(DateTime.parse(picked));
  }

  Widget _entryRow(BuildContext c, String k) {
    final d = DateTime.parse(k);
    final e = _entries[k]!;
    final moodLabel = e.mood.isEmpty
        ? ''
        : diaryMoods
            .firstWhere((m) => m.$1 == e.mood,
                orElse: () => ('', '', ''))
            .$2;
    final moodEmoji = diaryMoodEmoji(e.mood);
    final p = e.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final String preview;
    if (p.isNotEmpty) {
      preview = p.length > 110 ? '${p.substring(0, 110)}…' : p;
    } else if (e.stickers.isNotEmpty) {
      preview = '🖼️ Picture';
    } else if (e.draw.isNotEmpty) {
      preview = '✒️ Aaka';
    } else {
      preview = '';
    }
    return InkWell(
      onTap: () => Navigator.pop(c, k),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 40,
              child: Text('${d.day}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: 'serif',
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w600,
                      fontSize: 24,
                      color: diaryEntryBrown,
                      height: 1.1)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    e.mood.isEmpty
                        ? DateFormat('EEEE').format(d)
                        : '${DateFormat('EEEE').format(d)} · $moodEmoji $moodLabel',
                    style: const TextStyle(
                        color: Colors.grey, fontSize: 12),
                  ),
                  if (preview.isNotEmpty)
                    Text(preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: 'serif',
                            fontStyle: FontStyle.italic,
                            fontSize: 18,
                            height: 1.25,
                            color: Colors.black87)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final night = context.watch<ThemeProvider>().night;
    return Scaffold(
      body: LayoutBuilder(builder: (ctx, bc) {
        final spread = bc.maxWidth >= 720;
        return Container(
          color: _deskColor,
          child: Column(
            children: [
              _dyBar(night),
              Expanded(
                  child: _open
                      ? _bookView(spread)
                      : _coverView()),
            ],
          ),
        );
      }),
    );
  }

  /// Top bar mirroring the web .dy-bar: title + live entry count,
  /// Private label, Today pill, MM/DD/YYYY date field + picker,
  /// Sob entry, table background, day/night, refresh, close book.
  Widget _dyBar(bool night) {
    final total = _totalEntries();
    return Container(
      color: diaryDeskBar,
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Icon(Icons.book_outlined,
                color: Colors.white70, size: 20),
            const SizedBox(width: 6),
            const Text('My Diary',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            if (total > 0) ...[
              const SizedBox(width: 8),
              Text('$total entry',
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 12)),
            ],
            const SizedBox(width: 18),
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline,
                    size: 14, color: Colors.white54),
                SizedBox(width: 4),
                Text('Private',
                    style: TextStyle(
                        color: Colors.white54, fontSize: 12)),
              ],
            ),
            const SizedBox(width: 6),
            ElevatedButton.icon(
              onPressed: () => _jumpTo(DateTime.now()),
              icon: const Icon(Icons.calendar_today, size: 15),
              label: const Text('Today',
                  style: TextStyle(fontSize: 13)),
              style: ElevatedButton.styleFrom(
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                border:
                    Border.all(color: const Color(0xFF6B5A3E)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                DateFormat('MM/dd/yyyy').format(_anchor),
                style: const TextStyle(
                    color: Color(0xFFF3E3B3), fontSize: 13),
              ),
            ),
            IconButton(
                tooltip: 'Pick date',
                onPressed: _pickDate,
                icon: const Icon(Icons.date_range_outlined,
                    color: Colors.white70, size: 20)),
            IconButton(
                tooltip: 'Sob entry',
                onPressed: _showEntries,
                icon: const Icon(Icons.list_outlined,
                    color: Colors.white70, size: 20)),
            IconButton(
                tooltip:
                    'Table er background (rong / chobi / kapor)',
                onPressed: _pickDeskColor,
                icon: const Icon(Icons.palette_outlined,
                    color: Colors.white70, size: 20)),
            IconButton(
                tooltip: 'Day / Night mode',
                onPressed: () =>
                    context.read<ThemeProvider>().toggle(),
                icon: Icon(
                    night
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                    color: Colors.white70,
                    size: 20)),
            IconButton(
                tooltip: 'Refresh',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_outlined,
                    color: Colors.white70, size: 20)),
            IconButton(
                tooltip: 'Diary bondho',
                onPressed: () =>
                    setState(() => _open = false),
                icon: const Icon(Icons.book_outlined,
                    color: Colors.white70, size: 20)),
          ],
        ),
      ),
    );
  }

  Widget _coverView() {
    final username =
        context.read<SessionProvider>().user?.username ?? '';
    return DiaryBookCover(
      username: username,
      year: DateTime.now().year,
      onOpen: () => _jumpTo(_anchor),
    );
  }

  Widget _bookView(bool spread) {
    final dates = _visibleDates(spread);
    final todayKey = dateKey(DateTime.now());
    final Widget book;
    if (spread) {
      book = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _page(dates[0], todayKey, false)),
          const SizedBox(width: 14),
          Expanded(child: _page(dates[1], todayKey, true)),
        ],
      );
    } else {
      book = _page(dates[0], todayKey, false);
    }
    return GestureDetector(
      onHorizontalDragEnd: (d) {
        if (d.primaryVelocity == null) return;
        if (d.primaryVelocity! < -200) {
          _flip(1, spread);
        } else if (d.primaryVelocity! > 200) {
          _flip(-1, spread);
        }
      },
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                SingleChildScrollView(
                  padding:
                      const EdgeInsets.fromLTRB(44, 8, 44, 16),
                  child: book,
                ),
                Positioned(
                  left: 2,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _navBtn(Icons.chevron_left,
                        'Ager page', () => _flip(-1, spread)),
                  ),
                ),
                Positioned(
                  right: 2,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _navBtn(Icons.chevron_right,
                        'Porer page', () => _flip(1, spread)),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            color: diaryDeskBar,
            padding: const EdgeInsets.symmetric(
                vertical: 8, horizontal: 16),
            child: const Text(
              'Page e click kore likhun / aakun, tarpor word select kore rong, marker, size din.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _page(DateTime d, String todayKey, bool bookmark) {
    final key = dateKey(d);
    return DiaryPage(
      date: d,
      entry: _entries[key],
      isToday: key == todayKey,
      bookmark: bookmark,
      onTap: () => _openEditor(key),
    );
  }

  Widget _navBtn(IconData icon, String label, VoidCallback onTap) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.black54,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(icon, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(
                color: Colors.white54, fontSize: 10)),
      ],
    );
  }
}

// ---------------- page editor ----------------

/// Full-screen editor for one diary date: write (with web-compatible
/// rich-text markup), draw (web-compatible strokes), photo stickers,
/// mood. Saves via PUT /api/diary in the exact web format.
class _DiaryPageEditor extends StatefulWidget {
  final String date; // YYYY-MM-DD
  final DiaryEntry? existing;
  const _DiaryPageEditor({required this.date, this.existing});

  @override
  State<_DiaryPageEditor> createState() => _DiaryPageEditorState();
}

class _DiaryPageEditorState extends State<_DiaryPageEditor> {
  late final TextEditingController _textCtrl;
  late List<DiarySpan> _spans;
  late String _mood;
  late List<DiaryStroke> _strokes;
  late List<DiarySticker> _stickers;
  late String _lastText;
  TextSelection _lastSel = const TextSelection.collapsed(offset: 0);

  String _mode = 'text'; // or 'draw'
  String _tool = 'p';
  String _penColor = '';
  String _markColor = 'yellow';
  String? _selSticker;
  bool _saving = false;
  bool _dirty = false;
  bool _popped = false; // result to report when popping

  DateTime get _date => DateTime.parse(widget.date);
  bool get _isToday => widget.date == dateKey(DateTime.now());
  String get _prettyDate =>
      DateFormat('EEEE, d MMMM yyyy').format(_date);

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e?.html?.isNotEmpty ?? false) {
      final (t, sp) = parseDiaryMarkup(e!.html!);
      _textCtrl = TextEditingController(text: t);
      _spans = sp;
    } else {
      _textCtrl = TextEditingController(text: e?.text ?? '');
      _spans = [];
    }
    _lastText = _textCtrl.text;
    _textCtrl.addListener(_onTextChanged);
    _mood = e?.mood ?? '';
    _strokes = List.of(e?.draw ?? <DiaryStroke>[]);
    _stickers = List.of(e?.stickers ?? <DiarySticker>[]);
  }

  @override
  void dispose() {
    _textCtrl.removeListener(_onTextChanged);
    _textCtrl.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final sel = _textCtrl.selection;
    if (sel.isValid && !sel.isCollapsed) _lastSel = sel;
    final cur = _textCtrl.text;
    if (cur == _lastText) return;
    final prev = _lastText;
    var a = 0;
    while (a < prev.length &&
        a < cur.length &&
        prev.codeUnitAt(a) == cur.codeUnitAt(a)) {
      a++;
    }
    var bp = prev.length, bc = cur.length;
    while (bp > a &&
        bc > a &&
        prev.codeUnitAt(bp - 1) == cur.codeUnitAt(bc - 1)) {
      bp--;
      bc--;
    }
    _spans = diaryShiftOnEdit(_spans, a, bp, bc - a);
    _lastText = cur;
    _dirty = true;
  }

  /// Apply a format attribute to the current (or last) text selection.
  void _applyFormat(String attr, String key) {
    var sel = _textCtrl.selection;
    if (!sel.isValid || sel.isCollapsed) sel = _lastSel;
    final n = _textCtrl.text.length;
    if (!sel.isValid || sel.isCollapsed) {
      showMsg(context, 'Select some text first.');
      return;
    }
    final s = sel.start.clamp(0, n), e = sel.end.clamp(0, n);
    if (s >= e) {
      showMsg(context, 'Select some text first.');
      return;
    }
    setState(() {
      _spans = diarySetAttr(_spans, s, e, attr, key);
      _dirty = true;
    });
  }

  void _clearFormat() {
    var sel = _textCtrl.selection;
    if (!sel.isValid || sel.isCollapsed) sel = _lastSel;
    final n = _textCtrl.text.length;
    if (!sel.isValid || sel.isCollapsed) {
      showMsg(context, 'Select some text first.');
      return;
    }
    final s = sel.start.clamp(0, n), e = sel.end.clamp(0, n);
    if (s >= e) return;
    setState(() {
      _spans = diaryClearRange(_spans, s, e);
      _dirty = true;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final text = _textCtrl.text;
    final html = serializeDiaryMarkup(text, _spans);
    final empty = text.trim().isEmpty &&
        _mood.isEmpty &&
        _strokes.isEmpty &&
        _stickers.isEmpty;
    if (empty) {
      if (widget.existing == null) {
        showMsg(context, 'Nothing to save.');
        return;
      }
      // The server deletes an entry saved empty — confirm first.
      final ok = await confirmDialog(context,
          title: 'Clear entry?',
          message:
              'Removing all text, drawings and photos will delete this diary entry.',
          okLabel: 'Delete entry');
      if (!ok || !mounted) return;
    }
    setState(() => _saving = true);
    final api = context.read<SessionProvider>().api;
    final entry = DiaryEntry(
      date: widget.date,
      text: text,
      mood: _mood,
      at: widget.existing?.at ??
          DateTime.now().millisecondsSinceEpoch,
      html: html.isEmpty ? null : html,
      draw: _strokes,
      stickers: _stickers,
    );
    final deleted = await guard(context, () => api.saveDiaryEntry(entry));
    if (!mounted) return;
    setState(() => _saving = false);
    if (deleted == null) return; // error already shown by guard
    showMsg(context, deleted ? 'Entry deleted.' : 'Entry saved.');
    _dirty = false;
    _popped = true;
    Navigator.pop(context, true);
  }

  Future<void> _deleteEntry() async {
    final ok = await confirmDialog(context,
        title: 'Delete entry?',
        message:
            'Delete the diary entry for $_prettyDate? This cannot be undone.');
    if (!ok || !mounted) return;
    final api = context.read<SessionProvider>().api;
    var done = false;
    await guard(context, () async {
      await api.deleteDiaryEntry(widget.date);
      done = true;
    });
    if (done && mounted) {
      showMsg(context, 'Entry deleted.');
      _dirty = false;
      _popped = true;
      Navigator.pop(context, true);
    }
  }

  Future<void> _addPhoto() async {
    if (_stickers.length >= 20) {
      showMsg(context, 'Max 20 photos per page.', error: true);
      return;
    }
    final api = context.read<SessionProvider>().api;
    final res = await FilePicker.platform
        .pickFiles(type: FileType.image, allowMultiple: true);
    if (res == null || res.files.isEmpty || !mounted) return;
    for (final f in res.files) {
      if (_stickers.length >= 20) {
        if (mounted) {
          showMsg(context, 'Max 20 photos per page.', error: true);
        }
        break;
      }
      String? path = f.path;
      if (path == null && f.bytes != null) {
        final tmp = File(
            '${Directory.systemTemp.path}/diary_${DateTime.now().millisecondsSinceEpoch}_${f.name}');
        await tmp.writeAsBytes(f.bytes!);
        path = tmp.path;
      }
      if (path == null || !mounted) continue;
      // Mirror the web app: shrink client-side so longest side ≤1400px.
      late final File shrunk;
      try {
        shrunk = await shrinkForDiary(path);
      } catch (_) {
        if (mounted) {
          showMsg(context, 'Could not process the image.',
              error: true);
        }
        continue;
      }
      double aspect = 1;
      try {
        final dec = img.decodeImage(await shrunk.readAsBytes());
        if (dec != null && dec.width > 0) {
          aspect = (dec.height / dec.width).clamp(0.2, 5).toDouble();
        }
      } catch (_) {}
      DiaryImage? up;
      final ok = await ProgressDialog.show(context,
          title: 'Uploading photo…',
          task: (prog) async {
            up = await api.uploadDiaryImage(shrunk.path);
          });
      if (!mounted) return;
      if (ok && up != null) {
        // Same defaults as the web app: centered, slight jitter.
        final w = aspect > 1.2 ? 400.0 : 520.0;
        final idx = _stickers.length;
        setState(() {
          _stickers.add(DiarySticker(
            id: up!.id,
            x: 500 - w / 2 + ((idx % 3) - 1) * 40,
            y: 80 + idx * 40,
            w: w,
            a: aspect,
            r: ((idx % 5) - 2) * 2.0,
            k: 'tape',
            url: up!.url,
          ));
          _dirty = true;
        });
        showMsg(context, 'Photo added.');
      }
    }
  }

  void _moveSticker(DiarySticker st, Offset deltaPx, double s) {
    final i = _stickers.indexWhere((x) => x.id == st.id);
    if (i < 0) return;
    setState(() {
      _stickers[i] = DiarySticker(
        id: st.id,
        x: (st.x + deltaPx.dx / s).clamp(-200, 1000).toDouble(),
        y: (st.y + deltaPx.dy / s).clamp(0, 30000).toDouble(),
        w: st.w,
        a: st.a,
        r: st.r,
        k: st.k,
        url: st.url,
      );
      _dirty = true;
    });
  }

  Future<void> _onPopInvoked(bool didPop, Object? result) async {
    if (didPop) return;
    if (!_dirty) {
      if (mounted) Navigator.pop(context, _popped ? true : result);
      return;
    }
    final ok = await confirmDialog(context,
        title: 'Discard changes?',
        message: 'You have unsaved changes on this page.',
        okLabel: 'Discard');
    if (ok && mounted) Navigator.pop(context, _popped ? true : result);
  }

  @override
  Widget build(BuildContext context) {
    final isDraw = _mode == 'draw';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        backgroundColor: diaryDesk,
        appBar: AppBar(
          title: Text(_prettyDate,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            if (widget.existing != null)
              IconButton(
                  tooltip: 'Delete entry',
                  onPressed: _deleteEntry,
                  icon: const Icon(Icons.delete_outline)),
            IconButton(
              tooltip: 'Save',
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2))
                  : const Icon(Icons.check),
            ),
          ],
        ),
        body: Column(
          children: [
            _modeBar(),
            if (!isDraw)
              DiaryFormatToolbar(
                  onApply: _applyFormat, onClear: _clearFormat),
            if (isDraw)
              DiaryDrawToolbar(
                tool: _tool,
                onTool: (t) => setState(() {
                  _tool = t;
                  if (t == 'b' && _markColor.isEmpty) {
                    _markColor = 'yellow';
                  }
                }),
                penColor: _penColor,
                onPenColor: (c) => setState(() => _penColor = c),
                markColor: _markColor,
                onMarkColor: (c) => setState(() => _markColor = c),
                onUndo: _strokes.isEmpty
                    ? null
                    : () => setState(() {
                          _strokes =
                              List.of(_strokes)..removeLast();
                          _dirty = true;
                        }),
                onTextMode: () =>
                    setState(() => _mode = 'text'),
                onSticker: _addPhoto,
              ),
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: _editorPage(),
              ),
            ),
            _bottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _modeBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(
              value: 'text',
              icon: Icon(Icons.text_fields_outlined, size: 16),
              label: Text('Write')),
          ButtonSegment(
              value: 'draw',
              icon: Icon(Icons.draw_outlined, size: 16),
              label: Text('Draw')),
        ],
        selected: {_mode},
        onSelectionChanged: (v) =>
            setState(() => _mode = v.first),
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact),
      ),
    );
  }

  Widget _editorPage() {
    return Container(
      decoration: BoxDecoration(
        color: diaryPaper,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFD8CFB8)),
        boxShadow: const [
          BoxShadow(
              color: Colors.black45,
              blurRadius: 14,
              offset: Offset(0, 6)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                  painter: const LinedPaperPainter()),
            ),
            Column(
              children: [
                DiaryPageHeader(date: _date, mood: _mood),
                Expanded(
                  child: LayoutBuilder(builder: (ctx, bc) {
                    final w = bc.maxWidth;
                    final s = w / 1000.0;
                    final isDraw = _mode == 'draw';
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                                66, 4, 14, 8),
                            child: isDraw
                                ? IgnorePointer(
                                    child: _textCtrl.text.isEmpty
                                        ? const Text('Ekhane likhun…',
                                            style: TextStyle(
                                                fontFamily: 'serif',
                                                fontStyle:
                                                    FontStyle.italic,
                                                color:
                                                    diaryPlaceholder,
                                                fontSize: 17,
                                                height: 1.75))
                                        : RichText(
                                            text: TextSpan(
                                                children:
                                                    buildDiaryTextSpans(
                                                        _textCtrl.text,
                                                        _spans))),
                                  )
                                : TextField(
                                    controller: _textCtrl,
                                    maxLines: null,
                                    expands: true,
                                    textAlignVertical:
                                        TextAlignVertical.top,
                                    style: const TextStyle(
                                        fontFamily: 'serif',
                                        fontSize: 17,
                                        height: 1.75,
                                        color: diaryDefaultInk),
                                    decoration: const InputDecoration(
                                      hintText: 'Ekhane likhun…',
                                      hintStyle: TextStyle(
                                          fontFamily: 'serif',
                                          fontStyle:
                                              FontStyle.italic,
                                          color: diaryPlaceholder),
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      filled: false,
                                    ),
                                    keyboardType:
                                        TextInputType.multiline,
                                  ),
                          ),
                        ),
                        for (final st in _stickers)
                          StickerView(
                            st: st,
                            s: s,
                            selected: _selSticker == st.id,
                            onTap: () => setState(() =>
                                _selSticker =
                                    _selSticker == st.id
                                        ? null
                                        : st.id),
                            onDelete: () => setState(() {
                              _stickers.removeWhere(
                                  (x) => x.id == st.id);
                              _selSticker = null;
                              _dirty = true;
                            }),
                            onDrag: isDraw
                                ? null
                                : (d) =>
                                    _moveSticker(st, d.delta, s),
                          ),
                        Positioned.fill(
                          child: isDraw
                              ? DrawCanvas(
                                  strokes: _strokes,
                                  tool: _tool,
                                  penColor: _penColor,
                                  markColor: _markColor,
                                  onChanged: (v) => setState(() {
                                    _strokes = v;
                                    _dirty = true;
                                  }),
                                )
                              : IgnorePointer(
                                  child: CustomPaint(
                                      painter: DrawingPainter(
                                          strokes: _strokes)),
                                ),
                        ),
                      ],
                    );
                  }),
                ),
                DiaryPageFooter(
                    date: _date, at: widget.existing?.at),
              ],
            ),
            if (_isToday)
              const Positioned(
                  top: 0, right: 26, child: TodayRibbon()),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar() {
    return Container(
      color: diaryDeskBar,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _moodChip('', ''),
                  for (final m in diaryMoods)
                    _moodChip(m.$1, m.$3),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _addPhoto,
            icon: const Icon(Icons.add_a_photo_outlined, size: 18),
            label: const Text('Photo'),
            style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFF3E3B3),
                side: const BorderSide(
                    color: Color(0xFF6B5A3E))),
          ),
        ],
      ),
    );
  }

  Widget _moodChip(String key, String emoji) {
    final sel = _mood == key && key.isNotEmpty;
    final isClear = key.isEmpty;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: () => setState(() {
          _mood = (isClear || _mood == key) ? '' : key;
          _dirty = true;
        }),
        borderRadius: BorderRadius.circular(19),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: sel
                ? diaryGold.withOpacity(0.25)
                : Colors.white10,
            border: Border.all(
                color: sel ? diaryGold : Colors.white24),
          ),
          child: Center(
              child: isClear
                  ? Icon(Icons.close,
                      size: 16,
                      color: _mood.isEmpty
                          ? diaryGold
                          : Colors.white54)
                  : Text(emoji,
                      style:
                          const TextStyle(fontSize: 20))),
        ),
      ),
    );
  }
}
