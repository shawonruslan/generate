import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/notifications.dart';
import '../shell/app_shell.dart';
import '../widgets/common.dart';
import '../widgets/fa.dart';
import '../widgets/responsive.dart';

/// v27 Notification center page (`#notifications`).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // route(): entering the page marks everything read after 1.5 s
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) context.read<AppState>().notifications.markAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.appWatch;
    final p = app.palette;
    final center = app.notifications;
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < Bp.sm;

    return ChangeNotifierProvider<NotificationCenter>.value(
      value: center,
      child: Consumer<NotificationCenter>(builder: (context, n, _) {
        final items = n.filtered;
        final tools = Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Segmented<String>(
              small: true,
              options: const [('all', 'All'), ('ok', 'Success'), ('err', 'Errors'), ('warn', 'Warnings'), ('info', 'Info')],
              value: n.filter,
              onChanged: n.setFilter,
            ),
            ZButton('Mark all read', icon: 'fa-check-double', kind: ZBtnKind.ghost, small: true, onPressed: n.unread == 0 ? null : n.markAll),
            ZButton('Clear', icon: 'fa-broom', kind: ZBtnKind.ghost, small: true, onPressed: n.items.isEmpty
                ? null
                : () async {
                    if (await confirmDialog(context, 'Clear all notifications on this device?', okLabel: 'Clear', danger: true)) n.clear();
                  }),
          ],
        );

        return PageBody(children: [
          GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Flex(
                direction: narrow ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: narrow ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: narrow ? 0 : 1,
                    child: Row(children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(gradient: p.primaryGradient, borderRadius: BorderRadius.circular(p.radiusSm)),
                        alignment: Alignment.center,
                        child: Icon(faIcon('fa-bell'), color: p.onPrimary, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Text('Notifications', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: p.text)),
                            const SizedBox(width: 10),
                            if (n.unread > 0) Pill('${n.unread} unread', small: true, color: p.danger, fg: Colors.white),
                          ]),
                          const SizedBox(height: 2),
                          Text('Live feed of uploads, gate decisions, saves, errors and warnings from this panel. Stored on this device.',
                              style: TextStyle(fontSize: 12.5, color: p.muted)),
                        ]),
                      ),
                    ]),
                  ),
                  if (narrow) const SizedBox(height: 14) else const SizedBox(width: 14),
                  tools,
                ],
              ),
              const SizedBox(height: 18),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  child: EmptyNote(
                    n.items.isEmpty ? 'No notifications yet. Uploads, gate decisions, saves and errors will show up here.' : 'Nothing matches this filter.',
                    icon: 'fa-bell-slash',
                    big: true,
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _NotifRow(items[i]),
                ),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('${items.length} shown · ${n.items.length} stored (max 300) · newest first', style: TextStyle(fontSize: 11.5, color: p.muted)),
              ],
            ]),
          ),
        ]);
      }),
    );
  }
}

class _NotifRow extends StatelessWidget {
  const _NotifRow(this.item);
  final NotifItem item;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final (Color c, String icon, String label) = switch (item.kind) {
      'ok' => (p.ok, 'fa-circle-check', 'Success'),
      'err' => (p.danger, 'fa-circle-xmark', 'Error'),
      'warn' => (p.warn, 'fa-triangle-exclamation', 'Warning'),
      _ => (p.info, 'fa-circle-info', 'Info'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: item.read ? p.tintCard : c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(p.radiusSm),
        border: Border.all(color: item.read ? p.border : c.withValues(alpha: 0.45)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: c.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)),
          alignment: Alignment.center,
          child: Icon(faIcon(icon), color: c, size: 15),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.text, style: TextStyle(fontSize: 13.5, fontWeight: item.read ? FontWeight.w500 : FontWeight.w700, color: p.text)),
            const SizedBox(height: 5),
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Pill(label, small: true, color: c.withValues(alpha: 0.18), fg: c),
              if (item.acc.isNotEmpty) Pill(item.acc.toUpperCase(), small: true, outline: true),
              Text(NotificationCenter.ago(item.ts), style: TextStyle(fontSize: 11.5, color: p.muted)),
              if (!item.read) Container(width: 7, height: 7, decoration: BoxDecoration(color: p.primary, shape: BoxShape.circle)),
            ]),
          ]),
        ),
      ]),
    );
  }
}
