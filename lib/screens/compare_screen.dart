import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../app_theme.dart';
import '../browser/image_prompt_service.dart';
import '../compare/similarity.dart';
import '../compare/target_match.dart';
import '../widgets/ui_kit.dart';

/// Opens the originality check for a generated picture. The reference is
/// found automatically from the prompt (Image to Prompt history) or can
/// be picked by the user.
Future<void> openCompare(
  BuildContext context, {
  Uint8List? generatedBytes,
  String? generatedUrl,
  required String prompt,
}) {
  return Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => CompareScreen(
      generatedBytes: generatedBytes,
      generatedUrl: generatedUrl,
      prompt: prompt,
    ),
  ));
}

class CompareScreen extends StatefulWidget {
  const CompareScreen({
    super.key,
    this.generatedBytes,
    this.generatedUrl,
    required this.prompt,
    this.reference,
    this.referenceBytes,
  });
  final Uint8List? generatedBytes;
  final String? generatedUrl;
  final String prompt;
  final ImagePromptItem? reference;

  /// Test hook / manual reference.
  final Uint8List? referenceBytes;

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

enum _ViewMode { side, slider, overlay }

class _CompareScreenState extends State<CompareScreen> {
  final _svc = ImagePromptService.instance;
  ImagePromptItem? _ref;
  Uint8List? _refBytes, _genBytes;
  SimilarityReport? _report;
  AiCompareReview? _ai;
  String _error = '', _aiError = '';
  bool _loading = true, _aiLoading = false;
  _ViewMode _mode = _ViewMode.side;
  double _split = 0.5, _opacity = 0.5;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _svc.load();
    _ref = widget.reference ?? _svc.referenceFor(widget.prompt);
    try {
      _genBytes = widget.generatedBytes;
      if (_genBytes == null && widget.generatedUrl != null) {
        final r = await http
            .get(Uri.parse(widget.generatedUrl!))
            .timeout(const Duration(seconds: 90));
        if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
        _genBytes = r.bodyBytes;
      }
      _refBytes = widget.referenceBytes ??
          (_ref != null ? await _svc.referenceBytes(_ref!) : null);
    } catch (e) {
      _error = 'Could not load the pictures: $e';
    }
    await _analyse();
  }

  Future<void> _analyse() async {
    _report = null;
    _ai = null;
    _aiError = '';
    if (_refBytes != null && _genBytes != null) {
      if (mounted) setState(() => _loading = true);
      _report = await compareImagesInBackground(_refBytes!, _genBytes!);
      if (_report == null) _error = 'One of the pictures could not be read.';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _runAi() async {
    if (_refBytes == null || _genBytes == null) return;
    setState(() {
      _aiLoading = true;
      _aiError = '';
    });
    try {
      _ai = await _svc.aiReview(_refBytes!, _genBytes!);
    } catch (e) {
      _aiError = '$e';
    }
    if (mounted) setState(() => _aiLoading = false);
  }

  Future<void> _pickReference() async {
    final done = _svc.items
        .where((i) => i.state == ImagePromptState.done && i.prompt.isNotEmpty)
        .take(60)
        .toList();
    final choice = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.7,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.folder_open_outlined),
                title: const Text('Pick a picture file'),
                subtitle: const Text('Any reference image from this device'),
                onTap: () => Navigator.pop(ctx, 'file'),
              ),
              const Divider(height: 1),
              Expanded(
                child: done.isEmpty
                    ? const Center(
                        child: Text('No Image to Prompt history yet.'))
                    : ListView.builder(
                        itemCount: done.length,
                        itemBuilder: (_, i) {
                          final it = done[i];
                          return ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                  width: 48, height: 48, child: _thumb(it)),
                            ),
                            title: Text(it.prompt,
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                                it.pageTitle.isNotEmpty
                                    ? it.pageTitle
                                    : it.pageUrl,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            onTap: () => Navigator.pop(ctx, it),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null) return;
    setState(() => _loading = true);
    if (choice == 'file') {
      final r = await FilePicker.platform
          .pickFiles(type: FileType.image, withData: true);
      final b = r?.files.single.bytes;
      if (b == null) {
        setState(() => _loading = false);
        return;
      }
      _ref = null;
      _refBytes = b;
    } else if (choice is ImagePromptItem) {
      _ref = choice;
      _refBytes = await _svc.referenceBytes(choice);
    }
    _error = '';
    await _analyse();
  }

  Widget _thumb(ImagePromptItem it) {
    if (it.preview != null) return Image.memory(it.preview!, fit: BoxFit.cover);
    if (it.isThumbnailable) {
      return Image.network(it.src,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.image_outlined));
    }
    return const Icon(Icons.image_outlined);
  }

