import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_config.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// Native account dropdown.
///
/// The web version had a z-index bug that made "Zedge 1" unclickable; a real
/// Flutter menu renders in its own overlay, so that class of bug cannot happen.
class AccountSwitcher extends StatelessWidget {
  const AccountSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();

    return PopupMenuButton<ZedgeAccount>(
      tooltip: 'Switch Zedge account',
      position: PopupMenuPosition.under,
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Colors.white.withOpacity(0.22)),
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
                    : (state.error == null ? Zc.ok : Zc.danger),
              ),
            ),
            const SizedBox(width: 9),
            Text(
              state.account.label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more_rounded,
                color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }
}
