import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart' as wf;
import 'package:webview_windows/webview_windows.dart' as ww;

import '../gemini_web.dart';
import '../gemini_web_android.dart';

/// One Gemini web job: a prompt plus an optional image for vision.
class GeminiWebTask {
  final String label;
  final String prompt;
  final Uint8List? imageBytes;
  final String? imageName;
  final RegExp? completeWhen;

  GeminiWebTask({
    required this.label,
    required this.prompt,
    this.imageBytes,
    this.imageName,
    this.completeWhen,
  });
}

/// Runs [tasks] sequentially in an embedded Gemini web tab and returns
/// the raw reply texts in order ('' for a failed task - check the
/// dialog's per-task status, or match failures by empty string).
///
/// Auto-closes on full success; stays open with per-task results when
/// anything failed or the session expired.
Future<List<String>> runGeminiWebTasks(
    BuildContext context, List<GeminiWebTask> tasks) async {
  final res = await showDialog<List<String>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _GeminiWebRunnerDialog(tasks: tasks),
  );
  return res ?? [];
}

class _GeminiWebRunnerDialog extends StatefulWidget {
  final List<GeminiWebTask> tasks;
  const _GeminiWebRunnerDialog({required this.tasks});

  @override
  State<_GeminiWebRunnerDialog> createState() =>
      _GeminiWebRunnerDialogState();
}

class _GeminiWebRunnerDialogState
    extends State<_GeminiWebRunnerDialog> {
  ww.WebviewController? _winController;
  wf.WebViewController? _androidController;
  late final GeminiWebDriver _driver;
  late final GeminiWebClient _client;
  bool _ready = false;
  bool _finished = false;
  int _index = -1;
  String _stage = 'Starting the browser...';
  String? _fatal;
  final _results = <String>[];
  final _errors = <String?>[];

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _winController?.dispose();
    GeminiWebEnv.controllerReleased();
    super.dispose();
  }

  Future<void> _run() async {
    try {
      await GeminiWebEnv.ensure();
      if (Platform.isWindows) {
        final c = ww.WebviewController();
        await c.initialize();
        GeminiWebEnv.controllerCreated();
        _winController = c;
        _driver = WindowsGeminiWebDriver(c);
      } else {
        final c = newAndroidGeminiController();
        GeminiWebEnv.controllerCreated();
        _androidController = c;
        _driver = AndroidGeminiWebDriver(c);
      }
      _client = GeminiWebClient(_driver);
      if (!mounted) return;
      setState(() => _ready = true);
      if (!await _client.isLoggedIn) {
        // First run: the tab is still blank, so load the app and wait for
        // the session to show. A cold WebView2 profile needs well over a
        // few seconds to render the avatar - a fixed delay races it, so
        // poll until the session signal appears instead.
        await _driver.loadUrl('https://gemini.google.com/app');
        final loginDeadline =
            DateTime.now().add(const Duration(seconds: 30));
        var loggedIn = false;
        while (DateTime.now().isBefore(loginDeadline)) {
          if (!mounted) return;
          if (await _client.isLoggedIn) {
            loggedIn = true;
            break;
          }
          await Future.delayed(const Duration(seconds: 1));
        }
        if (!loggedIn) {
          throw Exception(
              'Gemini web session expired. Reconnect in Settings.');
        }
      }
      for (var i = 0; i < widget.tasks.length; i++) {
        if (!mounted) return;
        final task = widget.tasks[i];
        setState(() {
          _index = i;
          _stage = '${task.label}: starting...';
        });
        try {
          final text = await _client.runPrompt(
            task.prompt,
            imageBytes: task.imageBytes,
            imageName: task.imageName ?? 'wallpaper.jpg',
            completeWhen: task.completeWhen,
            onStatus: (s) {
              if (mounted) setState(() => _stage = '${task.label}: $s');
            },
          );
          _results.add(text);
          _errors.add(null);
        } catch (e) {
          _results.add('');
          _errors.add(e.toString());
        }
        if (mounted) setState(() {});
      }
      if (!mounted) return;
      setState(() {
        _finished = true;
        _stage = 'Done.';
      });
      if (_errors.every((e) => e == null)) {
        await Future.delayed(const Duration(milliseconds: 900));
        if (mounted) Navigator.of(context).pop(_results);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fatal = e.toString();
        _finished = true;
      });
    }
  }

  void _close() => Navigator.of(context).pop(_results);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final size = MediaQuery.of(context).size;
    final webview = _ready
        ? ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Platform.isWindows
                ? ww.Webview(_winController!)
                : wf.WebViewWidget(controller: _androidController!),
          )
        : const Center(child: CircularProgressIndicator());
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      // Content-sized: no more giant empty dialog. The browser gets a
      // fixed readable height and the task list wraps its content.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: min(size.width * 0.92, 1000),
          maxHeight: size.height * 0.92,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.language_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Gemini Web tasks',
                        style: textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  if (_finished || _fatal != null)
                    IconButton(
                      tooltip: 'Close',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_outlined),
                      onPressed: _close,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (_fatal != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_fatal!,
                      style: textTheme.bodySmall),
                )
              else ...[
                SizedBox(height: 420, child: webview),
                const SizedBox(height: 8),
                Text(_stage, style: textTheme.bodySmall),
                Text(
                  'Tip: keep this window visible while tasks run - browsers throttle background tabs, which can stall Gemini until you return.',
                  style: textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline),
                ),
                const SizedBox(height: 8),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: widget.tasks.length,
                  itemBuilder: (_, i) {
                      final done = i < _errors.length;
                      final err = done ? _errors[i] : null;
                      final active = i == _index && !done;
                      return ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        leading: err != null
                            ? Icon(Icons.error_outline,
                                color: Theme.of(context)
                                    .colorScheme
                                    .error,
                                size: 20)
                            : done
                                ? Icon(Icons.check_circle_outline,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                    size: 20)
                                : active
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child:
                                            CircularProgressIndicator(
                                                strokeWidth: 2),
                                      )
                                    : const Icon(
                                        Icons
                                            .radio_button_unchecked_outlined,
                                        size: 20),
                        title: Text(widget.tasks[i].label,
                            style: textTheme.bodySmall),
                        subtitle: err != null
                            ? Text(err,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .error))
                            : null,
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
    );
  }
}