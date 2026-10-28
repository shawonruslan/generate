import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_image_studio/main.dart';

void main() {
  testWidgets('App launches with title and generate button',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const AiImageStudioApp());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('AI Image Studio'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
