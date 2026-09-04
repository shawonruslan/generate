import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_config.dart';
import '../models/queue_item.dart';
import '../services/time_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/phone_preview.dart';
import '../widgets/stat_card.dart';
import '../widgets/ui.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final TextEditingController _apiKey = TextEditingController();
  bool _seeded = false;
  bool _busy = false;
  bool _keyVisible = false;

  @override
  void dispose() {
    _apiKey.dispose();
    super.dispose();
  }

  Future<void> _saveKey(AppState state) async {
    setState(() => _busy = true);
    await state.holidays.setApiKey(_apiKey.text.trim());
    await state.refreshHolidays();
    if (!mounted) return;
    setState(() => _busy = false);
    showSnack(context, 'Calendar key saved - holidays reloaded');
  }

  Future<void> _toggleRegion(AppState state, String region, bool on) async {
    final List<String> regions = List<String>.from(state.holidays.enabledRegions);
    if (on) {
      if (!regions.contains(region)) regions.add(region);
    } else {
      regions.remove(region);
    }
    await state.holidays.setRegions(regions, state.holidays.googleEnabled);
    await state.refreshHolidays();
  }

  Future<void> _toggleGoogle(AppState state, bool on) async {
    await state.holidays.setRegions(List<String>.from(state.holidays.enabledRegions), on);
    await state.refreshHolidays();
  }

  Future<void> _clearHolidayCache(AppState state) async {
    final bool ok = await confirmDialog(
      context,
      title: 'Clear holiday cache?',
      message: 'Cached Nager / Google Calendar feeds are removed and fetched again.',
      confirmLabel: 'Clear',
    );
    if (!ok) return;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    int n = 0;
    for (final String k in prefs.getKeys().toList()) {
      if (k.startsWith('feed_')) {
        await prefs.remove(k);
        n++;
      }
    }
    await state.refreshHolidays();
    if (mounted) showSnack(context, 'Removed $n cached feeds');
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    if (!_seeded) {
      _seeded = true;
      final String k = state.holidays.apiKey;
      _apiKey.text = k == kDefaultCalendarApiKey ? '' : k;
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final bool wide = c.maxWidth >= 900;
        final List<Widget> left = <Widget>[
          _holidayCard(state),
          const SizedBox(height: 16),
          _clockCard(state),
        ];
        final List<Widget> right = <Widget>[
          _previewCard(state),
          const SizedBox(height: 16),
          _aboutCard(state),
        ];
        return ListView(
          padding: EdgeInsets.fromLTRB(wide ? 24 : 14, 8, wide ? 24 : 14, 32),
          children: <Widget>[
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: Column(children: left)),
                  const SizedBox(width: 16),
                  Expanded(child: Column(children: right)),
                ],
              )
            else ...<Widget>[...left, const SizedBox(height: 16), ...right],
          ],
        );
      },
    );
  }

  Widget _holidayCard(AppState state) {
    final bool loading = state.holidaysLoading || _busy;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionTitle(
            icon: Icons.public_rounded,
            title: 'Special days & holidays',
            subtitle: state.holidays.onlineReady
                ? '${state.holidays.onlineCountryCount} countries online + built-in world days'
                : 'Built-in list active - online feeds pending',
            trailing: loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(
                    tooltip: 'Reload feeds',
                    onPressed: state.refreshHolidays,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _apiKey,
            obscureText: !_keyVisible,
            decoration: InputDecoration(
              labelText: 'Google Calendar API key (optional)',
              helperText: kBuildCalendarApiKey.isNotEmpty
                  ? 'A build-time key from GitHub Actions is already embedded.'
                  : 'Leave empty to use the bundled default key.',
              suffixIcon: IconButton(
                onPressed: () => setState(() => _keyVisible = !_keyVisible),
                icon: Icon(_keyVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 18),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              GradientButton(
                label: 'Save & reload',
                icon: Icons.save_rounded,
                dense: true,
                busy: _busy,
                onPressed: loading ? null : () => _saveKey(state),
              ),
              OutlinedButton.icon(
                onPressed: loading ? null : () => _clearHolidayCache(state),
                icon: const Icon(Icons.cleaning_services_rounded, size: 15),
                label: const Text('Clear cache'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'NAGER.DATE REGIONS',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: Zc.muted),
          ),
          const SizedBox(height: 4),
          ...kNagerRegions.entries.map((MapEntry<String, List<String>> e) {
            final bool on = state.holidays.enabledRegions.contains(e.key);
            return SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              activeColor: Zc.goldDeep,
              value: on,
              onChanged: loading ? null : (bool v) => _toggleRegion(state, e.key, v),
              title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              subtitle: Text(
                e.value.map((String cc) => kCountryNames[cc] ?? cc).join(', '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
            );
          }),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            activeColor: Zc.goldDeep,
            value: state.holidays.googleEnabled,
            onChanged: loading ? null : (bool v) => _toggleGoogle(state, v),
            title: const Text('Google Calendar - India & Bangladesh',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            subtitle: const Text('Official holiday calendars (needs API key)', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _clockCard(AppState state) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionTitle(
            icon: Icons.schedule_rounded,
            title: 'Calendar clock',
            subtitle: 'Asia/Dhaka (UTC+6) - synced against internet time',
            gradient: Zc.secondaryGradient,
          ),
          const SizedBox(height: 12),
          MetaLine('Mode', state.timeSynced ? 'REAL SYNC (${state.time.source})' : 'DEVICE CLOCK'),
          MetaLine('Offset', '${state.time.offset.inMilliseconds} ms'),
          MetaLine('Dhaka now', dhakaStamp(state.dhakaNow)),
          MetaLine('Today key', state.todayKey),
          const SizedBox(height: 10),
          GradientButton(
            label: 'Re-sync clock',
            icon: Icons.sync_rounded,
            dense: true,
            gradient: Zc.secondaryGradient,
            foreground: Colors.white,
            onPressed: () async {
              await state.time.sync(state.account.databaseUrl);
              if (!mounted) return;
              setState(() {});
              showSnack(
                context,
                state.timeSynced
                    ? 'Clock synced (${state.time.source})'
                    : 'Sync failed - using device clock',
                error: !state.timeSynced,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _previewCard(AppState state) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionTitle(
            icon: Icons.phone_android_rounded,
            title: 'Preview device',
            subtitle: 'Default frame for wallpaper / live previews',
            gradient: Zc.accentGradient,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kDevicePresets.map((DevicePreset d) {
              final bool on = d.id == state.previewDeviceId;
              return ChoiceChip(
                avatar: Icon(d.icon, size: 15, color: on ? Zc.ink : Zc.inkSoft),
                label: Text(d.label),
                selected: on,
                showCheckmark: false,
                selectedColor: Zc.gold,
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: on ? Zc.ink : Zc.inkSoft,
                ),
                onSelected: (_) => state.setPreviewDevice(d.id),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          const Center(
            child: PhonePreview(
              frames: <PreviewFrame>[],
              baseWidth: 150,
              showDeviceChooser: false,
              showControls: false,
            ),
          ),
        ],
      ),
    );
  }

  Widget _aboutCard(AppState state) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionTitle(
            icon: Icons.info_outline_rounded,
            title: 'About',
            subtitle: 'Zedge Studio 2.0.0 - Unified Zedge Content Studio',
          ),
          const SizedBox(height: 12),
          ...kAccounts.map((ZedgeAccount a) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: <Widget>[
                    TagPill(
                      text: a.label,
                      color: a.id == state.account.id ? Zc.goldDeep : Zc.muted,
                      filled: a.id == state.account.id,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        a.databaseUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Zc.muted),
                      ),
                    ),
                  ],
                ),
              )),
          MetaLine('R2 gateway', kR2WorkerUrl.replaceFirst('https://', '')),
          const MetaLine('Queue path', kQueuePath),
          const MetaLine('Quota', '$kUploadsPerDay uploads / day / account'),
          const MetaLine('Wallpaper size', '${kImageTargetWidth}x$kImageTargetHeight JPEG'),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => launchUrl(Uri.parse('https://www.zedge.net/'), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new_rounded, size: 15),
            label: const Text('Open zedge.net'),
          ),
        ],
      ),
    );
  }
}
