import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_image_studio/distribute.dart';
import 'package:ai_image_studio/ringtone/ringtone_service.dart';
import 'package:ai_image_studio/ringtone/stable_audio.dart';
import 'package:ai_image_studio/screens/ringtone_screen.dart';

void main() {
  testWidgets('studio opens and mode presets update', (t) async {
    final dir = Directory.systemTemp.createTempSync('studio-ui-');
    final s = RingtoneService(
        persist: false,
        dataDir: () async => dir,
        stableAudio: StableAudioClient(store: MemoryStableAudioStore()),
        distLoader: () async => const DistConfig(r2WorkerUrl: '', accounts: []),
        ffmpegFinder: (_) async => null);
    await t.runAsync(() => s.init());
    await t.pumpWidget(MaterialApp(home: RingtoneScreen(service: s)));
    await t.pumpAndSettle();
    expect(find.text('Ringtone Studio'), findsOneWidget);
    expect(find.text('Create sounds'), findsOneWidget);
    await t.tap(find.text('Ringtone').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Notification').last);
    await t.pumpAndSettle();
    expect(s.config.lengthSeconds, 3);
    expect(s.config.audioShape, 'oneshot');
    await t.pumpWidget(const SizedBox());
    dir.deleteSync(recursive: true);
  });
}
