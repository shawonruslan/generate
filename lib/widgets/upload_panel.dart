import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_config.dart';
import '../services/r2_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

Future<void> showUploadSheet(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0x99120F07),
    builder: (BuildContext context) => const UploadDialog(),
  );
}

/// Native uploader: files go straight to the R2 worker with `http`, then one
/// queue row is written per item (or one row with all slots for set types).
class UploadDialog extends StatefulWidget {
  const UploadDialog({super.key});

  @override
  State<UploadDialog> createState() => _UploadDialogState();
}

class _UploadDialogState extends State<UploadDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _tags = TextEditingController();
  final TextEditingController _category = TextEditingController();
  final TextEditingController _description = TextEditingController();

  String _type = 'WALLPAPER';
  DateTime? _scheduled;
  final Map<String, PlatformFile> _slotFiles = <String, PlatformFile>{};
  List<PlatformFile> _singles = <PlatformFile>[];
  bool _busy = false;
  String _progress = '';

  List<String> get _slots => kSetSlots[_type] ?? const <String>[];
  bool get _isSet => _slots.isNotEmpty;
  bool get _isAudio => _type == 'AUDIO';
  bool get _isVideo =>
      _type == 'LIVE_WALLPAPER' || _type == 'CHARGING_ANIMATION';

  @override
  void dispose() {
    _title.dispose();
    _tags.dispose();
    _category.dispose();
    _description.dispose();
    super.dispose();
  }

  List<String> get _extensions {
    if (_isAudio) return <String>['mp3', 'm4a', 'wav', 'ogg'];
    if (_isVideo) return <String>['mp4', 'webm'];
    return <String>['jpg', 'jpeg', 'png', 'webp'];
  }

  Future<void> _pickForSlot(String slot) async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _extensions,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() => _slotFiles[slot] = result.files.first);
  }

  Future<void> _pickSingles() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: _extensions,
      withData: true,
    );
    if (result == null) return;
    setState(() => _singles = result.files);
  }

  String get _folder {
    if (_isAudio) return 'ringtones';
    if (_isVideo) return 'videos';
    if (_type == 'WALLPAPER_24H') return '24h';
    if (_type == 'WALLPAPER_DUAL') return 'dual';
    if (_type == 'WALLPAPER_BATTERY') return 'battery';
    return 'wallpapers';
  }

  Map<String, dynamic> _baseRow(PlatformFile file) {
    return <String, dynamic>{
      'name': file.name,
      'title': _title.text.trim(),
      'tags': _tags.text.trim(),
      'category': _category.text.trim(),
      'description': _description.text.trim(),
      'contentType': _type,
      'status': 'queued',
      'size': file.size,
      'type': R2Service.guessContentType(file.name),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'scheduledDate': _scheduled == null
          ? null
          : DateFormat('yyyy-MM-dd').format(_scheduled!),
      'source': 'zedge-studio-app',
    };
  }

  Future<void> _submit() async {
    final AppState state = context.read<AppState>();
    setState(() => _busy = true);
    try {
      if (_isSet) {
        if (_slotFiles.isEmpty) throw Exception('pick at least one slot image');
        final Map<String, String> files = <String, String>{};
        int index = 0;
        for (final MapEntry<String, PlatformFile> entry in _slotFiles.entries) {
          index++;
          setState(() => _progress =
              'Uploading ${entry.key} ($index/${_slotFiles.length})');
          files[entry.key] = await _upload(entry.value);
        }
        final PlatformFile first = _slotFiles.values.first;
        final Map<String, dynamic> row = _baseRow(first)
          ..['files'] = files
          ..['fileUrl'] = files.values.first
          ..['thumbUrl'] = files.values.first;
        setState(() => _progress = 'Writing queue row');
        await state.addQueueItem(row);
      } else {
        if (_singles.isEmpty) throw Exception('pick at least one file');
        for (int i = 0; i < _singles.length; i++) {
          final PlatformFile file = _singles[i];
          setState(() =>
              _progress = 'Uploading ${i + 1}/${_singles.length}: ${file.name}');
          final String url = await _upload(file);
          final Map<String, dynamic> row = _baseRow(file)
            ..['fileUrl'] = url
            ..['thumbUrl'] = _isAudio ? '' : url
            ..['isMp3'] = R2Service.isAudioName(file.name);
          if (_singles.length > 1 && _title.text.trim().isNotEmpty) {
            row['title'] = '${_title.text.trim()} ${i + 1}';
          }
          await state.addQueueItem(row);
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Added to the upload queue')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $error')),
      );
    } finally {
      if (mounted) setState(() {
        _busy = false;
        _progress = '';
      });
    }
  }

  Future<String> _upload(PlatformFile file) async {
    final Uint8List? bytes = file.bytes;
    if (bytes == null) throw Exception('could not read ${file.name}');
    return R2Service.upload(
      bytes: bytes,
      key: R2Service.buildKey(_folder, file.name),
      contentType: R2Service.guessContentType(file.name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: 620,
        height: (screen.height * 0.86).clamp(420.0, 760.0),
        child: Column(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.fromLTRB(22, 18, 12, 18),
              decoration: const BoxDecoration(gradient: Zc.headerGradient),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.cloud_upload_rounded, color: Zc.gold),
                  const SizedBox(width: 10),
                  const Text(
                    'Upload to queue',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(22),
                children: <Widget>[
                  DropdownButtonFormField<String>(
                    value: _type,
                    decoration: const InputDecoration(labelText: 'CONTENT TYPE'),
                    items: kTypeLabels.entries
                        .where((MapEntry<String, String> entry) =>
                            entry.key != 'RINGTONE')
                        .map(
                          (MapEntry<String, String> entry) =>
                              DropdownMenuItem<String>(
                            value: entry.key,
                            child: Row(
                              children: <Widget>[
                                Icon(Zc.typeIcon(entry.key),
                                    size: 15, color: Zc.goldDeep),
                                const SizedBox(width: 8),
                                Text(entry.value),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (String? value) {
                            if (value == null) return;
                            setState(() {
                              _type = value;
                              _slotFiles.clear();
                              _singles = <PlatformFile>[];
                            });
                          },
                  ),
                  const SizedBox(height: 16),
                  if (_isSet)
                    Column(
                      children: _slots.map((String slot) {
                        final PlatformFile? file = _slotFiles[slot];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: <Widget>[
                              SizedBox(
                                width: 96,
                                child: Text(
                                  slot.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    letterSpacing: 0.9,
                                    fontWeight: FontWeight.w900,
                                    color: Zc.muted,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  file?.name ?? 'No file selected',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: file == null ? Zc.muted : Zc.ink,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed:
                                    _busy ? null : () => _pickForSlot(slot),
                                child: Text(file == null ? 'Pick' : 'Change'),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _pickSingles,
                          icon: const Icon(Icons.attach_file_rounded, size: 16),
                          label: Text(
                            _singles.isEmpty
                                ? 'Choose files'
                                : '${_singles.length} file(s) selected',
                          ),
                        ),
                        if (_singles.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 8),
                          Text(
                            _singles
                                .map((PlatformFile file) => file.name)
                                .join(', '),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Zc.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _title,
                    decoration: const InputDecoration(labelText: 'ITEM TITLE'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tags,
                    decoration: const InputDecoration(
                      labelText: 'SEARCH TAGS',
                      helperText: 'Comma separated',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _category,
                    decoration:
                        const InputDecoration(labelText: 'MAIN CATEGORY'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _description,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                        labelText: 'PUBLISHING DESCRIPTION'),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: _busy
                        ? null
                        : () async {
                            final DateTime now = DateTime.now();
                            final DateTime? picked = await showDatePicker(
                              context: context,
                              initialDate: _scheduled ?? now,
                              firstDate: now.subtract(const Duration(days: 1)),
                              lastDate: DateTime(now.year + 3),
                            );
                            if (picked != null) {
                              setState(() => _scheduled = picked);
                            }
                          },
                    borderRadius: BorderRadius.circular(14),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                          labelText: 'SCHEDULED UPLOAD DATE'),
                      child: Text(
                        _scheduled == null
                            ? 'Not scheduled (bot picks it up next)'
                            : DateFormat('dd MMM yyyy').format(_scheduled!),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Zc.line)),
              ),
              child: Row(
                children: <Widget>[
                  if (_busy)
                    Expanded(
                      child: Row(
                        children: <Widget>[
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _progress,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Zc.inkSoft,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    const Spacer(),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _busy ? null : _submit,
                    icon: const Icon(Icons.rocket_launch_rounded, size: 16),
                    label: const Text('Upload & queue'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
