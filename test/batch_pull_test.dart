import 'package:ai_image_studio/browser/image_prompt_service.dart';
import 'package:ai_image_studio/screens/batch_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('web prompt lands in Batch prompts once', (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: BatchScreen()));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    PromptListBridge.instance.add(['A red fox in snow']);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // ignore: avoid_print
    print('fields: ${tester.widgetList<TextField>(find.byType(TextField, skipOffstage: false)).map((t) => t.controller?.text).toList()}');
    final n = tester
        .widgetList<TextField>(find.byType(TextField, skipOffstage: false))
        .where((t) => t.controller?.text == 'A red fox in snow')
        .length;
    // ignore: avoid_print
    print('rows with prompt: $n, pending: ${PromptListBridge.instance.pending.value}');
    expect(n, 1);
  });
}
