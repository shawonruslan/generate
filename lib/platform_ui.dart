import 'dart:io';

/// Tests / screenshots can force the Android UI on a desktop host.
bool? debugForceAndroid;

bool get isAndroidUi => debugForceAndroid ?? Platform.isAndroid;
