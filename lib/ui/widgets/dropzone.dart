import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/media.dart';
import 'common.dart';
import 'fa.dart';

Future<List<LocalFile>> pickLocalFiles({bool multiple = true, List<String>? extensions, String? title}) async {
  final res = await FilePicker.platform.pickFiles(
    allowMultiple: multiple,
    type: extensions == null ? FileType.any : FileType.custom,
    allowedExtensions: extensions,
    dialogTitle: title,
    withData: false,
  );
  if (res == null) return const [];
  final out = <LocalFile>[];
  for (final f in res.files) {
    if (f.path == null) continue;
    out.add(await LocalFile.fromPath(f.path!));
  }
  return out;
}

/// Drag & drop + click-to-choose zone (`.dropzone`, `.smart-archive-zone`, `.vpn-drop`).
class DropZone extends StatefulWidget {
  const DropZone({
    super.key,
    required this.onFiles,
    required this.title,
    this.subtitle,
    this.icon = 'fa-cloud-upload-alt',
    this.buttonLabel = 'Choose Files',
    this.extensions,
    this.multiple = true,
    this.busy = false,
    this.busyLabel,
    this.height = 150,
    this.dense = false,
    this.extra,
  });
  final Future<void> Function(List<LocalFile> files) onFiles;
  final String title;
  final String? subtitle;
  final String icon;
  final String buttonLabel;
  final List<String>? extensions;
  final bool multiple;
  final bool busy;
  final String? busyLabel;
  final double height;
  final bool dense;
  final Widget? extra;

  @override
  State<DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<DropZone> {
  bool _drag = false;

  Future<void> _dropped(List<DropItem> items) async {
    final files = <LocalFile>[];
    for (final it in items) {
      try {
        files.add(await LocalFile.fromPath(it.path));
      } catch (_) {}
    }
    if (files.isNotEmpty) await widget.onFiles(files);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return DropTarget(
      onDragEntered: (_) => setState(() => _drag = true),
      onDragExited: (_) => setState(() => _drag = false),
      onDragDone: (d) {
        setState(() => _drag = false);
        _dropped(d.files);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        constraints: BoxConstraints(minHeight: widget.height),
        padding: EdgeInsets.all(widget.dense ? 14 : 20),
        decoration: BoxDecoration(
          color: _drag ? p.tintSoft.withValues(alpha: 0.6) : p.surfaceHover.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(p.radiusMd),
          border: Border.all(color: _drag ? p.accent : p.primary2.withValues(alpha: 0.6), width: 1.6, strokeAlign: BorderSide.strokeAlignInside),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: widget.dense ? 40 : 52,
            height: widget.dense ? 40 : 52,
            decoration: BoxDecoration(gradient: p.primaryGradient, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: p.primary.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))]),
            child: Center(child: Fa(widget.icon, size: widget.dense ? 16 : 20, color: p.onPrimary)),
          ),
          SizedBox(height: widget.dense ? 8 : 12),
          Text(widget.title, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: widget.dense ? 13.5 : 15, color: p.text)),
          if (widget.subtitle != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(widget.subtitle!, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.muted))),
          SizedBox(height: widget.dense ? 8 : 12),
          Wrap(spacing: 8, runSpacing: 6, alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ZButton(widget.busy ? (widget.busyLabel ?? 'Uploading...') : widget.buttonLabel,
                icon: 'fa-folder',
                busy: widget.busy,
                small: widget.dense,
                onPressed: widget.busy
                    ? null
                    : () async {
                        final files = await pickLocalFiles(multiple: widget.multiple, extensions: widget.extensions);
                        if (files.isNotEmpty) await widget.onFiles(files);
                      }),
            if (widget.extra != null) widget.extra!,
          ]),
        ]),
      ),
    );
  }
}
