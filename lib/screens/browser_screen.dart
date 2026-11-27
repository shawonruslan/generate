import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';


import '../app_theme.dart';
import '../browser/chromium_browser.dart';
import '../browser/image_prompt_service.dart';
import '../widgets/originality_panel.dart';
import '../widgets/ui_kit.dart';
import 'batch_screen.dart';
import 'compare_screen.dart';
import 'settings_screen.dart';

/// "Image to Prompt" browser: opens a real Chromium window (no WebView),
/// lets the user click the overlay icon on any web picture (or tick many
/// and run them one by one) and collects the Gemini-generated prompts,
/// which can be sent to the Batch Sets prompt list.
class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key, this.openedFromBatch = false});

  /// True when Batch Sets pushed this screen (then "Open Batch Sets" just
  /// pops back instead of stacking a second Batch screen).
  final bool openedFromBatch;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  final _svc = ImagePromptService.instance;
  final _urlCtrl = TextEditingController();
  final Set<String> _picked = {};

  @override
  void initState() {
    super.initState();
    _svc.addListener(_changed);
    _svc.load().then((_) {
      if (mounted && _urlCtrl.text.isEmpty) _urlCtrl.text = _svc.homeUrl;
    });
  }

  @override
  void dispose() {
    _svc.removeListener(_changed);
    _urlCtrl.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _go() async {
    final url = _urlCtrl.text;
    await _svc.saveSettings(homeUrl: url);
    await _svc.open(url);
    if (_svc.lastError.isNotEmpty) _snack(_svc.lastError);
  }

  void _openBatch() {
    if (widget.openedFromBatch) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const BatchScreen()));
    }
  }

  void _addPicked() {
    final list = _svc.items
        .where((i) => _picked.isEmpty || _picked.contains(i.id))
        .toList();
    var n = _svc.addToList(list);
    var again = false;
    if (n == 0) {
      // Everything was sent before (e.g. the Batch list was cleared or
      // closed): send them again instead of refusing.
      n = _svc.addToList(list, force: true);
      again = true;
    }
    setState(_picked.clear);
    _snack(n == 0
        ? 'No finished prompts to add yet.'
        : '$n prompt${n == 1 ? '' : 's'} ${again ? 'added again' : 'added'} to the Batch Sets prompt list.');
  }

  @override
  Widget build(BuildContext context) {
    final android = ImagePromptService.builtInBrowser;
    return Scaffold(
      appBar: AppBar(
        title: Text(android ? 'Image to Prompt' : 'Image to Prompt Browser',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Batch Sets prompt list',
            icon: const Icon(Icons.layers_outlined),
            onPressed: _openBatch,
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: !ImagePromptService.browserSupported
          ? _unsupported()
          : ListView(
              padding: screenScrollPadding(context, 16, 980),
              children: [
                _browserCard(),
                const SizedBox(height: 14),
                if (_svc.basket.isNotEmpty) ...[
                  _basketCard(),
                  const SizedBox(height: 14),
                ],
                _queueCard(),
                const SizedBox(height: 14),
                _optionsCard(),
              ],
            ),
    );
  }

  Widget _unsupported() => const Center(
        child: EmptyState(
          icon: Icons.desktop_windows_outlined,
          title: 'Not available here',
          message: 'The Image to Prompt browser is not available on this '
              'platform.',
        ),
      );

  // --------------------------------------------------------------- browser
  static const _sites = [
    ('Pinterest', 'https://www.pinterest.com/', Icons.push_pin_outlined),
    ('Unsplash', 'https://unsplash.com/', Icons.photo_camera_outlined),
    ('Google Images', 'https://www.google.com/imghp', Icons.image_search),
    ('Lexica', 'https://lexica.art/', Icons.auto_awesome_outlined),
  ];

  Widget _browserCard() {
    final scheme = Theme.of(context).colorScheme;
    final connected = _svc.browserConnected;
    final tabs = _svc.browser?.tabCount ?? 0;
    final android = ImagePromptService.builtInBrowser;
    return SectionCard(
      title: android ? 'Browser' : 'Chromium browser',
      subtitle: android
          ? 'Built-in Firefox engine'
          : 'Your installed Chrome / Edge / Brave',
      icon: Icons.travel_explore_outlined,
      trailing: StatusPill(
        label: connected
            ? (android ? 'Ready' : '$tabs tab${tabs == 1 ? '' : 's'}')
            : 'Closed',
        color: connected ? AppTheme.success : scheme.outline,
        icon: connected ? Icons.circle : Icons.circle_outlined,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _urlCtrl,
            onSubmitted: (_) => _go(),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search pictures or paste a link',
              suffixIcon: _urlCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => setState(_urlCtrl.clear),
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _sites.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final s = _sites[i];
                return ActionChip(
                  avatar: Icon(s.$3, size: 17),
                  label: Text(s.$1),
                  onPressed: _svc.connecting
                      ? null
                      : () {
                          _urlCtrl.text = s.$2;
                          _go();
                        },
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          ButtonGroup(children: [
            AppButton(
              label: android
                  ? 'Open browser'
                  : (connected ? 'Open tab' : 'Open browser'),
              icon: Icons.open_in_new_rounded,
              loading: _svc.connecting,
              onPressed: _go,
            ),
            if (connected && android)
              AppButton(
                label: 'Back to page',
                icon: Icons.web_asset_outlined,
                kind: AppButtonKind.tonal,
                onPressed: _svc.showBrowser,
              )
            else
              AppButton(
                label: _svc.signingIn ? 'Waiting...' : 'Sign in',
                icon: Icons.login_rounded,
                kind: AppButtonKind.outline,
                loading: _svc.signingIn,
                onPressed: _svc.connecting ? null : _svc.signInToGoogle,
              ),
          ]),
          if (connected) ...[
            const SizedBox(height: 6),
            Row(children: [
              if (android)
                TextButton.icon(
                  onPressed: _svc.signingIn ? null : _svc.signInToGoogle,
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: const Text('Google sign-in'),
                ),
              const Spacer(),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                onPressed: _svc.closeBrowser,
                icon: const Icon(Icons.power_settings_new, size: 18),
                label: const Text('Close browser'),
              ),
            ]),
          ],
          if (_svc.lastError.isNotEmpty) ...[
            const SizedBox(height: 10),
            _errorBox(_svc.lastError),
          ],
          const SizedBox(height: 4),
          ExpansionTile(
            title: const Text('How it works',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            leading: Icon(Icons.help_outline, color: scheme.primary, size: 20),
            minTileHeight: 44,
            children: [
              StepList(android
                  ? const [
                      'Open the browser and go to any site with pictures.',
                      'Tap "Select pictures" (bottom right), then tap the '
                          'pictures you want - links do not open while '
                          'selecting. Tapping a video captures its frame.',
                      'Snip (bottom left): drag over any area - locked '
                          'pictures, video frames, art - to make a prompt '
                          'from exactly what you see.',
                      'Tap "Generate prompts". Go back to the app any time: '
                          'prompts keep generating one by one in the '
                          'background and appear below.',
                      '"Google sign-in" uses the same engine, so Gemini and '
                          'the browser are signed in together.',
                    ]
                  : const [
                      'Open the browser and go to any site with pictures.',
                      'Hover a picture and click "Prompt", or tick several '
                          'and press "Generate prompts" in the bottom bar.',
                      'Locked picture or video? Hover it and click the '
                          'camera to capture exactly what you see, or use '
                          'Snip (bottom left, Alt+Shift+S) on any area.',
                      'Prompts run one by one and appear below.',
                      '"Google sign-in" opens a normal window (Google blocks '
                          'sign-in in controlled windows); it closes by itself once Gemini opens.',
                    ]),
            ],
          ),
        ],
      ),
    );
  }

  Widget _thumb(ImagePromptItem it) {
    if (it.preview != null) {
      return Image.memory(it.preview!,
          fit: BoxFit.cover, gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _thumbFallback());
    }
    if (it.isThumbnailable) {
      return Image.network(it.src,
          fit: BoxFit.cover,
          headers: {if (it.pageUrl.isNotEmpty) 'Referer': it.pageUrl},
          errorBuilder: (_, __, ___) => _thumbFallback());
    }
    return _thumbFallback();
  }

  static IconData _captureIcon(String kind) => switch (kind) {
        'video' => Icons.videocam_rounded,
        'area' => Icons.crop_free_rounded,
        _ => Icons.photo_camera_rounded,
      };

  Widget _errorBox(String msg) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.error_outline, size: 18, color: scheme.error),
        const SizedBox(width: 10),
        Expanded(
          child: Text(msg,
              style: TextStyle(color: scheme.error, fontSize: 13, height: 1.4)),
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------- basket
  Widget _basketCard() {
    final pages = _svc.basket.map((b) => b.pageUrl).toSet().length;
    return SectionCard(
      title: '${_svc.basket.length} selected',
      subtitle: 'From $pages page${pages == 1 ? '' : 's'} · kept while you browse',
      icon: Icons.check_circle_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _svc.basket.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final b = _svc.basket[i];
                return Stack(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: b.ref.src.startsWith('http')
                          ? Image.network(b.ref.src,
                              fit: BoxFit.cover,
                              headers: {
                                if (b.pageUrl.isNotEmpty) 'Referer': b.pageUrl
                              },
                              errorBuilder: (_, __, ___) => _thumbFallback())
                          : _thumbFallback(),
                    ),
                  ),
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.6),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => _svc.removeFromBasket(b),
                        child: const Padding(
                          padding: EdgeInsets.all(3),
                          child:
                              Icon(Icons.close, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ]);
              },
            ),
          ),
          const SizedBox(height: 14),
          ButtonGroup(children: [
            AppButton(
              label: 'Generate prompts',
              icon: Icons.auto_awesome,
              onPressed: _svc.generateBasket,
            ),
            AppButton(
              label: 'Clear',
              icon: Icons.clear_rounded,
              kind: AppButtonKind.outline,
              onPressed: _svc.clearBasket,
            ),
          ]),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- queue
  Widget _queueCard() {
    final items = _svc.items;
    final queued = _svc.queuedCount;
    final failed =
        items.where((i) => i.state == ImagePromptState.error).length;
    final pending = items
        .where((i) => i.state == ImagePromptState.done && !i.addedToList)
        .length;
    final addCount = _picked.isNotEmpty ? _picked.length : pending;
    final secondary = <Widget>[
      if (_svc.working)
        _miniAction(Icons.stop_circle_outlined, 'Stop', _svc.stop)
      else if (queued > 0)
        _miniAction(Icons.play_arrow_rounded, 'Resume ($queued)', _svc.resume),
      if (failed > 0 && !_svc.working)
        _miniAction(Icons.refresh, 'Retry failed ($failed)', _svc.retryFailed),
      if (_picked.isNotEmpty)
        _miniAction(Icons.deselect, 'Unselect', () => setState(_picked.clear)),
      if (items.isNotEmpty)
        _miniAction(Icons.cleaning_services_outlined, 'Clear finished',
            _svc.clearFinished),
    ];
    return SectionCard(
      title: 'Prompts',
      subtitle: '${_svc.doneCount} ready'
          '${queued > 0 ? ' · $queued queued' : ''}'
          '${failed > 0 ? ' · $failed failed' : ''}',
      icon: Icons.auto_awesome_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_svc.working || _svc.status.isNotEmpty) ...[
            if (_svc.working) const LinearProgressIndicator(),
            if (_svc.working) const SizedBox(height: 8),
            if (_svc.lastError.isNotEmpty)
              _errorBox(_svc.status)
            else
              HintText(_svc.status,
                  icon: _svc.working ? Icons.sync : Icons.check_circle_outline),
            const SizedBox(height: 12),
          ],
          if (items.isNotEmpty) ...[
            ButtonGroup(children: [
              AppButton(
                label: addCount == 0
                    ? 'Add all again'
                    : (_picked.isNotEmpty
                        ? 'Add $addCount selected'
                        : 'Add $addCount to list'),
                icon: addCount == 0
                    ? Icons.replay_rounded
                    : Icons.playlist_add,
                onPressed: _svc.doneCount == 0 ? null : _addPicked,
              ),
              AppButton(
                label: 'Batch Sets',
                icon: Icons.layers_outlined,
                kind: AppButtonKind.outline,
                onPressed: _openBatch,
              ),
            ]),
            if (secondary.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 4, runSpacing: 0, children: secondary),
            ],
          ],
          if (items.isEmpty)
            EmptyState(
              icon: Icons.image_search_outlined,
              title: 'No prompts yet',
              message: ImagePromptService.builtInBrowser
                  ? 'Open the browser, tap "Select pictures" and pick the '
                      'images you like.'
                  : 'Open the browser and click "Prompt" on any picture.',
            )
          else
            for (final it in items) _itemTile(it),
        ],
      ),
    );
  }

  Widget _miniAction(IconData icon, String label, VoidCallback onTap) =>
      TextButton.icon(
        style: TextButton.styleFrom(
            minimumSize: const Size(40, 40),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            textStyle:
                const TextStyle(fontFamily: AppTheme.font, fontSize: 13.5, fontWeight: FontWeight.w600)),
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );

  Widget _itemTile(ImagePromptItem it) {
    final scheme = Theme.of(context).colorScheme;
    final (Color c, IconData ic, String label) = switch (it.state) {
      ImagePromptState.queued => (scheme.outline, Icons.schedule, 'Queued'),
      ImagePromptState.running =>
        (AppTheme.warning, Icons.hourglass_top_rounded, 'Analyzing'),
      ImagePromptState.done =>
        (AppTheme.success, Icons.check_circle_rounded, 'Ready'),
      ImagePromptState.error =>
        (scheme.error, Icons.error_outline_rounded, 'Failed'),
    };
    final picked = _picked.contains(it.id);
    final done = it.state == ImagePromptState.done;
    void togglePick() => setState(
        () => picked ? _picked.remove(it.id) : _picked.add(it.id));
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: picked
            ? scheme.primary.withValues(alpha: 0.08)
            : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onLongPress: done ? togglePick : null,
          onTap: done
              ? (_picked.isNotEmpty ? togglePick : () => _showPrompt(it))
              : null,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: picked ? scheme.primary : scheme.outlineVariant,
                  width: picked ? 1.6 : 1),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 76,
                          height: 76,
                          child: _thumb(it),
                        ),
                      ),
                      if (it.isCapture)
                        Positioned(
                          left: 4,
                          bottom: 4,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(_captureIcon(it.captureKind),
                                size: 13, color: Colors.white),
                          ),
                        ),
                      if (picked)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.check_rounded,
                                color: Colors.white, size: 32),
                          ),
                        ),
                    ]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            StatusPill(label: label, color: c, icon: ic),
                            if (it.addedToList)
                              StatusPill(
                                  label: 'In Prompts',
                                  color: scheme.primary,
                                  icon: Icons.playlist_add_check),
                          ]),
                          const SizedBox(height: 8),
                          Text(
                            it.pageTitle.isNotEmpty
                                ? it.pageTitle
                                : (Uri.tryParse(it.pageUrl)?.host ??
                                    it.pageUrl),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 12.5,
                                height: 1.35),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (done)
                  Text(it.prompt,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, height: 1.45))
                else if (it.state == ImagePromptState.error)
                  Text(it.error,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: scheme.error, fontSize: 13, height: 1.4))
                else if (it.state == ImagePromptState.running)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: LinearProgressIndicator(),
                  )
                else
                  Text('Waiting for its turn...',
                      style: TextStyle(
                          color: scheme.onSurfaceVariant, fontSize: 13)),
                if (it.state != ImagePromptState.running) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    if (done) ...[
                      IconAction(
                        icon: Icons.copy_rounded,
                        tooltip: 'Copy prompt',
                        onPressed: () => _copy(it),
                      ),
                      const SizedBox(width: 8),
                      IconAction(
                        icon: Icons.edit_outlined,
                        tooltip: 'Edit prompt',
                        onPressed: () => _edit(it),
                      ),
                      const SizedBox(width: 8),
                      IconAction(
                        icon: it.addedToList
                            ? Icons.playlist_add_check
                            : Icons.playlist_add,
                        selected: it.addedToList,
                        tooltip: it.addedToList
                            ? 'Added - tap to add again'
                            : 'Add to Prompts list',
                        onPressed: () => _addOne(it),
                      ),
                      const SizedBox(width: 8),
                    ],
                    IconAction(
                      icon: Icons.refresh_rounded,
                      tooltip: 'Generate again',
                      onPressed: () => _svc.retry(it),
                    ),
                    const Spacer(),
                    IconAction(
                      icon: Icons.delete_outline_rounded,
                      tooltip: 'Remove',
                      color: scheme.error,
                      onPressed: () {
                        _picked.remove(it.id);
                        _svc.remove(it);
                      },
                    ),
                  ]),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _copy(ImagePromptItem it) {
    Clipboard.setData(ClipboardData(text: it.prompt));
    _snack('Prompt copied.');
  }

  void _addOne(ImagePromptItem it) {
    final again = it.addedToList;
    final n = _svc.addToList([it], force: true);
    if (n == 0) {
      _snack('This prompt is not ready yet.');
      return;
    }
    _snack(again
        ? 'Added again to the Batch Sets prompt list.'
        : 'Added to the Batch Sets prompt list.');
  }

  /// Kept / changed elements of the picture for its similarity target.
  Widget _elementPlan(ImagePromptItem it, ColorScheme scheme) {
    final kept = it.elements.where((e) => !e.change).toList();
    final changed = it.elements.where((e) => e.change).toList();
    Widget chips(List<SceneElement> list, Color c) => Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final e in list)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: c.withValues(alpha: 0.4)),
                ),
                child: Text(e.name,
                    style: TextStyle(fontSize: 12, color: scheme.onSurface)),
              ),
          ],
        );
    final label = TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: scheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            'Element plan for ${it.target}% - ${it.elements.length} elements found',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('Kept (${kept.length})', style: label),
        const SizedBox(height: 6),
        chips(kept, const Color(0xFFF59E0B)),
        const SizedBox(height: 10),
        Text('Changed (${changed.length})', style: label),
        const SizedBox(height: 6),
        chips(changed, const Color(0xFF22C55E)),
      ],
    );
  }

  /// Full prompt in a bottom sheet (tap on a card).
  Future<void> _showPrompt(ImagePromptItem it) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    if (it.isThumbnailable || it.preview != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                            width: 48, height: 48, child: _thumb(it)),
                      ),
                      const SizedBox(width: 12),
                    ],
                    const Expanded(
                      child: Text('Prompt',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(it.prompt,
                              style: TextStyle(
                                  fontSize: 15,
                                  height: 1.55,
                                  color: scheme.onSurface)),
                          if (it.elements.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            _elementPlan(it, scheme),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  ButtonGroup(minItemWidth: 100, children: [
                    AppButton(
                      label: 'Copy',
                      icon: Icons.copy_rounded,
                      onPressed: () {
                        _copy(it);
                        Navigator.of(ctx).pop();
                      },
                    ),
                    AppButton(
                      label: 'Edit',
                      icon: Icons.edit_outlined,
                      kind: AppButtonKind.outline,
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _edit(it);
                      },
                    ),
                    AppButton(
                      label: it.addedToList ? 'Add again' : 'Add',
                      icon: it.addedToList
                          ? Icons.replay_rounded
                          : Icons.playlist_add,
                      kind: AppButtonKind.outline,
                      onPressed: () {
                        _addOne(it);
                        Navigator.of(ctx).pop();
                      },
                    ),
                                    ]),
                  const SizedBox(height: 10),
                  ButtonGroup(minItemWidth: 140, children: [
                    AppButton(
                      label: 'Check originality',
                      icon: Icons.compare_outlined,
                      kind: AppButtonKind.tonal,
                      tooltip: 'Pick the image you generated from this prompt',
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        final r = await FilePicker.platform
                            .pickFiles(type: FileType.image, withData: true);
                        final b = r?.files.single.bytes;
                        if (b == null || !mounted) return;
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => CompareScreen(
                                reference: it,
                                generatedBytes: b,
                                prompt: it.prompt)));
                      },
                    ),
                    AppButton(
                      label: 'Less similar',
                      icon: Icons.auto_fix_high,
                      kind: AppButtonKind.outline,
                      tooltip: 'Rewrite this prompt 20% less similar',
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _svc.remixMoreOriginal(it);
                      },
                    ),
                  ]),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _thumbFallback() => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.image_outlined),
      );

  Future<void> _edit(ImagePromptItem it) async {
    final ctrl = TextEditingController(text: it.prompt);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit prompt'),
        content: SizedBox(
          width: 520,
          child: TextField(
              controller: ctrl, maxLines: 10, minLines: 4, autofocus: true),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      _svc.updatePrompt(it, ctrl.text.trim());
    }
    ctrl.dispose();
  }

  // --------------------------------------------------------------- options
  Widget _optionsCard() {
    return SectionCard(
      title: 'Options',
      icon: Icons.tune_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-add to Prompts list'),
            subtitle: const Text(
                'Finished prompts go straight to Batch Sets > Prompts.'),
            value: _svc.autoAddToList,
            onChanged: (v) => _svc.saveSettings(autoAddToList: v),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<GeminiCookieSource>(
            initialValue: _svc.cookieSource,
            decoration:
                const InputDecoration(labelText: 'Gemini web cookies'),
            isExpanded: true,
            items: [
              DropdownMenuItem(
                  value: GeminiCookieSource.auto,
                  child: Text(ImagePromptService.builtInBrowser
                      ? 'Auto - browser sign-in, else saved session'
                      : 'Auto - Chromium sign-in, else saved session')),
              DropdownMenuItem(
                  value: GeminiCookieSource.chromium,
                  child: Text(ImagePromptService.builtInBrowser
                      ? 'Live cookies from the built-in browser'
                      : 'Live cookies from the Chromium window')),
              const DropdownMenuItem(
                  value: GeminiCookieSource.saved,
                  child: Text('Saved session from Settings')),
            ],
            onChanged: (v) {
              if (v != null) _svc.saveSettings(cookieSource: v);
            },
          ),
          if (_svc.geminiNote.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Last used: ${_svc.geminiNote}',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          const SizedBox(height: 12),
          SimilarityTargetPanel(
            target: _svc.similarityTarget,
            onChanged: (v) {
              _svc.saveSettings(similarityTarget: v);
              setState(() {});
            },
            antiRepeat: _svc.antiRepeat,
            onAntiRepeat: (v) {
              _svc.saveSettings(antiRepeat: v);
              setState(() {});
            },
          ),
          ExpansionTile(
            title: const Text('Gemini instruction',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
            subtitle: const Text('How the picture is described',
                style: TextStyle(fontSize: 12.5)),
            children: [
              _InstructionEditor(
                initial: _svc.instruction,
                onSave: (v) {
                  _svc.saveSettings(instruction: v);
                  _snack('Instruction saved.');
                },
                onReset: () {
                  _svc.saveSettings(
                      instruction: ImagePromptService.defaultInstruction);
                  _snack('Instruction reset.');
                },
              ),
            ],
          ),
          if (!ImagePromptService.builtInBrowser)
          ExpansionTile(
            title: const Text('Browser path (optional)',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
            subtitle: Text(
                ChromiumBrowser.findExecutable(_svc.browserPath) ??
                    'No Chromium browser found',
                style: const TextStyle(fontSize: 12)),
            children: [
              _PathEditor(
                initial: _svc.browserPath,
                onSave: (v) {
                  _svc.saveSettings(browserPath: v);
                  _snack(v.trim().isEmpty
                      ? 'Using the auto-detected browser.'
                      : 'Browser path saved.');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InstructionEditor extends StatefulWidget {
  const _InstructionEditor(
      {required this.initial, required this.onSave, required this.onReset});
  final String initial;
  final ValueChanged<String> onSave;
  final VoidCallback onReset;
  @override
  State<_InstructionEditor> createState() => _InstructionEditorState();
}

class _InstructionEditorState extends State<_InstructionEditor> {
  late final _ctrl = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(controller: _ctrl, maxLines: 10, minLines: 5),
          const SizedBox(height: 6),
          Text('Keep the [PROMPT] ... [/PROMPT] markers so the reply can be '
              'checked for completeness.',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Text('Closeness is set with the Similarity target above - it is '
              'added to this instruction for every picture and overrides any '
              'originality wording here.',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
            TextButton(
                onPressed: () {
                  _ctrl.text = ImagePromptService.defaultInstruction;
                  widget.onReset();
                },
                child: const Text('Reset to default')),
            FilledButton.tonal(
                onPressed: () => widget.onSave(_ctrl.text),
                child: const Text('Save')),
          ]),
          const SizedBox(height: 8),
        ],
      );
}

class _PathEditor extends StatefulWidget {
  const _PathEditor({required this.initial, required this.onSave});
  final String initial;
  final ValueChanged<String> onSave;
  @override
  State<_PathEditor> createState() => _PathEditorState();
}

class _PathEditorState extends State<_PathEditor> {
  late final _ctrl = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              decoration: const InputDecoration(
                  hintText:
                      r'C:\Program Files\Google\Chrome\Application\chrome.exe'),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
              onPressed: () => widget.onSave(_ctrl.text),
              child: const Text('Save')),
        ]),
      );
}
