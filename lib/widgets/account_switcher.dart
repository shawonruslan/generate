import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_config.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// Account dropdown in the header (Zedge 1 / 2 / 3).
class AccountSwitcher extends StatelessWidget {
  const AccountSwitcher({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();

    return PopupMenuButton<ZedgeAccount>(
      tooltip: 'Switch Zedge account',
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (ZedgeAccount account) {
        if (account.id == state.account.id) return;
        state.connect(account);
      },
      itemBuilder: (BuildContext context) => kAccounts
          .map(
            (ZedgeAccount account) => PopupMenuItem<ZedgeAccount>(
              value: account,
              child: Row(
                children: <Widget>[
                  Icon(
                    account.id == state.account.id
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 16,
                    color: Zc.goldDeep,
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        account.label,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        account.projectId,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Zc.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          )
          .toList(),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.55),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Colors.white.withOpacity(0.8)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: state.connecting
                    ? Zc.warn
                    : (state.error == null ? Zc.okDeep : Zc.danger),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              state.account.label,
              style: const TextStyle(
                color: Zc.ink,
                fontWeight: FontWeight.w900,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more_rounded, color: Zc.ink, size: 18),
          ],
        ),
      ),
    );
  }
}
