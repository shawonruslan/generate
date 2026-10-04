import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../widgets/common.dart';
import '../widgets/fa.dart';

/// `purgeUi` - veil with phase / progress / live line while the verified
/// R2 + Firebase purge runs, then a result card. Returns the PurgeResult (null on error).
Future<PurgeResult?> runPurge(BuildContext context, {required String account, required List<String> ids, String? what}) async {
  final app = context.app;
  final phase = ValueNotifier<PurgePhase?>(null);
  final result = ValueNotifier<PurgeResult?>(null);
  final error = ValueNotifier<String?>(null);
  final t0 = DateTime.now();

  // ignore: unawaited_futures
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _PurgeDialog(total: ids.length, account: account, what: what, phase: phase, result: result, error: error, t0: t0),
  );

  PurgeResult? res;
  try {
    res = await app.repo.deleteItemsById(account, ids, onPhase: (p) => phase.value = p);
    result.value = res;
    app.showToast(res.summary(what), res.kind);
  } catch (e) {
    error.value = e.toString().replaceFirst('Exception: ', '');
    app.showToast('Delete failed: ${error.value}', 'err');
  }
  return res;
}

class _PurgeDialog extends StatelessWidget {
  const _PurgeDialog({required this.total, required this.account, required this.what, required this.phase, required this.result, required this.error, required this.t0});
  final int total;
  final String account;
  final String? what;
  final ValueNotifier<PurgePhase?> phase;
  final ValueNotifier<PurgeResult?> result;
  final ValueNotifier<String?> error;
  final DateTime t0;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: GlassCard(
          padding: const EdgeInsets.all(22),
          child: ValueListenableBuilder<PurgeResult?>(
            valueListenable: result,
            builder: (_, res, __) => ValueListenableBuilder<String?>(
              valueListenable: error,
              builder: (_, err, __) {
                if (err != null) return _errorCard(context, err);
                if (res != null) return _doneCard(context, res);
                return _progress(context);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _progress(BuildContext context) {
    final p = context.pal;
    return ValueListenableBuilder<PurgePhase?>(
      valueListenable: phase,
      builder: (_, ph, __) {
        final text = ph?.text ?? 'Checking all account queues…';
        final det = ph != null && ph.total > 0;
        final ratio = det ? (ph.current / ph.total).clamp(0.0, 1.0).toDouble() : null;
        var eta = '';
        if (det) {
          final el = DateTime.now().difference(t0).inMilliseconds / 1000;
          if (ph.current > 0 && ph.current < ph.total) {
            eta = '~${((ph.total - ph.current) * (el / ph.current)).round().clamp(1, 1 << 30)}s left';
          } else if (ph.current >= ph.total) {
            eta = 'R2 done';
          }
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Fa('fa-trash-alt', size: 18, color: p.danger),
            const SizedBox(width: 10),
            Expanded(child: Text('Deleting $total item(s) from ${account.toUpperCase()}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: p.text))),
          ]),
          const SizedBox(height: 14),
          Text(text, style: TextStyle(color: p.text, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: ratio, minHeight: 10, color: p.primary, backgroundColor: p.tintSoft)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text(det ? '${ph.current} / ${ph.total} R2 files verified deleted' : (ph == null ? 'Preparing' : text), style: TextStyle(fontSize: 12, color: p.muted))),
            Text(eta, style: TextStyle(fontSize: 12, color: p.muted)),
          ]),
          if (ph?.live != null) ...[
            const SizedBox(height: 8),
            Text(ph!.live!, style: TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: p.text), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 14),
          Text('Do not close this window. Every file is removed from R2 first and verified absent, then its queue record is deleted.', style: TextStyle(fontSize: 12, color: p.muted)),
        ]);
      },
    );
  }

  Widget _doneCard(BuildContext context, PurgeResult res) {
    final p = context.pal;
    final ok = res.ok;
    final secs = (DateTime.now().difference(t0).inMilliseconds / 1000).toStringAsFixed(1);
    Widget stat(String n, String label, {bool good = true}) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: (good ? p.ok : p.danger).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              Text(n, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: good ? p.ok : p.danger)),
              Text(label, style: TextStyle(fontSize: 11, color: p.muted), textAlign: TextAlign.center),
            ]),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Fa(ok ? 'fa-check-circle' : 'fa-exclamation-triangle', size: 20, color: ok ? const Color(0xff2b8a3e) : const Color(0xffc92a2a)),
        const SizedBox(width: 10),
        Expanded(child: Text(ok ? 'Deletion complete' : 'Deletion finished with issues', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: p.text))),
      ]),
      const SizedBox(height: 6),
      Text('${what ?? 'items'} · ${secs}s', style: TextStyle(fontSize: 12, color: p.muted)),
      const SizedBox(height: 14),
      Row(children: [
        stat('${res.rows}', 'records removed'),
        const SizedBox(width: 8),
        stat('${res.files}', 'R2 files verified gone'),
        const SizedBox(width: 8),
        stat('${res.retained}', 'kept for retry', good: res.retained == 0 && res.kept == 0),
      ]),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: (ok ? p.ok : p.danger).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            ok
                ? 'All selected files are permanently gone from R2 and Firebase. Zedge-published content stays on Zedge.'
                : 'Kept records are marked failed / Deletion incomplete. Fix the cause, then press Delete again (not Requeue).',
            style: TextStyle(fontSize: 12.5, color: p.text),
          ),
          if (res.corsBlocked)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Network/CORS blocked: the R2 Worker is not deployed with the v19 code — open the Worker URL, it must show deleteProtocol r2-delete-v1.', style: TextStyle(fontSize: 12.5, color: p.text, fontWeight: FontWeight.w700)),
            ),
          if (res.errors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(res.errors.take(3).map((e) => '• $e').join('\n'), style: TextStyle(fontSize: 12, color: p.text)),
            ),
        ]),
      ),
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        if (res.errors.isNotEmpty) ...[_CopyBtn(res), const SizedBox(width: 8)],
        ZButton('Close', onPressed: () => Navigator.of(context).pop()),
      ]),
    ]);
  }

  Widget _errorCard(BuildContext context, String err) {
    final p = context.pal;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Fa('fa-exclamation-triangle', size: 20, color: p.danger),
        const SizedBox(width: 10),
        Expanded(child: Text('Deletion failed', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: p.text))),
      ]),
      const SizedBox(height: 12),
      Text(err, style: TextStyle(color: p.text)),
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [ZButton('Close', onPressed: () => Navigator.of(context).pop())]),
    ]);
  }
}

class _CopyBtn extends StatefulWidget {
  const _CopyBtn(this.res);
  final PurgeResult res;
  @override
  State<_CopyBtn> createState() => _CopyBtnState();
}

class _CopyBtnState extends State<_CopyBtn> {
  bool _copied = false;
  @override
  Widget build(BuildContext context) => ZButton(_copied ? 'Copied' : 'Copy details', kind: ZBtnKind.ghost, onPressed: () async {
        await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(widget.res.toJson())));
        if (mounted) setState(() => _copied = true);
      });
}
