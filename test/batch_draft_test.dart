import 'package:ai_image_studio/browser/image_prompt_service.dart';
import 'package:ai_image_studio/screens/batch_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<String> texts(WidgetTester t) => t
    .widgetList<TextField>(find.byType(TextField, skipOffstage: false))
    .map((x) => x.controller?.text ?? '')
    .where((x) => x.startsWith('P'))
    .toList();

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('prompts survive leaving Batch and re-add works',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PromptListBridge.instance.add(['P one', 'P two']);
    await tester.pumpWidget(const MaterialApp(home: BatchScreen()));
    await settle(tester);
    expect(texts(tester), ['P one', 'P two']);
    // Leave the Batch screen (tab switch / settings) -> disposed.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await settle(tester);
    // Come back: rows are restored from the draft.
    await tester.pumpWidget(const MaterialApp(home: BatchScreen()));
    await settle(tester);
    expect(texts(tester), ['P one', 'P two']);
    // "Add again" from Image to Prompt: no duplicate, new one appended.
    PromptListBridge.instance.add(['P two', 'P three']);
    await settle(tester);
    expect(texts(tester), ['P one', 'P two', 'P three']);
    final p = await SharedPreferences.getInstance();
    expect(p.getString('batch_prompt_draft_v1'), contains('P three'));
  });
}