  // ------------------------------------------------------------ scoring
  /// Overall similarity: pixel analysis, blended with the AI review when
  /// available (the AI sees meaning, pixels see layout and colour).
  double? get _overallSimilarity {
    final r = _report;
    if (r == null) return null;
    final ai = _ai;
    if (ai == null) return r.similarity;
    return r.similarity * 0.4 + ai.similarity * 0.6;
  }

  static Color _verdictColor(OriginalityVerdict v) => switch (v) {
        OriginalityVerdict.original => AppTheme.success,
        OriginalityVerdict.inspired => const Color(0xFF14B8A6),
        OriginalityVerdict.review => AppTheme.warning,
        OriginalityVerdict.tooSimilar => const Color(0xFFEF4444),
      };

  static String _verdictLabel(OriginalityVerdict v) => switch (v) {
        OriginalityVerdict.original => 'Original',
        OriginalityVerdict.inspired => 'Inspired - safe',
        OriginalityVerdict.review => 'Review - close',
        OriginalityVerdict.tooSimilar => 'Too similar',
      };

  static String _verdictText(OriginalityVerdict v) => switch (v) {
        OriginalityVerdict.original =>
          'Clearly a new picture. Only general feel is shared.',
        OriginalityVerdict.inspired =>
          'Same vibe, different picture. Good for publishing.',
        OriginalityVerdict.review =>
          'Several visible elements match. Check before publishing.',
        OriginalityVerdict.tooSimilar =>
          'Looks like a copy of the reference. Do not publish - remix it.',
      };

  int get _refTarget =>
      (_ref?.target ?? 0) > 0 ? _ref!.target : _svc.similarityTarget;

  int? _targetInfo() => (_ref?.target ?? 0) > 0 ? _ref!.target : null;

