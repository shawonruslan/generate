import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';

const _ticketCategories = [
  'general',
  'upload',
  'download',
  'storage',
  'account',
  'bug'
];
const _ticketPriorities = ['low', 'normal', 'high'];

String _cap(String s) =>
    s.isEmpty ? '—' : s[0].toUpperCase() + s.substring(1);

// ---------------------------------------------------------------------------
// Web ticket pill colors (.tst): day / night pairs, flat solid colors.
// ---------------------------------------------------------------------------
Color _tstOpenBg(bool n) => n ? const Color(0xFF0F2E22) : const Color(0xFFDCFCE7);
Color _tstOpenFg(bool n) => n ? const Color(0xFF4ADE80) : const Color(0xFF15803D);
Color _tstHighBg(bool n) => n ? const Color(0xFF3A1D1F) : const Color(0xFFFEE2E2);
Color _tstHighFg(bool n) => n ? const Color(0xFFF87171) : const Color(0xFFB91C1C);
Color _tstNormalBg(bool n) =>
    n ? const Color(0xFF2B3242) : const Color(0xFFE0E7FF);
Color _tstNormalFg(bool n) =>
    n ? const Color(0xFFAEBAFF) : const Color(0xFF4338CA);
Color _tstGrayBg(bool n) =>
    n ? AppColors.nightSide2 : const Color(0xFFF1F5F9);
Color _tstGrayFg(bool n) =>
    n ? AppColors.nightMuted : const Color(0xFF475569);

/// Small rounded status pill, like the web's .tst (11px/700, radius 20px).
Widget _tstPill(String label, Color bg, Color fg, {IconData? icon}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration:
        BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
        ],
        Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
      ],
    ),
  );
}

Widget _statusPill(bool open, bool night) => _tstPill(
    open ? 'OPEN' : 'CLOSED',
    open ? _tstOpenBg(night) : _tstGrayBg(night),
    open ? _tstOpenFg(night) : _tstGrayFg(night));

Widget _priorityPill(String pri, bool night, {bool long = false}) {
  final label = long ? '${pri.toUpperCase()} PRIORITY' : pri.toUpperCase();
  switch (pri) {
    case 'high':
      return _tstPill(label, _tstHighBg(night), _tstHighFg(night));
    case 'normal':
      return _tstPill(label, _tstNormalBg(night), _tstNormalFg(night));
    default:
      return _tstPill(label, _tstGrayBg(night), _tstGrayFg(night));
  }
}

Widget _categoryPill(String cat, bool night) => _tstPill(
    _cap(cat), _tstGrayBg(night), _tstGrayFg(night),
    icon: Icons.people_outline);

/// "Nov 4, 2026, 12:54 AM" — absolute, like the web ticket info line.
String _absoluteDateTime(int ms) {
  if (ms <= 0) return '—';
  return DateFormat('MMM d, yyyy, h:mm a')
      .format(DateTime.fromMillisecondsSinceEpoch(ms));
}

// ---------------------------------------------------------------------------
// Code-aware message text: ```fences``` and `inline` render in monospace.
// ---------------------------------------------------------------------------
List<TextSpan> _inlineCodeSpans(
    String text, TextStyle base, TextStyle mono) {
  final out = <TextSpan>[];
  final inline = RegExp(r'`([^`]+)`');
  var last = 0;
  for (final m in inline.allMatches(text)) {
    if (m.start > last) {
      out.add(TextSpan(text: text.substring(last, m.start), style: base));
    }
    out.add(TextSpan(text: m.group(1), style: mono));
    last = m.end;
  }
  if (last < text.length) {
    out.add(TextSpan(text: text.substring(last), style: base));
  }
  return out;
}

List<TextSpan> _codeSpans(String text, TextStyle base) {
  final mono = base.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Consolas', 'monospace']);
  final out = <TextSpan>[];
  final fence = RegExp(r'```([\s\S]*?)```');
  var last = 0;
  for (final m in fence.allMatches(text)) {
    if (m.start > last) {
      out.addAll(
          _inlineCodeSpans(text.substring(last, m.start), base, mono));
    }
    out.add(TextSpan(text: '\n${m.group(1)!.trim()}\n', style: mono));
    last = m.end;
  }
  if (last < text.length) {
    out.addAll(_inlineCodeSpans(text.substring(last), base, mono));
  }
  return out;
}

