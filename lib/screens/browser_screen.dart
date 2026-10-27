import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../browser/chromium_browser.dart';
import '../browser/image_prompt_service.dart';
import 'batch_screen.dart';
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
        .where((i) =>
            (_picked.isEmpty || _picked.contains(i.id)) &&
            i.state == ImagePromptState.done &&
            (_picked.isNotEmpty || !i.addedToList))
        .toList();
    if (list.isEmpty) {
      _snack('No finished prompts to add.');
      return;
    }
    _svc.addToList(list);
    setState(_picked.clear);
    _snack('${list.length} prompt${list.length == 1 ? '' : 's'} added to the '
        'Batch Sets prompt list.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Image to Prompt Browser',
            style: TextStyle(fontWeight: FontWeight.w700)),
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
        ],
      ),
      body: !ChromiumBrowser.supported
          ? _unsupported()
          : ListView(
              padding: screenScrollPadding(context),
              children: [
                _browserCard(),
                const SizedBox(height: 12),
                _queueCard(),
                const SizedBox(height: 12),
                _optionsCard(),
              ],
            ),
    );
  }

  Widget _unsupported() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.desktop_windows_outlined, size: 48),
            const SizedBox(height: 12),
            Text('The Image to Prompt browser drives a real Chromium window '
                'and is available in the Windows desktop app.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge),
          ]),
        ),
      );

  Widget _card({required String title, required IconData icon,
      Widget? trailing, required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              if (trailing != null) trailing,
            ]),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------- browser
  Widget _browserCard() {
    final scheme = Theme.of(context).colorScheme;
    final connected = _svc.browserConnected;
    final tabs = _svc.browser?.tabCount ?? 0;
    return _card(
      title: 'Chromium browser',
      icon: Icons.travel_explore_outlined,
      trailing: Chip(
        avatar: Icon(connected ? Icons.link : Icons.link_off,
            size: 16, color: connected ? Colors.green : scheme.outline),
        label: Text(connected
            ? 'Connected · $tabs tab${tabs == 1 ? '' : 's'}'
            : 'Not running'),
        visualDensity: VisualDensity.compact,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _urlCtrl,
                onSubmitted: (_) => _go(),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.public),
                  hintText: 'Website URL or image search words',
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 18)),
                onPressed: _svc.connecting ? null : _go,
                icon: _svc.connecting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.open_in_new),
                label: Text(connected ? 'Open tab' : 'Open browser'),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final q in const [
              ['Pinterest', 'https://www.pinterest.com/'],
              ['Unsplash', 'https://unsplash.com/'],
              ['Google Images', 'https://www.google.com/imghp'],
              ['Lexica', 'https://lexica.art/'],
              ['Gemini sign-in', 'https://gemini.google.com/app'],
            ])
              ActionChip(
                label: Text(q[0]),
                onPressed: _svc.connecting
                    ? null
                    : () {
                        _urlCtrl.text = q[1];
                        _go();
                      },
              ),
            if (connected)
              ActionChip(
                avatar: const Icon(Icons.close, size: 16),
                label: const Text('Close browser'),
                onPressed: _svc.closeBrowser,
              ),
          ]),
          const SizedBox(height: 10),
          Text(
            'Hover any picture in the Chromium window: click "Prompt" to '
            'turn it into an image prompt, or tick several pictures and press '
            '"Generate prompts" in the bar at the bottom - they run one by one.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
          ),
          if (_svc.lastError.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_svc.lastError,
                style: TextStyle(color: scheme.error, fontSize: 12.5)),
          ],
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- queue
  Widget _queueCard() {
    final scheme = Theme.of(context).colorScheme;
    final items = _svc.items;
    final queued = _svc.queuedCount;
    final failed =
        items.where((i) => i.state == ImagePromptState.error).length;
    final pending = items
        .where((i) => i.state == ImagePromptState.done && !i.addedToList)
        .length;
    return _card(
      title: 'Generated prompts',
      icon: Icons.auto_awesome_outlined,
      trailing: Text('${_svc.doneCount} ready'
          '${queued > 0 ? ' · $queued queued' : ''}',
          style: TextStyle(color: scheme.onSurfaceVariant)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_svc.working || _svc.status.isNotEmpty) ...[
            if (_svc.working) const LinearProgressIndicator(),
            const SizedBox(height: 6),
            Text(_svc.status,
                style: TextStyle(
                    fontSize: 12.5,
                    color: _svc.lastError.isNotEmpty
                        ? scheme.error
                        : scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
          ],
          Wrap(spacing: 8, runSpacing: 6, children: [
            FilledButton.tonalIcon(
              onPressed: _addPicked,
              icon: const Icon(Icons.playlist_add),
              label: Text(_picked.isNotEmpty
                  ? 'Add ${_picked.length} selected to Prompts list'
                  : 'Add $pending new to Prompts list'),
            ),
            OutlinedButton.icon(
              onPressed: _openBatch,
              icon: const Icon(Icons.layers_outlined),
              label: const Text('Open Batch Sets'),
            ),
            if (_svc.working)
              OutlinedButton.icon(
                onPressed: _svc.stop,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Stop'),
              )
            else if (queued > 0)
              OutlinedButton.icon(
                onPressed: _svc.resume,
                icon: const Icon(Icons.play_arrow),
                label: Text('Resume ($queued)'),
              ),
            if (failed > 0 && !_svc.working)
              OutlinedButton.icon(
                onPressed: _svc.retryFailed,
                icon: const Icon(Icons.refresh),
                label: Text('Retry failed ($failed)'),
              ),
            if (items.isNotEmpty)
              TextButton.icon(
                onPressed: _svc.clearFinished,
                icon: const Icon(Icons.clear_all),
                label: const Text('Clear finished'),
              ),
          ]),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Column(children: [
                Icon(Icons.image_search_outlined,
                    size: 40, color: scheme.outline),
                const SizedBox(height: 8),
                Text('No pictures yet. Open the browser and click the '
                    'Prompt icon on any image.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ]),
            )
          else
            for (final it in items) _itemTile(it),
        ],
      ),
    );
  }

  Widget _itemTile(ImagePromptItem it) {
    final scheme = Theme.of(context).colorScheme;
    final (Color c, IconData ic, String label) = switch (it.state) {
      ImagePromptState.queued => (scheme.outline, Icons.schedule, 'Queued'),
      ImagePromptState.running =>
        (Colors.orange, Icons.hourglass_top, 'Analyzing'),
      ImagePromptState.done => (Colors.green, Icons.check_circle, 'Ready'),
      ImagePromptState.error => (scheme.error, Icons.error_outline, 'Failed'),
    };
    final picked = _picked.contains(it.id);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: picked ? scheme.primary : scheme.outlineVariant,
              width: picked ? 2 : 1),
        ),
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: picked,
              onChanged: it.state == ImagePromptState.done
                  ? (v) => setState(() =>
                      v == true ? _picked.add(it.id) : _picked.remove(it.id))
                  : null,
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 84,
                height: 84,
                child: it.isThumbnailable
                    ? Image.network(it.src,
                        fit: BoxFit.cover,
                        headers: {
                          if (it.pageUrl.isNotEmpty) 'Referer': it.pageUrl
                        },
                        errorBuilder: (_, __, ___) => _thumbFallback())
                    : _thumbFallback(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(ic, size: 16, color: c),
                    const SizedBox(width: 4),
                    Text(label,
                        style: TextStyle(
                            color: c,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5)),
                    if (it.addedToList) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.playlist_add_check,
                          size: 16, color: scheme.primary),
                      const SizedBox(width: 2),
                      Text('In Prompts list',
                          style: TextStyle(
                              color: scheme.primary, fontSize: 12)),
                    ],
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        it.pageTitle.isNotEmpty ? it.pageTitle : it.pageUrl,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  if (it.state == ImagePromptState.done)
                    SelectableText(it.prompt,
                        maxLines: 5, style: const TextStyle(fontSize: 13.5))
                  else if (it.state == ImagePromptState.error)
                    Text(it.error,
                        style: TextStyle(color: scheme.error, fontSize: 12.5))
                  else if (it.state == ImagePromptState.running)
                    const LinearProgressIndicator()
                  else
                    Text('Waiting for its turn...',
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 12.5)),
                ],
              ),
            ),
            Column(children: [
              if (it.state == ImagePromptState.done) ...[
                IconButton(
                  tooltip: 'Copy prompt',
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: it.prompt));
                    _snack('Prompt copied.');
                  },
                ),
                IconButton(
                  tooltip: 'Edit prompt',
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => _edit(it),
                ),
                IconButton(
                  tooltip: it.addedToList
                      ? 'Add to Prompts list again'
                      : 'Add to Prompts list',
                  icon: Icon(
                      it.addedToList
                          ? Icons.playlist_add_check
                          : Icons.playlist_add,
                      size: 20),
                  onPressed: () {
                    _svc.addToList([it]);
                    _snack('Added to the Batch Sets prompt list.');
                  },
                ),
              ],
              if (it.state == ImagePromptState.error ||
                  it.state == ImagePromptState.done)
                IconButton(
                  tooltip: 'Generate again',
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () => _svc.retry(it),
                ),
              if (it.state != ImagePromptState.running)
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () {
                    _picked.remove(it.id);
                    _svc.remove(it);
                  },
                ),
            ]),
          ],
        ),
      ),
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
    return _card(
      title: 'Options',
      icon: Icons.tune_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Add every new prompt to the Prompts list'),
            subtitle: const Text(
                'Finished prompts drop straight into Batch Sets > Prompts.'),
            value: _svc.autoAddToList,
            onChanged: (v) => _svc.saveSettings(autoAddToList: v),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<GeminiCookieSource>(
            initialValue: _svc.cookieSource,
            decoration:
                const InputDecoration(labelText: 'Gemini web cookies'),
            items: const [
              DropdownMenuItem(
                  value: GeminiCookieSource.auto,
                  child: Text('Auto - Chromium sign-in, else saved session')),
              DropdownMenuItem(
                  value: GeminiCookieSource.chromium,
                  child: Text('Live cookies from the Chromium window')),
              DropdownMenuItem(
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
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Prompt instruction sent to Gemini'),
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
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Browser path (optional)'),
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
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
                onPressed: () {
                  _ctrl.text = ImagePromptService.defaultInstruction;
                  widget.onReset();
                },
                child: const Text('Reset')),
            const SizedBox(width: 8),
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
