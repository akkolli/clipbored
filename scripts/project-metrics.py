#!/usr/bin/env python3
"""Report physical Swift lines and logical file sizes, without external tools."""

import argparse
import json
import os
from pathlib import Path

GENERATED = {".git", ".build", "build", ".swiftpm"}


def files_under(root, exclude=()):
    for directory, names, files in os.walk(root):
        names[:] = [name for name in names if name not in exclude]
        for name in files:
            path = Path(directory) / name
            if not path.is_symlink():
                yield path


def size(root):
    return sum(path.stat().st_size for path in files_under(root))


def code_metrics(files, extensions=(".swift",)):
    code = [path for path in files if path.suffix in extensions]
    lines = [line for path in code for line in path.read_text().splitlines()]
    return {"files": len(code), "lines": len(lines),
            "nonblank_lines": sum(bool(line.strip()) for line in lines),
            "bytes": sum(path.stat().st_size for path in code)}


def measure(root):
    files = list(files_under(root, GENERATED))
    executable = root / "build/Goldfish.app/Contents/MacOS/Goldfish"
    return {
        "app_swift": code_metrics(path for path in files if path.is_relative_to(root / "Sources")),
        "test_swift": code_metrics(path for path in files if path.is_relative_to(root / "Tests")),
        "tooling": code_metrics((path for path in files if path.is_relative_to(root / "scripts")
                                 or path == root / "Package.swift"), (".swift", ".sh", ".py")),
        "project_bytes_excluding_generated": sum(path.stat().st_size for path in files),
        "app_bundle_bytes": size(root / "build/Goldfish.app"),
        "executable_bytes": executable.stat().st_size if executable.exists() else 0,
        "generated_bytes": {name: size(root / name) for name in sorted(GENERATED)},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    report = measure(args.root.resolve())
    if args.json:
        print(json.dumps(report, indent=2))
        return
    for key, title in [("app_swift", "App Swift"), ("test_swift", "Test Swift"), ("tooling", "Build/tools")]:
        group = report[key]
        print(f"{title}: {group['lines']:,} lines ({group['nonblank_lines']:,} nonblank), {group['files']} files")
    for key, title in [("project_bytes_excluding_generated", "Project excluding generated files"),
                       ("app_bundle_bytes", "Built app"), ("executable_bytes", "Executable")]:
        print(f"{title}: {report[key]:,} bytes ({report[key] / 1_000_000:.2f} MB)")
    for name, value in report["generated_bytes"].items():
        print(f"{name}: {value / 1_000_000:.2f} MB")
    print("Lines include comments and blanks. Sizes are logical bytes, excluding symlink duplicates.")


if __name__ == "__main__":
    main()