class _NewTicketData {
  final String subject;
  final String text;
  final String cat;
  final String pri;
  _NewTicketData(
      {required this.subject,
      required this.text,
      required this.cat,
      required this.pri});
}

/// Support tickets (member) / Tickets (admin).
/// Home-screen "New" button hooks in via [SupportScreen.requestNew].
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  /// Called by the app shell's New button. Member: opens the new-ticket
  /// dialog. Admin: resets the list filter to All.
  static VoidCallback? requestNew;

  /// Optional prefill for the next new-ticket dialog
  /// ({subject, text, cat}) — e.g. a locked file's "ask admin to unlock".
  static Map<String, String>? prefill;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  late final VoidCallback _requestNewCb;
  List<Ticket> _tickets = [];
  bool _loading = true;
  bool _error = false;
  String _filter = 'open'; // open | closed | all

  @override
  void initState() {
    super.initState();
    _requestNewCb = () {
      if (!mounted) return;
      if (context.read<SessionProvider>().isAdmin) {
        setState(() => _filter = 'all');
      } else {
        _openNewTicket();
      }
    };
    SupportScreen.requestNew = _requestNewCb;
    _load();
  }

  @override
  void dispose() {
    if (identical(SupportScreen.requestNew, _requestNewCb)) {
      SupportScreen.requestNew = null;
    }
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    setState(() => _error = false);
    final api = context.read<SessionProvider>().api;
    final res = await guard(context, () => api.getTickets());
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res != null) {
        _tickets = res;
      } else if (_tickets.isEmpty) {
        _error = true;
      }
    });
  }

  List<Ticket> get _filtered {
    final list = _filter == 'all'
        ? _tickets
        : _tickets.where((t) => t.status == _filter).toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  /// Worker-computed per-ticket unread count (tPub.unread).
  bool _isUnread(Ticket t) => t.unread > 0;

  String _preview(Ticket t, String me, bool isAdmin) {
    if (t.msgs.isEmpty) return 'No messages yet';
    final m = t.msgs.last;
    final who = m.by == me ? 'You' : (isAdmin ? m.by : 'Admin');
    var txt = m.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (txt.length > 90) txt = '${txt.substring(0, 90)}…';
    return '$who: $txt';
  }

  Future<void> _openThread(Ticket t) async {
    final session = context.read<SessionProvider>();
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _TicketThreadScreen(
          ticket: t,
          isAdmin: session.isAdmin,
          me: session.user?.username ?? '',
        ),
      ),
    );
    if (changed == true && mounted) _load(silent: true);
  }

  Future<void> _openNewTicket() async {
    final prefill = SupportScreen.prefill;
    SupportScreen.prefill = null;
    final data = await showDialog<_NewTicketData>(
      context: context,
      builder: (c) => _NewTicketDialog(prefill: prefill),
    );
    if (data == null || !mounted) return;
    final api = context.read<SessionProvider>().api;
    final newId = await guard(
        context,
        () => api.createTicket(
            subject: data.subject,
            text: data.text,
            cat: data.cat,
            pri: data.pri));
    if (newId == null || !mounted) return;
    showMsg(context, 'Ticket created.');
    await _load(silent: true);
    if (!mounted) return;
    Ticket? created;
    for (final t in _tickets) {
      if (t.id == newId) {
        created = t;
        break;
      }
    }
    if (created != null) {
      setState(() => _filter = 'open');
      _openThread(created);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final isAdmin = session.isAdmin;
    final theme = Theme.of(context);
    final night = theme.brightness == Brightness.dark;
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;

    final openN = _tickets.where((t) => t.isOpen).length;
    final closedN = _tickets.length - openN;

    Widget body;
    if (_loading && _tickets.isEmpty) {
      body = const LoadingView(label: 'Loading tickets…');
    } else if (_error && _tickets.isEmpty) {
      body =
          ErrorView(message: 'Could not load tickets.', onRetry: () => _load());
    } else {
      final list = _filtered;
      body = RefreshIndicator(
        onRefresh: () => _load(silent: true),
        child: list.isEmpty
            ? ListView(children: [
                SizedBox(
                    height: MediaQuery.of(context).size.height * 0.5,
                    child: EmptyView(
                        icon: Icons.support_agent_outlined,
                        message: _filter == 'all'
                            ? 'No tickets yet.'
                            : 'No ${_filter} tickets.'))
              ])
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                itemCount: list.length,
                itemBuilder: (c, i) => _ticketCard(list[i], isAdmin,
                    session.user?.username ?? '', muted, night),
              ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
              child: Row(
                children: [
                  const Text('Support tickets',
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                      tooltip: 'Refresh',
                      onPressed: () => _load(),
                      icon: const Icon(Icons.refresh_outlined)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
              child: Text('$openN open',
                  style: TextStyle(fontSize: 13, color: muted)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  _filterPill('Open', 'open', openN, night),
                  const SizedBox(width: 8),
                  _filterPill('Closed', 'closed', closedN, night),
                  const SizedBox(width: 8),
                  _filterPill('All', 'all', _tickets.length, night),
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
      floatingActionButton: isAdmin
          ? null
          : FloatingActionButton.extended(
              onPressed: _openNewTicket,
              icon: const Icon(Icons.add),
              label: const Text('New ticket'),
            ),
    );
  }

  /// Web .chip style: active = light-blue pill, blue text; else bordered.
  Widget _filterPill(String label, String value, int count, bool night) {
    final selected = _filter == value;
    final brand = night ? AppColors.brandDark : AppColors.brandLight;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? (night
                  ? const Color(0xFF2B3242)
                  : const Color(0x214A5FD0))
              : (night ? AppColors.nightPanel : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected
                  ? const Color(0xFFC7D2FE)
                  : (night ? AppColors.nightLine : AppColors.dayLine)),
        ),
        child: Text('$label ($count)',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: selected
                    ? brand
                    : (night
                        ? AppColors.nightMuted
                        : AppColors.dayMuted))),
      ),
    );
  }

  Widget _ticketCard(
      Ticket t, bool isAdmin, String me, Color muted, bool night) {
    final unread = _isUnread(t);
    final brand = night ? AppColors.brandDark : AppColors.brandLight;
    final avatars = context.read<SessionProvider>().drive?.avatars;
    final panel = night ? AppColors.nightPanel : Colors.white;
    final line = night ? AppColors.nightLine : AppColors.dayLine;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openThread(t),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: AvatarWidget(
                    url: avatars?[t.user], name: t.user, radius: 20),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(t.subject,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontWeight: unread
                                      ? FontWeight.w800
                                      : FontWeight.w700,
                                  fontSize: 15)),
                        ),
                        if (unread)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: brand,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(_preview(t, me, isAdmin),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: muted)),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _statusPill(t.isOpen, night),
                          _priorityPill(t.pri, night),
                          _categoryPill(t.cat, night),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 2),
                child: Text(formatRelative(t.updatedAt),
                    style: TextStyle(fontSize: 11, color: muted)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// New-ticket dialog (members only).
class _NewTicketDialog extends StatefulWidget {
  final Map<String, String>? prefill;
  const _NewTicketDialog({this.prefill});

  @override
  State<_NewTicketDialog> createState() => _NewTicketDialogState();
}

class _NewTicketDialogState extends State<_NewTicketDialog> {
  late final TextEditingController _subjectCtrl;
  late final TextEditingController _textCtrl;
  late String _cat;
  String _pri = 'normal';

  @override
  void initState() {
    super.initState();
    final p = widget.prefill;
    _subjectCtrl = TextEditingController(text: p?['subject'] ?? '');
    _textCtrl = TextEditingController(text: p?['text'] ?? '');
    final pc = p?['cat'];
    _cat = (pc != null && _ticketCategories.contains(pc)) ? pc : 'general';
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final subject = _subjectCtrl.text.trim();
    final text = _textCtrl.text.trim();
    if (subject.isEmpty || text.isEmpty) {
      showMsg(context, 'Subject and message are required.', error: true);
      return;
    }
    Navigator.pop(
        context,
        _NewTicketData(
            subject: subject, text: text, cat: _cat, pri: _pri));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New ticket'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _subjectCtrl,
                maxLength: 120,
                decoration: const InputDecoration(
                    labelText: 'Subject',
                    hintText: 'Brief summary of the issue'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _cat,
                      decoration:
                          const InputDecoration(labelText: 'Category'),
                      items: _ticketCategories
                          .map((c) => DropdownMenuItem(
                              value: c, child: Text(_cap(c))))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _cat = v ?? 'general'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _pri,
                      decoration:
                          const InputDecoration(labelText: 'Priority'),
                      items: _ticketPriorities
                          .map((p) => DropdownMenuItem(
                              value: p, child: Text(_cap(p))))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _pri = v ?? 'normal'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _textCtrl,
                maxLines: 5,
                maxLength: 3000,
                decoration: const InputDecoration(
                    labelText: 'Message',
                    hintText: 'Describe the issue in detail…',
                    alignLabelWithHint: true),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(onPressed: _submit, child: const Text('Submit')),
      ],
    );
  }
}

