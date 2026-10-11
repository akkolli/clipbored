#!/usr/bin/env python3
"""Check portable local file references in maintained Markdown."""
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote

root = Path(__file__).resolve().parent.parent
failed = []
for name in subprocess.check_output(['git', '-C', str(root), 'ls-files', '--cached', '--others', '--exclude-standard'], text=True).splitlines():
    path = root / name
    if path.suffix != '.md' or not path.is_file():
        continue
    for line, text in enumerate(path.read_text().splitlines(), 1):
        for target in re.findall(r'\]\(([^)]+)\)', text):
            if '://' in target or target.startswith(('app:', 'mailto:', '#')):
                continue
            target = unquote(target.split('#', 1)[0])
            if target.startswith('/') or not (path.parent / target).is_file():
                failed.append(f'{name}:{line}: invalid or nonportable reference: {target}')
if failed:
    sys.exit('\n'.join(failed))
print('Documentation file references passed.')
