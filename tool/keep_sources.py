"""Protect the hand written sources from `flutter create`.

`flutter create .` regenerates the native shells, but it also overwrites
pubspec.yaml and lib/main.dart with its counter-app template. CI therefore
runs:

    python tool/keep_sources.py save      # before flutter create
    python tool/keep_sources.py restore   # after flutter create

Restores are merges (nothing is deleted), so the freshly generated android/
and windows/ folders stay intact and no file is locked on Windows runners.
"""
import os
import shutil
import sys
import tempfile

KEEP = [
    "pubspec.yaml",
    "analysis_options.yaml",
    "README.md",
    "lib",
    "assets",
    "tool",
    "installer",
]

STASH = os.path.join(tempfile.gettempdir(), "zedge_studio_keep")


def copy(src, dst):
    if os.path.isdir(src):
        shutil.copytree(src, dst, dirs_exist_ok=True)
    else:
        parent = os.path.dirname(dst)
        if parent:
            os.makedirs(parent, exist_ok=True)
        shutil.copy2(src, dst)


def save():
    if os.path.isdir(STASH):
        shutil.rmtree(STASH, ignore_errors=True)
    os.makedirs(STASH, exist_ok=True)
    for item in KEEP:
        if os.path.exists(item):
            copy(item, os.path.join(STASH, item))
            print("[keep] saved %s" % item)
    print("[keep] stash: %s" % STASH)


def restore():
    if not os.path.isdir(STASH):
        raise SystemExit("[keep] nothing saved at %s" % STASH)
    for item in KEEP:
        src = os.path.join(STASH, item)
        if os.path.exists(src):
            copy(src, item)
            print("[keep] restored %s" % item)


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "save":
        save()
    elif mode == "restore":
        restore()
    else:
        raise SystemExit("usage: keep_sources.py [save|restore]")
