import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('build_state', Path(__file__).resolve().parents[2] / 'scripts/build-state.py')
state = importlib.util.module_from_spec(spec)
spec.loader.exec_module(state)


class BuildStateTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name) / 'repo'
        self.root.mkdir()
        self.git('init', '-q', '-b', 'main')
        self.info = self.root / 'Sources/Goldfish/resources/Info.plist'
        self.info.parent.mkdir(parents=True)
        self.info.write_bytes(plistlib.dumps(dict(CFBundleName='Goldfish', CFBundleDisplayName='Goldfish',
                                                 CFBundleExecutable='Goldfish', CFBundleIdentifier='com.local.clipbored')))
        config = self.root / 'Sources/Goldfish/config/AppConfiguration.swift'
        config.parent.mkdir()
        config.write_text('static let appName = "Goldfish"')
        (self.root / 'Package.swift').write_text('name: "Goldfish", name: "GoldfishTests"')
        self.commit()

    def git(self, *args):
        subprocess.run(['git', '-C', str(self.root), *args], check=True, capture_output=True)

    def commit(self):
        self.git('add', '-A')
        self.git('-c', 'user.name=Build Test', '-c', 'user.email=build@example.invalid', 'commit', '-qm', 'fixture')

    def worktree(self):
        path = Path(self.directory.name) / 'worktree'
        self.git('worktree', 'add', '-q', '--detach', str(path), 'HEAD')
        return path

    def test_committed_snapshot_and_source_changes(self):
        recorded = state.snapshot(self.root)
        self.assertFalse(recorded['dirty'])
        state.verify(self.root, recorded)
        (self.root / 'new.swift').write_text('new code')
        with self.assertRaisesRegex(ValueError, 'Commit'): state.snapshot(self.root)
        preview = state.snapshot(self.root, allow_dirty=True)
        self.assertTrue(preview['dirty'])
        (self.root / 'new.swift').write_text('changed code')
        with self.assertRaisesRegex(ValueError, 'sourceHash'): state.verify(self.root, preview)

    def test_stale_worktree_and_uncommitted_main_are_rejected(self):
        other = self.worktree()
        (self.root / 'new.swift').write_text('new code')
        with self.assertRaisesRegex(ValueError, 'Main has uncommitted'): state.snapshot(other, allow_dirty=True)
        self.commit()
        with self.assertRaisesRegex(ValueError, 'Stale checkout'): state.snapshot(other)

    def test_old_branding_and_package_names_are_rejected(self):
        for key in ('CFBundleName', 'CFBundleDisplayName', 'CFBundleExecutable'):
            info = plistlib.loads(self.info.read_bytes())
            info[key] = 'ClipBored'
            with self.assertRaisesRegex(ValueError, key): state.validate_name(info)
        (self.root / 'Package.swift').write_text('name: "ClipBored"')
        with self.assertRaisesRegex(ValueError, 'Package'): state.snapshot(self.root, allow_dirty=True)

    def test_install_requires_provenance_clean_main_and_matching_source(self):
        app = Path(self.directory.name) / 'Goldfish.app'
        resources = app / 'Contents/Resources'
        resources.mkdir(parents=True)
        (app / 'Contents/Info.plist').write_bytes(self.info.read_bytes())
        with self.assertRaisesRegex(ValueError, 'no build provenance'): state.installable(self.root, app)
        recorded = state.snapshot(self.root)
        manifest = resources / 'BuildInfo.json'
        manifest.write_text(json.dumps(recorded))
        state.installable(self.root, app)
        recorded['dirty'] = True
        manifest.write_text(json.dumps(recorded))
        with self.assertRaisesRegex(ValueError, 'clean build'): state.installable(self.root, app)
        recorded['dirty'] = False
        recorded['sourceHash'] = 'wrong'
        manifest.write_text(json.dumps(recorded))
        with self.assertRaisesRegex(ValueError, 'sourceHash'): state.installable(self.root, app)

    def test_build_from_another_checkout_is_rejected(self):
        recorded = state.snapshot(self.root)
        with self.assertRaisesRegex(ValueError, 'checkout'): state.verify(self.worktree(), recorded)
