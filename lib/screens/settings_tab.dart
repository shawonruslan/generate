import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_config.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final TextEditingController _key = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _key.text = context.read<AppState>().holidays.apiKey;
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final List<String> enabled = state.holidays.nagerCountries;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
      children: <Widget>[
        _Section(
          title: 'HOLIDAY FEEDS',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'India and Bangladesh come from the official Google Calendar '
                'holiday feeds, because the free Nager feed has no Indian data. '
                'Every other country uses Nager, which needs no key. Feeds are '
                'cached for 7 days so the planner also works offline.',
                style: TextStyle(
                    fontSize: 12, color: Zc.inkSoft, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _key,
                decoration: InputDecoration(
                  labelText: 'GOOGLE CALENDAR API KEY',
                  helperText: state.holidays.hasApiKey
                      ? 'A key is active. Restrict it to the Calendar API in Google Cloud.'
                      : 'Optional at build time - paste a key here to enable IN/BD feeds.',
                  suffixIcon: IconButton(
                    tooltip: 'Save key',
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    onPressed: _saving
                        ? null
                        : () async {
                            setState(() => _saving = true);
                            await state.holidays.setApiKey(_key.text);
                            await state.refreshHolidays();
                            if (!mounted) return;
                            setState(() => _saving = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('API key saved and feeds refreshed'),
                              ),
                            );
                          },
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'COUNTRIES SHOWN ON THE CALENDAR',
                style: TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w900,
                  color: Zc.muted,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: kNagerCountries.map((String code) {
                  final bool on = enabled.contains(code);
                  return FilterChip(
                    selected: on,
                    showCheckmark: false,
                    selectedColor: Zc.gold,
                    label: Text(kCountryNames[code] ?? code),
                    onSelected: (bool value) async {
                      final List<String> next = List<String>.of(enabled);
                      if (value) {
                        next.add(code);
                      } else {
                        next.remove(code);
                      }
                      await state.holidays.setNagerCountries(next);
                      await state.refreshHolidays();
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              Text(
                'India and Bangladesh are always on.',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Zc.muted.withOpacity(0.9),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'ACCOUNTS',
          child: Column(
            children: kAccounts
                .map(
                  (ZedgeAccount account) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      account.id == state.account.id
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: Zc.goldDeep,
                    ),
                    title: Text(
                      account.label,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      account.projectId,
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    onTap: () => state.connect(account),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'ABOUT',
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Zedge Studio 1.0.0',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
              ),
              SizedBox(height: 6),
              Text(
                'A fully native Flutter client - no WebView, no embedded HTML. '
                'Every screen is real Flutter UI and the data layer talks to '
                'Firebase Realtime Database over its REST + Server-Sent-Events '
                'API, which behaves identically on Windows and Android.',
                style: TextStyle(
                    fontSize: 12, color: Zc.inkSoft, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Zc.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEBE2CB), width: 1.5),
        boxShadow: kSoftShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              letterSpacing: 1.3,
              fontWeight: FontWeight.w900,
              color: Zc.muted,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