/// Thread view for one ticket: messages, reply box, mark solved, delete.
class _TicketThreadScreen extends StatefulWidget {
  final Ticket ticket;
  final bool isAdmin;
  final String me;
  const _TicketThreadScreen(
      {required this.ticket,
      required this.isAdmin,
      required this.me});

  @override
  State<_TicketThreadScreen> createState() => _TicketThreadScreenState();
}

class _TicketThreadScreenState extends State<_TicketThreadScreen> {
  late Ticket _ticket;
  late List<TicketMessage> _msgs;
  final _replyCtrl = TextEditingController();
  bool _sending = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _ticket = widget.ticket;
    _msgs = List.of(widget.ticket.msgs);
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
  }

  @override
  void dispose() {
    _replyCtrl.dispose();
    super.dispose();
  }

  Future<void> _markRead() async {
    final api = context.read<SessionProvider>().api;
    await guard(context, () async {
      await api.markTicketRead(_ticket.id);
      return true;
    });
  }

  Ticket _withStatus(String status) => Ticket(
        id: _ticket.id,
        user: _ticket.user,
        subject: _ticket.subject,
        cat: _ticket.cat,
        pri: _ticket.pri,
        status: status,
        createdAt: _ticket.createdAt,
        updatedAt: _ticket.updatedAt,
        unread: _ticket.unread,
        msgs: _ticket.msgs,
      );

  Future<void> _send() async {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final api = context.read<SessionProvider>().api;
    final ok = await guard(context, () async {
      await api.replyTicket(id: _ticket.id, text: text);
      return true;
    });
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok != true) return;
    setState(() {
      _msgs.add(TicketMessage(
          by: widget.me,
          text: text,
          at: DateTime.now().millisecondsSinceEpoch));
      _replyCtrl.clear();
      if (!_ticket.isOpen) {
        // Server reopens a closed ticket on reply.
        _ticket = _withStatus('open');
        showMsg(context, 'Ticket reopened.');
      }
      _changed = true;
    });
  }

  Future<void> _toggleStatus() async {
    final next = _ticket.isOpen ? 'closed' : 'open';
    final api = context.read<SessionProvider>().api;
    final ok = await guard(context, () async {
      await api.setTicketStatus(id: _ticket.id, status: next);
      return true;
    });
    if (ok != true || !mounted) return;
    setState(() {
      _ticket = _withStatus(next);
      _changed = true;
    });
    showMsg(context, next == 'closed' ? 'Ticket closed.' : 'Ticket reopened.');
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context,
        title: 'Delete ticket?',
        message: 'Delete "${_ticket.subject}" permanently?');
    if (!ok || !mounted) return;
    final api = context.read<SessionProvider>().api;
    final done = await guard(context, () async {
      await api.deleteTicket(_ticket.id);
      return true;
    });
    if (done == true && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final night = theme.brightness == Brightness.dark;
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    final panel = night ? AppColors.nightPanel : Colors.white;
    final line = night ? AppColors.nightLine : AppColors.dayLine;
    final brand = night ? AppColors.brandDark : AppColors.brandLight;
    final danger = night ? AppColors.dangerDark : AppColors.dangerLight;
    final canClose =
        widget.isAdmin || _ticket.user == widget.me; // member: own ticket
    final avatars = context.read<SessionProvider>().drive?.avatars;

    // Report back to the ticket list whether anything changed, so it refreshes.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_changed ? true : result);
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              // Header card: back arrow + avatar + bold title.
              Container(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                padding: const EdgeInsets.fromLTRB(4, 8, 12, 12),
                decoration: BoxDecoration(
                  color: panel,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Back',
                          onPressed: () =>
                              Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.arrow_back_outlined),
                        ),
                        AvatarWidget(
                            url: avatars?[_ticket.user],
                            name: _ticket.user,
                            radius: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(_ticket.subject,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16)),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 0, 0),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _statusPill(_ticket.isOpen, night),
                          _priorityPill(_ticket.pri, night, long: true),
                          _tstPill(
                              '${_cap(_ticket.cat)} · ${_ticket.user} · #${_ticket.id}',
                              _tstGrayBg(night),
                              _tstGrayFg(night)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 0, 0),
                      child: Text(
                          '${_ticket.user} opened this ticket · ${_absoluteDateTime(_ticket.createdAt)}',
                          style:
                              TextStyle(fontSize: 12, color: muted)),
                    ),
                    if (canClose || widget.isAdmin)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 0, 0),
                        child: Row(
                          children: [
                            if (canClose)
                              Expanded(
                                child: SizedBox(
                                  height: 44,
                                  child: ElevatedButton.icon(
                                    onPressed: _toggleStatus,
                                    icon: Icon(
                                        _ticket.isOpen
                                            ? Icons.check
                                            : Icons.replay_outlined,
                                        size: 18),
                                    label: Text(_ticket.isOpen
                                        ? 'Mark as solved'
                                        : 'Reopen'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          const Color(0xFF1B1B1E),
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                              ),
                            if (canClose && widget.isAdmin)
                              const SizedBox(width: 8),
                            if (widget.isAdmin)
                              SizedBox(
                                height: 44,
                                child: ElevatedButton(
                                  onPressed: _delete,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: danger,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                  ),
                                  child:
                                      const Icon(Icons.delete_outline),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  children: [
                    if (!_ticket.isOpen)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.warn.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, size: 18),
                            const SizedBox(width: 8),
                            const Expanded(
                                child: Text(
                                    'This ticket is closed. Replying will reopen it.',
                                    style: TextStyle(fontSize: 13))),
                          ],
                        ),
                      ),
                    ..._msgs.map(_bubble),
                  ],
                ),
              ),
              const Divider(height: 1),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: CallbackShortcuts(
                          bindings: {
                            const SingleActivator(LogicalKeyboardKey.enter,
                                control: true): _send,
                          },
                          child: TextField(
                            controller: _replyCtrl,
                            minLines: 1,
                            maxLines: 5,
                            maxLength: 3000,
                            textInputAction: TextInputAction.newline,
                            decoration: const InputDecoration(
                              hintText:
                                  'Reply likhun… (Ctrl + Enter = send)',
                              counterText: '',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _sending ? null : _send,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: brand,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: _sending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white))
                              : const Icon(Icons.send),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Render message content. Code-like messages (long lines, config patterns)
  /// get a horizontally scrollable monospace block; normal text wraps.
  Widget _messageContent(TicketMessage m, Color fg) {
    final text = m.text;
    final lines = text.split('\n');
    final hasLongLines = lines.any((l) => l.length > 60);
    final looksLikeCode = hasLongLines ||
        text.contains('apiKey') ||
        text.contains('const ') && text.contains('= {') ||
        RegExp(r'```').hasMatch(text);

    if (looksLikeCode) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: fg.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SelectableText(
            text,
            style: TextStyle(
              fontFamily: 'monospace',
              fontFamilyFallback: const ['Menlo', 'Consolas', 'monospace'],
              fontSize: 12.5,
              color: fg,
              height: 1.4,
            ),
          ),
        ),
      );
    }

    return RichText(
        text: TextSpan(
            children: _codeSpans(
                text,
                TextStyle(
                    fontSize: 14,
                    color: fg,
                    height: 1.35))));
  }

  Widget _bubble(TicketMessage m) {
    final theme = Theme.of(context);
    final night = theme.brightness == Brightness.dark;
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    final brand = night ? AppColors.brandDark : AppColors.brandLight;
    final mine = m.by == widget.me;
    final bg = night ? AppColors.nightSide2 : const Color(0xFFF4F2EC);
    final fg = night ? AppColors.nightText : AppColors.dayText;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.88),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14).copyWith(
            topRight: mine ? const Radius.circular(4) : null,
            topLeft: mine ? null : const Radius.circular(4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(m.by,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: brand)),
              ),
            _messageContent(m, fg),
            const SizedBox(height: 4),
            Text(formatRelative(m.at),
                style: TextStyle(fontSize: 10, color: muted)),
          ],
        ),
      ),
    );
  }
}
