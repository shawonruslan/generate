"""Build-patch integration check, runnable without Flutter or the Android SDK."""
import pathlib
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[2]
ANDROID = '{http://schemas.android.com/apk/res/android}'


class RotationPackagingTest(unittest.TestCase):
    def test_patched_activity_is_copied_and_manifest_is_idempotent(self):
        with tempfile.TemporaryDirectory() as d:
            root = pathlib.Path(d)
            files = {
                'android/app/src/main/kotlin/example/MainActivity.kt':
                    'package example\nclass MainActivity\n',
                'android/app/src/main/AndroidManifest.xml':
                    '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
                    '<application /></manifest>',
                'android/build.gradle.kts':
                    'allprojects { repositories {\n        mavenCentral()\n} }\n',
                'android/settings.gradle.kts':
                    'plugins { id("org.jetbrains.kotlin.android") version "2.1.0" }\n',
                'android/app/build.gradle.kts':
                    'android {\n    defaultConfig {\n'
                    '        minSdk = flutter.minSdkVersion\n    }\n}\n',
                'lib/browser/overlay_script.dart': "const overlay = r'''// test overlay''';\n",
            }
            for name, text in files.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text)
            # Expand application to match Flutter's generated manifest form.
            manifest = root / 'android/app/src/main/AndroidManifest.xml'
            manifest.write_text(manifest.read_text().replace(
                '<application />', '<application></application>'))
            command = [sys.executable, str(ROOT / 'android_native/patch_android.py')]
            subprocess.run(command, cwd=root, check=True, capture_output=True)
            first = manifest.read_text()
            subprocess.run(command, cwd=root, check=True, capture_output=True)
            self.assertEqual(first, manifest.read_text())
            tree = ET.fromstring(first)
            activities = [a for a in tree.findall('./application/activity')
                          if a.get(ANDROID + 'name') == '.StableAudioWebViewActivity']
            self.assertEqual(len(activities), 1)
            self.assertIn('orientation', activities[0].get(ANDROID + 'configChanges'))
            self.assertTrue(any(p.get(ANDROID + 'name') == 'android.permission.INTERNET'
                                for p in tree.findall('uses-permission')))
            native = root / 'android/app/src/main/kotlin/example/StableAudioWebViewActivity.kt'
            expected = (ROOT / 'android_native/kotlin/StableAudioWebViewActivity.kt').read_text()
            self.assertEqual(native.read_text(), expected.replace(
                'package com.aistudio.ai_image_studio', 'package example', 1))


if __name__ == '__main__':
    unittest.main()
