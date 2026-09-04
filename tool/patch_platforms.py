#!/usr/bin/env python3
"""Zedge Studio platform patcher.

The repo intentionally does NOT commit the generated android/ and windows/
folders. CI runs `flutter create` to generate them, then this script applies
every app specific tweak (permissions, app name, exe name, window size,
release signing). It never fails the build - it prints warnings instead.

Usage: python tool/patch_platforms.py [android|android-signing|windows|all]
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP_NAME = "Zedge Studio"
BINARY = "ZedgeStudio"
WINDOW_W, WINDOW_H = 1400, 920


def read(path):
    try:
        return path.read_text(encoding="utf-8")
    except Exception:
        return None


def save(path, text, label):
    path.write_text(text, encoding="utf-8")
    print("  patched %s (%s)" % (path.relative_to(ROOT), label))


def patch_android():
    print("[android] manifest + gradle")
    man = ROOT / "android/app/src/main/AndroidManifest.xml"
    text = read(man)
    if text is None:
        print("  ! AndroidManifest.xml not found - did flutter create run?")
        return
    perms = [
        "android.permission.INTERNET",
        "android.permission.ACCESS_NETWORK_STATE",
        "android.permission.READ_MEDIA_IMAGES",
        "android.permission.READ_MEDIA_AUDIO",
        "android.permission.READ_MEDIA_VIDEO",
    ]
    missing = [p for p in perms if p not in text]
    if missing:
        block = "".join('\n    <uses-permission android:name="%s"/>' % p for p in missing)
        text = re.sub(r"(<manifest[^>]*>)", lambda m: m.group(1) + block, text, count=1)
    text = re.sub(r'android:label="[^"]*"', 'android:label="%s"' % APP_NAME, text, count=1)
    save(man, text, "internet + media permissions, app label")

    for name in ("build.gradle.kts", "build.gradle"):
        gradle = ROOT / "android/app" / name
        text = read(gradle)
        if text is None:
            continue
        original = text
        text = re.sub(r"minSdk(?:Version)?\s*=?\s*flutter\.minSdkVersion", "minSdk = 23", text)
        text = re.sub(r"minSdk(?:Version)?\s*=\s*\d+", "minSdk = 23", text)
        if text != original:
            save(gradle, text, "minSdk 23")
        break


def patch_android_signing():
    print("[android-signing] release keystore")
    if not (ROOT / "android/key.properties").exists():
        print("  no android/key.properties - release APK keeps the Flutter debug key")
        return
    kts = ROOT / "android/app/build.gradle.kts"
    groovy = ROOT / "android/app/build.gradle"
    if read(kts) is not None:
        text = read(kts)
        if "zedgeKeystore" in text:
            print("  already patched")
            return
        header = (
            "import java.util.Properties\n"
            "import java.io.FileInputStream\n\n"
            "val zedgeKeystore = Properties()\n"
            'val zedgeKeystoreFile = rootProject.file("key.properties")\n'
            "if (zedgeKeystoreFile.exists()) "
            "{ zedgeKeystore.load(FileInputStream(zedgeKeystoreFile)) }\n\n"
        )
        signing = (
            "    signingConfigs {\n"
            '        create("release") {\n'
            '            keyAlias = zedgeKeystore.getProperty("keyAlias")\n'
            '            keyPassword = zedgeKeystore.getProperty("keyPassword")\n'
            '            storeFile = zedgeKeystore.getProperty("storeFile")'
            "?.let { file(it) }\n"
            '            storePassword = zedgeKeystore.getProperty("storePassword")\n'
            "        }\n"
            "    }\n"
        )
        text = header + text
        text = re.sub(r"\n(\s*)buildTypes\s*\{", "\n" + signing + "\n" + r"\1buildTypes {", text, count=1)
        text = text.replace('signingConfig = signingConfigs.getByName("debug")',
                            'signingConfig = signingConfigs.getByName("release")')
        save(kts, text, "kotlin dsl release signing")
        return
    text = read(groovy)
    if text is None:
        print("  ! no app build.gradle found")
        return
    if "zedgeKeystore" in text:
        print("  already patched")
        return
    header = (
        "def zedgeKeystore = new Properties()\n"
        'def zedgeKeystoreFile = rootProject.file("key.properties")\n'
        "if (zedgeKeystoreFile.exists()) "
        '{ zedgeKeystoreFile.withReader("UTF-8") { zedgeKeystore.load(it) } }\n\n'
    )
    signing = (
        "    signingConfigs {\n"
        "        release {\n"
        '            keyAlias zedgeKeystore["keyAlias"]\n'
        '            keyPassword zedgeKeystore["keyPassword"]\n'
        '            storeFile zedgeKeystore["storeFile"] '
        '? file(zedgeKeystore["storeFile"]) : null\n'
        '            storePassword zedgeKeystore["storePassword"]\n'
        "        }\n"
        "    }\n"
    )
    text = header + text
    text = re.sub(r"\n(\s*)buildTypes\s*\{", "\n" + signing + "\n" + r"\1buildTypes {", text, count=1)
    text = text.replace("signingConfig signingConfigs.debug", "signingConfig signingConfigs.release")
    save(groovy, text, "groovy release signing")


def patch_windows():
    print("[windows] exe name, window title, size, metadata")
    cmake = ROOT / "windows/CMakeLists.txt"
    text = read(cmake)
    if text is None:
        print("  ! windows/CMakeLists.txt not found - did flutter create run?")
        return
    text = re.sub(r'set\(BINARY_NAME "[^"]*"\)', 'set(BINARY_NAME "%s")' % BINARY, text, count=1)
    save(cmake, text, "binary name %s.exe" % BINARY)

    main_cpp = ROOT / "windows/runner/main.cpp"
    text = read(main_cpp)
    if text is not None:
        text = re.sub(r'window\.Create\(L"[^"]*"', 'window.Create(L"%s"' % APP_NAME, text, count=1)
        text = re.sub(r"Win32Window::Size size\(\d+,\s*\d+\)",
                      "Win32Window::Size size(%d, %d)" % (WINDOW_W, WINDOW_H), text, count=1)
        save(main_cpp, text, "title + default window size")

    rc = ROOT / "windows/runner/Runner.rc"
    text = read(rc)
    if text is not None:
        text = text.replace('"com.example"', '"Zedge Automation"')
        text = text.replace('"zedge_studio"', '"%s"' % APP_NAME)
        text = text.replace('"A new Flutter project."',
                            '"Zedge Studio - upload automation control room"')
        text = text.replace('"zedge_studio.exe"', '"%s.exe"' % BINARY)
        save(rc, text, "exe version metadata")


def main():
    mode = (sys.argv[1] if len(sys.argv) > 1 else "all").lower()
    if mode in ("android", "all"):
        patch_android()
    if mode in ("android-signing", "all"):
        patch_android_signing()
    if mode in ("windows", "all"):
        patch_windows()
    print("platform patch done (%s)" % mode)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print("platform patch warning: %s" % exc)
