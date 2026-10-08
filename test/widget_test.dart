import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_image_studio/main.dart';

void main() {
  testWidgets('App launches with title and generate button',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AiImageStudioApp());
    await tester.pumpAndSettle();
    expect(find.text('AI Image Studio'), findsOneWidget);
    expect(find.text('Generate image'), findsOneWidget);
  });
}