  /// Target vs measured: the AI score is the meaningful one (pixels miss
  /// "same subject, new angle"), so the row says which one is used.
  Widget _targetRow(double sim) {
    final t = _targetInfo()!;
    final d = sim - t;
    final (label, color) = d.abs() <= matchTolerance
        ? ('On target', AppTheme.success)
        : d < 0
            ? ('More different than the target', AppTheme.warning)
            : ('Closer than the target', const Color(0xFFEF4444));
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.track_changes, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Target $t%  -  measured ${sim.round()}%  -  $label',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: color)),
            ),
          ]),
          if (_ai == null) ...[
            const SizedBox(height: 3),
            Text(
                sim < t - 12
                    ? 'Turn on "Match similarity target" in Batch Sets: the source '
                        'picture is sent with the prompt to image_to_image and results '
                        'are regenerated until they are near $t%.'
                    : 'Pixel estimate - same subject from a new angle reads low. '
                        'Run the AI review for an accurate target check.',
                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }

  Widget _rewriteButton(String label, IconData icon, int target) {
    final t = target.clamp(20, 90);
    return AppButton(
      label: '$label ($t%)',
      icon: icon,
      kind: AppButtonKind.tonal,
      expand: false,
      onPressed: () {
        _svc.rewriteWithTarget(_ref!, t);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Rewriting the prompt for $t% similarity - the new '
                'prompt goes to the batch list.')));
      },
    );
  }

  // --------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 980;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Originality check'),
        actions: [
          IconButton(
            tooltip: 'Change reference',
            icon: const Icon(Icons.swap_horiz),
            onPressed: _loading ? null : _pickReference,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: screenScrollPadding(context, 16, 1280),
              children: [
                if (_error.isNotEmpty) ...[
                  HintText(_error, icon: Icons.error_outline),
                  const SizedBox(height: 12),
                ],
                if (_refBytes == null)
                  _noReference()
                else if (_report != null)
                  wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 6, child: _visualCard()),
                            const SizedBox(width: 16),
                            Expanded(
                                flex: 5,
                                child: Column(children: _scoreCards())),
                          ],
                        )
                      : Column(children: [
                          _scoreHero(),
                          const SizedBox(height: 12),
                          _visualCard(),
                          const SizedBox(height: 12),
                          ..._scoreCards(skipHero: true),
                        ]),
              ],
            ),
    );
  }

  Widget _noReference() => SectionCard(
        icon: Icons.image_search_outlined,
        title: 'No reference found',
        subtitle: 'This prompt was not made with Image to Prompt, or its '
            'picture is no longer stored.',
        child: AppButton(
          label: 'Choose the reference picture',
          icon: Icons.add_photo_alternate_outlined,
          onPressed: _pickReference,
        ),
      );

  List<Widget> _scoreCards({bool skipHero = false}) => [
        if (!skipHero) ...[_scoreHero(), const SizedBox(height: 12)],
        _metricsCard(),
        const SizedBox(height: 12),
        _aiCard(),
        const SizedBox(height: 12),
        _paletteCard(),
      ];

  Widget _scoreHero() {
    final sim = _overallSimilarity!;
    final v = SimilarityReport.verdictFor(sim);
    final c = _verdictColor(v);
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            SizedBox(
              width: 116,
              height: 116,
              child: CustomPaint(
                painter: _RingPainter(
                    value: (100 - sim) / 100,
                    color: c,
                    track: cs.surfaceContainerHighest),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${(100 - sim).round()}%',
                          style: const TextStyle(
                              fontSize: 28, fontWeight: FontWeight.w800)),
                      Text('creative',
                          style: TextStyle(
                              fontSize: 11.5, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatusPill(
                      label: _verdictLabel(v),
                      color: c,
                      icon: v == OriginalityVerdict.tooSimilar
                          ? Icons.warning_amber_rounded
                          : Icons.verified_outlined),
                  const SizedBox(height: 8),
                  Text(_verdictText(v),
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(
                      'Similarity to reference: ${sim.round()}%'
                      '${_ai != null ? '  (pixels ${_report!.similarity.round()}% - AI ${_ai!.similarity}%)' : '  (pixel analysis)'}',
                      style: TextStyle(
                          fontSize: 12.5, color: cs.onSurfaceVariant)),
                  if (_targetInfo() != null) ...[
                    const SizedBox(height: 10),
                    _targetRow(sim),
                  ],
                  if (_ref != null) ...[
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      if (sim > _refTarget - 12 ||
                          v.index >= OriginalityVerdict.review.index)
                        _rewriteButton('Less similar', Icons.auto_fix_high,
                            _refTarget - 20),
                      if (sim < _refTarget - 12)
                        _rewriteButton(
                            'Closer to reference',
                            Icons.center_focus_strong_outlined,
                            _refTarget + 15),
                    ]),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _visualCard() {
    final a = _refBytes!, b = _genBytes!;
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final toggle = SegmentedButton<_ViewMode>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: const [
        ButtonSegment(
            value: _ViewMode.side,
            icon: Icon(Icons.view_column_outlined, size: 18),
            tooltip: 'Side by side'),
        ButtonSegment(
            value: _ViewMode.slider,
            icon: Icon(Icons.compare, size: 18),
            tooltip: 'Slider'),
        ButtonSegment(
            value: _ViewMode.overlay,
            icon: Icon(Icons.layers_outlined, size: 18),
            tooltip: 'Overlay'),
      ],
      selected: {_mode},
      onSelectionChanged: (s) => setState(() => _mode = s.first),
    );
    return SectionCard(
      icon: Icons.compare_outlined,
      title: 'Visual compare',
      subtitle: 'A = reference  -  B = new image',
      trailing: narrow ? null : toggle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (narrow) ...[toggle, const SizedBox(height: 12)],
          switch (_mode) {
            _ViewMode.side => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _labelled('A  Reference', a)),
                  const SizedBox(width: 10),
                  Expanded(child: _labelled('B  New', b)),
                ],
              ),
            _ViewMode.slider => _sliderView(a, b),
            _ViewMode.overlay => _overlayView(a, b),
          },
        ],
      ),
    );
  }

  Widget _labelled(String label, Uint8List bytes) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 9 / 14,
              child:
                  Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
            ),
          ),
          const SizedBox(height: 6),
          Text(label,
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      );

  Widget _sliderView(Uint8List a, Uint8List b) => AspectRatio(
        aspectRatio: 3 / 4,
        child: LayoutBuilder(builder: (context, c) {
          final x = c.maxWidth * _split;
          return GestureDetector(
            onHorizontalDragUpdate: (d) => setState(() => _split =
                (d.localPosition.dx / c.maxWidth).clamp(0.0, 1.0).toDouble()),
            onTapDown: (d) => setState(() => _split =
                (d.localPosition.dx / c.maxWidth).clamp(0.0, 1.0).toDouble()),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(fit: StackFit.expand, children: [
                Image.memory(b, fit: BoxFit.cover, gaplessPlayback: true),
                ClipRect(
                  clipper: _LeftClip(x),
                  child:
                      Image.memory(a, fit: BoxFit.cover, gaplessPlayback: true),
                ),
                Positioned(
                  left: x - 1.5,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 3, color: Colors.white),
                ),
                Positioned(
                  left: x - 18,
                  top: c.maxHeight / 2 - 18,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle),
                    child: const Icon(Icons.unfold_more,
                        color: Colors.black87, size: 22),
                  ),
                ),
                const Positioned(
                    left: 10, top: 10, child: _Tag('A  Reference')),
                const Positioned(right: 10, top: 10, child: _Tag('B  New')),
              ]),
            ),
          );
        }),
      );

  Widget _overlayView(Uint8List a, Uint8List b) => Column(children: [
        AspectRatio(
          aspectRatio: 3 / 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(fit: StackFit.expand, children: [
              Image.memory(a, fit: BoxFit.cover, gaplessPlayback: true),
              Opacity(
                  opacity: _opacity,
                  child: Image.memory(b,
                      fit: BoxFit.cover, gaplessPlayback: true)),
            ]),
          ),
        ),
        Row(children: [
          const Text('A', style: TextStyle(fontWeight: FontWeight.w700)),
          Expanded(
            child: Slider(
                value: _opacity,
                onChanged: (v) => setState(() => _opacity = v)),
          ),
          const Text('B', style: TextStyle(fontWeight: FontWeight.w700)),
        ]),
      ]);

  Widget _metricsCard() {
    final r = _report!;
    final cs = Theme.of(context).colorScheme;
    return SectionCard(
      icon: Icons.analytics_outlined,
      title: 'Similarity breakdown',
      subtitle: 'Measured on the pixels - lower bar = more creative',
      child: Column(
        children: [
          for (final m in r.metrics)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(m.label,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w600)),
                    ),
                    Text('${(m.similarity * 100).round()}% similar',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: _verdictColor(SimilarityReport.verdictFor(
                                m.similarity * 100)))),
                  ]),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: m.similarity,
                      minHeight: 8,
                      backgroundColor: cs.surfaceContainerHighest,
                      color: _verdictColor(
                          SimilarityReport.verdictFor(m.similarity * 100)),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text('${m.detail}  -  weight ${(m.weight * 100).round()}%',
                      style: TextStyle(
                          fontSize: 11.5, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          const HintText(
              'Pixel analysis cannot see meaning (same character in a new '
              'pose). Run the AI review for a full professional judgement.',
              icon: Icons.info_outline),
        ],
      ),
    );
  }

  Widget _aiCard() {
    final ai = _ai;
    final cs = Theme.of(context).colorScheme;
    Color riskColor(String r) => r == 'high'
        ? const Color(0xFFEF4444)
        : r == 'medium'
            ? AppTheme.warning
            : AppTheme.success;
    return SectionCard(
      icon: Icons.psychology_alt_outlined,
      title: 'AI art-director review',
      subtitle: 'Gemini looks at both pictures and judges the copy risk',
      trailing: ai != null
          ? StatusPill(label: '${ai.risk} risk', color: riskColor(ai.risk))
          : null,
      child: ai == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_aiError.isNotEmpty) ...[
                  HintText(_aiError, icon: Icons.error_outline),
                  const SizedBox(height: 8),
                ],
                AppButton(
                  label: _aiLoading ? 'Reviewing...' : 'Run AI review',
                  icon: Icons.auto_awesome,
                  kind: AppButtonKind.tonal,
                  loading: _aiLoading,
                  onPressed: _aiLoading ? null : _runAi,
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'AI similarity ${ai.similarity}%  -  '
                    '${100 - ai.similarity}% creative',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                if (ai.verdict.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(ai.verdict, style: const TextStyle(fontSize: 13.5)),
                ],
                if (ai.kept.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Shared with the reference',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  _chips(ai.kept, AppTheme.warning),
                ],
                if (ai.changed.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Made different (creative)',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  _chips(ai.changed, AppTheme.success),
                ],
                if (ai.advice.isNotEmpty &&
                    ai.advice.toLowerCase() != 'none') ...[
                  const SizedBox(height: 12),
                  HintText('Advice: ${ai.advice}',
                      icon: Icons.lightbulb_outline),
                ],
              ],
            ),
    );
  }

  Widget _chips(List<String> items, Color c) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final t in items)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: c.withValues(alpha: 0.35)),
              ),
              child: Text(t, style: const TextStyle(fontSize: 12.5)),
            ),
        ],
      );

  Widget _paletteCard() {
    final r = _report!;
    Widget row(String label, List<int> colors) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            SizedBox(
                width: 84,
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600))),
            for (final c in colors)
              Expanded(
                child: Container(
                  height: 30,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: Color(c),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
          ]),
        );
    return SectionCard(
      icon: Icons.palette_outlined,
      title: 'Dominant colours',
      subtitle: 'Reference ${r.sizeA.$1}x${r.sizeA.$2}  -  '
          'new ${r.sizeB.$1}x${r.sizeB.$2}',
      child: Column(children: [
        row('Reference', r.paletteA),
        row('New', r.paletteB),
      ]),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: Colors.black54, borderRadius: BorderRadius.circular(8)),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w600)),
      );
}

class _LeftClip extends CustomClipper<Rect> {
  _LeftClip(this.x);
  final double x;
  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, x, size.height);
  @override
  bool shouldReclip(_LeftClip old) => old.x != x;
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.color, required this.track});
  final double value;
  final Color color, track;
  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 11.0;
    final rect = Rect.fromLTWH(
        stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
        rect, -math.pi / 2, math.pi * 2 * value.clamp(0.0, 1.0), false, p);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color;
}
