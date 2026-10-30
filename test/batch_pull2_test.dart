import 'package:ai_image_studio/browser/image_prompt_service.dart';
import 'package:ai_image_studio/screens/batch_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<int> rows(WidgetTester t, String p) async {
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  final all = t.widgetList<TextField>(find.byType(TextField, skipOffstage: false))
      .map((x) => x.controller?.text).toList();
  // ignore: avoid_print
  print('fields: $all');
  return all.where((x) => x == p).length;
}

void main() {
  testWidgets('saved pending prompt from last run + new add', (tester) async {
    // Last run left one pending prompt in prefs.
    SharedPreferences.setMockInitialValues({'pending_batch_prompts': <String>['P']});
    FlutterSecureStorage.setMockInitialValues({});
    // Service loads (as BrowserScreen does), and a prompt is added right away
    final f = ImagePromptService.instance.load();
    PromptListBridge.instance.add(['P']); // auto-add
    PromptListBridge.instance.add(['P']); // "Add to Prompts list" click
    await f;
    // ignore: avoid_print
    print('pending before batch: ${PromptListBridge.instance.pending.value}');
    expect(PromptListBridge.instance.pending.value, ['P']);
    await tester.pumpWidget(const MaterialApp(home: BatchScreen()));
    final n = await rows(tester, 'P');
    expect(n, 1);
  });
}
