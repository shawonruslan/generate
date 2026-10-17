#!/usr/bin/env python3
"""Run this after filling in your values: python3 check_config.py
It lists every CONFIG placeholder that is still unfilled and checks that the
Firebase / R2 URLs are identical across the panel, Android app and desktop app.
(The zedgeN.yml bots and generator.yml read their URLs from GitHub Secrets -
see SECRETS.txt.)"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ACCOUNTS = 4
APP = 'app/app/src/main/java/com/zedge/contentstudio/core/Core.kt'
DESK = 'desktop/lib/config/profile_data.dart'
FILES = ['index.html', 'generator.yml'] + [f'zedge{n}.yml' for n in range(1, ACCOUNTS + 1)] + [APP, DESK]
PLACEHOLDERS = re.compile(r'YOUR[-_][A-Z0-9_-]+|YOUR-SUBDOMAIN|000000000000')

bad = 0
for rel in FILES:
    p = os.path.join(HERE, rel)
    if not os.path.exists(p):
        print(f'!! missing file: {rel}'); bad += 1; continue
    for i, line in enumerate(open(p, encoding='utf-8'), 1):
        if PLACEHOLDERS.search(line) and 'OPTIONAL' not in line and 'CONFIG spot' not in line:
            print(f'UNFILLED  {rel}:{i}: {line.strip()[:110]}'); bad += 1

def grab(rel, pattern):
    p = os.path.join(HERE, rel)
    return re.findall(pattern, open(p, encoding='utf-8').read()) if os.path.exists(p) else []

db_panel = grab('index.html', r'databaseURL:\s*"([^"]+)"')
db_app = grab(APP, r'Account\("zedge\d", "ZEDGE\d", "([^"]+)"')
db_desk = grab(DESK, r"databaseURL:\s*'([^']+)'")
for name, lst in (('index.html', db_panel), (APP, db_app), (DESK, db_desk)):
    if len(lst) != ACCOUNTS:
        print(f'COUNT     {name}: found {len(lst)} account URL(s), expected {ACCOUNTS}'); bad += 1
for n in range(min(len(db_panel), len(db_app), len(db_desk))):
    vals = {db_panel[n], db_app[n], db_desk[n]}
    if len(vals) != 1:
        print(f'MISMATCH  Firebase URL for account {n + 1} differs between files: {vals}'); bad += 1
if len(set(db_panel)) != len(db_panel):
    print('DUPLICATE two accounts use the same Firebase URL in index.html'); bad += 1

r2 = set(grab('index.html', r'R2_WORKER_URL = "([^"]+)"') + grab(APP, r'R2_WORKER_URL = "([^"]+)"')
         + grab(DESK, r"r2WorkerUrl:\s*'([^']+)'"))
if len(r2) != 1:
    print(f'MISMATCH  R2 worker URL differs between files: {r2}'); bad += 1

print('\nOK - all config filled and consistent.' if bad == 0 else f'\n{bad} problem(s) found - fix the lines above.')
sys.exit(1 if bad else 0)
