"""tools/install_addon.ps1 puts the addon archive in a game folder and keeps the old addon and every settings file safe.

Runs Windows PowerShell 5.1 against a temporary fake game folder and backup folder only, never a real game folder.
The four drive-root tests map a free drive letter, Z down to G, to a temporary folder with subst while they run. A
run stopped early, by Ctrl+C or a kill, can leave that letter mapped until you run subst <letter>: /d or sign out.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'tools/install_addon.ps1'
POWERSHELL = shutil.which('powershell.exe')
NEW = {'vantage.lua': b"addon.name = 'vantage';\naddon.version = '1.0.0';\n", 'core/store.lua': b'return {};\n',
       'ui/hud.lua': b'return { new = true };\n'}
OLD = {'vantage.lua': b"addon.version = '0.9.0';\n", 'core/store.lua': b'return { old = true };\n',
       'core/native_status_ui.lua': b'return {};\n'}
SETTINGS = {'config/addons/vantage/Name_1/settings.json': b'{"locked":true}\n',
            'config/addons/vantage/Name_2/settings.json': b'{"locked":false}\n',
            'config/addons/vantage/profiles.json': b'{}\n',
            'config/addons/vantage/shared_layout.json': b'{"layout":true}\n'}


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def tree(folder):
    folder = Path(folder)
    return {path.relative_to(folder).as_posix(): path.read_bytes() for path in folder.rglob('*') if path.is_file()}


@unittest.skipUnless(os.name == 'nt' and POWERSHELL, 'needs Windows PowerShell')
class InstallAddonTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix='vantage_install_')
        root = Path(self.work.name)
        self.game, self.backups, self.zip = root / 'game', root / 'backups', root / 'vantage-1.0.0-addon.zip'
        self.backups.mkdir()
        self.write(self.game, {'addons/other/other.lua': b'return {};\n', 'scripts/default.txt': b'/addon load vantage\n',
                               'config/boot/launcher.ini': b'[x]\n'})
        self.make_zip(NEW)
        self.kept = {name: data for name, data in tree(self.game).items() if not name.startswith('addons/vantage/')}

    def tearDown(self):
        # Nothing outside addons/vantage changed: not the launcher files or the startup script.
        now = {name: data for name, data in tree(self.game).items() if not name.startswith('addons/vantage/')}
        self.assertEqual(now, self.kept)
        self.assertEqual(list(self.backups.glob('vantage-addon-staging-*')), [])
        self.work.cleanup()

    def write(self, folder, files):
        for name, data in files.items():
            path = Path(folder) / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)

    def make_zip(self, files, names=None):
        with zipfile.ZipFile(self.zip, 'w', zipfile.ZIP_DEFLATED) as archive:
            for name, data in files.items():
                archive.writestr((names or {}).get(name, 'addons/vantage/' + name), data)
            for name in ('LICENSE', 'README.md', 'docs/GUIDE.md'):
                archive.writestr(name, b'document\n')

    def install(self, *extra, sha=None, backups=None, game=None, cwd=None):
        # Windows PowerShell builds its own module path when none is set. One left by PowerShell 7, the shell of
        # GitHub's Windows runner, points it at modules it can't load, and Get-FileHash goes missing.
        environment = {name: value for name, value in os.environ.items() if name.upper() != 'PSMODULEPATH'}
        result = subprocess.run([POWERSHELL, '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File',
                                 str(SCRIPT), '-Zip', str(self.zip), '-Sha256', sha or digest(self.zip).upper(),
                                 '-Game', str(game or self.game), '-BackupParent', str(backups or self.backups), *extra],
                                capture_output=True, text=True, timeout=300, env=environment, cwd=cwd)
        receipts = sorted(Path(backups or self.backups).glob('vantage-addon-install-*.json'))
        receipt = json.loads(receipts[-1].read_text(encoding='utf-8')) if receipts else None
        return result.returncode, result.stdout + result.stderr, receipt

    def drive(self, folder):
        # A drive whose root is the folder given: subst maps a free letter to it until the test ends.
        for letter in 'ZYXWVUTSRQPONMLKJIHG':
            if not os.path.exists(letter + ':\\') and subprocess.run(['subst', letter + ':', str(folder)],
                                                                     capture_output=True).returncode == 0:
                self.addCleanup(subprocess.run, ['subst', letter + ':', '/d'], capture_output=True)
                return Path(letter + ':\\')
        self.skipTest('no free drive letter for subst')

    def test_fresh_install(self):
        code, out, receipt = self.install()
        self.assertEqual(code, 0, out)
        self.assertEqual(tree(self.game / 'addons/vantage'), NEW)
        self.assertEqual(receipt['result'], 'installed')
        self.assertIsNone(receipt['backup'])
        self.assertEqual(receipt['zip_sha256'], digest(self.zip))
        self.assertEqual(receipt['files'], {name: hashlib.sha256(data).hexdigest() for name, data in NEW.items()})
        self.assertEqual(receipt['settings_before'], {'config/addons/vantage': 'absent'})
        self.assertEqual(receipt['settings_after'], receipt['settings_before'])
        self.assertEqual(list(self.backups.glob('vantage-addon-backup-*')), [])

    def test_upgrade_moves_the_old_addon_to_a_dated_backup(self):
        self.write(self.game / 'addons/vantage', OLD)
        self.write(self.game, SETTINGS)
        self.kept = {name: data for name, data in tree(self.game).items() if not name.startswith('addons/vantage/')}
        code, out, receipt = self.install()
        self.assertEqual(code, 0, out)
        self.assertEqual(tree(self.game / 'addons/vantage'), NEW)
        backups = list(self.backups.glob('vantage-addon-backup-*'))
        self.assertEqual(len(backups), 1)
        self.assertRegex(backups[0].name, r'^vantage-addon-backup-\d{8}T\d{9}Z$')
        self.assertEqual(tree(backups[0]), OLD)
        self.assertEqual(Path(receipt['backup']), backups[0])
        self.assertIn('The old addon is in ' + str(backups[0]), out)
        # Every file in the settings folders, not only each settings.json: the profiles and the shared layout too.
        settings = {name: hashlib.sha256(data).hexdigest() for name, data in SETTINGS.items()}
        self.assertEqual(receipt['settings_before'], settings)
        self.assertEqual(receipt['settings_after'], settings)

    def test_wrong_hash_changes_nothing(self):
        self.write(self.game / 'addons/vantage', OLD)
        code, out, receipt = self.install(sha='0' * 64)
        self.assertEqual(code, 1, out)
        self.assertIn('Not installed: the archive SHA-256 is ' + digest(self.zip), out)
        self.assertEqual(tree(self.game / 'addons/vantage'), OLD)
        self.assertEqual(list(self.backups.glob('vantage-addon-backup-*')), [])
        self.assertEqual(receipt['result'], 'refused')

    def test_a_failure_after_the_copy_puts_the_old_addon_back(self):
        self.write(self.game / 'addons/vantage', OLD)
        self.write(self.game, SETTINGS)
        self.kept = {name: data for name, data in tree(self.game).items() if not name.startswith('addons/vantage/')}
        code, out, receipt = self.install('-TestFailure', 'after_copy')
        self.assertEqual(code, 2, out)
        self.assertEqual(tree(self.game / 'addons/vantage'), OLD)
        self.assertEqual(receipt['result'], 'failed, put back')
        self.assertEqual(receipt['reason'], 'test failure after the copy')
        self.assertEqual(tree(receipt['failed_copy']), NEW)
        self.assertFalse(Path(receipt['backup']).exists())
        self.assertEqual(receipt['settings_after'], receipt['settings_before'])
        self.assertIn('The old addon is back in', out)

    def test_a_failed_fresh_install_leaves_no_addon(self):
        code, out, receipt = self.install('-TestFailure', 'after_copy')
        self.assertEqual(code, 2, out)
        self.assertFalse((self.game / 'addons/vantage').exists())
        self.assertTrue(Path(receipt['failed_copy']).is_relative_to(self.backups))

    def test_a_fresh_install_that_cannot_be_undone_names_the_partial_copy(self):
        code, out, receipt = self.install('-TestFailure', 'after_copy_held')
        self.assertEqual(code, 3, out)
        self.assertEqual(receipt['result'], 'failed, not put back')
        self.assertIsNone(receipt['backup'])
        self.assertNotIn('The old addon is in', out)
        self.assertIn('There was no old addon. The partial copy is still in ' + str(self.game / 'addons' / 'vantage'), out)
        self.assertEqual(tree(self.game / 'addons/vantage'), NEW)

    def test_installs_while_the_game_runs(self):
        # The game can stay open: the script looks for no game process, and its last line says to reload the addon in
        # game right away, before /vg. A loaded Vantage reads some files only on first use, such as the settings
        # window's pages, so until the reload it can load new files into its old code. Nothing says the old code
        # stays whole.
        script = SCRIPT.read_text(encoding='ascii')
        self.assertNotIn('Get-Process', script)
        self.assertNotIn('GameProcess', script)
        self.assertNotIn('keeps its old code', script)
        self.assertIn('If Vantage is loaded, run /addon reload vantage in game right after it, before you open /vg.',
                      ' '.join(script.split('#>')[0].split()))
        self.write(self.game / 'addons/vantage', OLD)
        self.write(self.game, SETTINGS)
        self.kept = {name: data for name, data in tree(self.game).items() if not name.startswith('addons/vantage/')}
        code, out, receipt = self.install()
        self.assertEqual(code, 0, out)
        self.assertEqual(receipt['result'], 'installed')
        self.assertEqual(tree(self.game / 'addons/vantage'), NEW)
        self.assertNotIn('Not installed', out)
        self.assertIn('Next: if the game is running, type /addon reload vantage in game right away, before you open /vg '
                      '(/addon load vantage if Vantage is not loaded).', out)

    def test_an_old_addon_in_use_stays_whole(self):
        # A file of the old addon held open, as a running game or another program can hold one: the old addon can't
        # be moved, so it stays where it is, whole, with nothing copied over it and nothing moved out of it.
        self.write(self.game / 'addons/vantage', OLD)
        self.write(self.game, SETTINGS)
        self.kept = {name: data for name, data in tree(self.game).items() if not name.startswith('addons/vantage/')}
        with open(self.game / 'addons/vantage/core/store.lua', 'rb'):
            code, out, receipt = self.install()
        self.assertEqual(code, 2, out)
        self.assertEqual(tree(self.game / 'addons/vantage'), OLD)
        self.assertEqual(receipt['result'], 'failed, put back')
        self.assertIsNone(receipt['backup'])
        self.assertIsNone(receipt['failed_copy'])
        self.assertEqual(list(self.backups.glob('vantage-addon-backup-*')), [])
        self.assertEqual(list(self.backups.glob('vantage-addon-failed-copy-*')), [])
        self.assertEqual(receipt['settings_after'], receipt['settings_before'])
        self.assertIn('The old addon was not moved. It is still in ' + str(self.game / 'addons' / 'vantage') + '.', out)

    def test_unsafe_archive_refused(self):
        for names in ({'ui/hud.lua': 'addons/vantage/../evil.lua'}, {'ui/hud.lua': 'addons/vantage/CORE/STORE.LUA'},
                      {'vantage.lua': 'addons/other/vantage.lua'}):
            with self.subTest(names=names):
                self.write(self.game / 'addons/vantage', OLD)
                self.make_zip(NEW, names)
                code, out, receipt = self.install()
                self.assertEqual(code, 1, out)
                self.assertEqual(receipt['result'], 'refused')
                self.assertEqual(tree(self.game / 'addons/vantage'), OLD)
                self.assertFalse((self.game / 'evil.lua').exists())
                self.assertFalse((self.game / 'addons/evil.lua').exists())

    def test_backup_inside_the_game_folder_refused(self):
        self.write(self.game / 'addons/vantage', OLD)
        inside = self.game / 'backups'
        inside.mkdir()
        self.kept = {name: data for name, data in tree(self.game).items() if not name.startswith('addons/vantage/')}
        code, out, _ = self.install(backups=inside)
        self.assertEqual(code, 1, out)
        self.assertIn('the backup folder must be outside the game folder', out)
        self.assertEqual(tree(self.game / 'addons/vantage'), OLD)
        self.assertEqual(list(inside.iterdir()), [])

    def test_a_drive_root_as_the_backup_folder(self):
        # X:\ is outside a game folder on X:, on the same drive. Trimmed to X:, the backup path was the drive-relative
        # X:vantage-addon-backup-..., and the same-drive check refused it.
        root = self.drive(self.work.name)
        self.write(self.game / 'addons/vantage', OLD)
        code, out, receipt = self.install(game=root / 'game', backups=root)
        self.assertEqual(code, 0, out)
        self.assertEqual(tree(self.game / 'addons/vantage'), NEW)
        backups = list(root.glob('vantage-addon-backup-*'))
        self.assertEqual(len(backups), 1)
        self.assertEqual(tree(backups[0]), OLD)
        self.assertEqual(receipt['result'], 'installed')
        self.assertEqual(receipt['backup'], str(backups[0]))
        self.assertEqual(list(root.glob('vantage-addon-staging-*')), [])

    def test_a_drive_root_as_the_backup_folder_from_another_folder_on_it(self):
        # Run from X:\elsewhere, the drive-relative X:vantage-addon-install-... meant a receipt in X:\elsewhere, not
        # in X:\.
        root = self.drive(self.work.name)
        elsewhere = root / 'elsewhere'
        elsewhere.mkdir()
        code, out, _ = self.install(game=root / 'game', backups=root, cwd=elsewhere)
        self.assertEqual(code, 0, out)
        receipts = list(root.glob('vantage-addon-install-*.json'))
        self.assertEqual(len(receipts), 1, out)
        self.assertIn('Receipt: ' + str(receipts[0]), out)
        self.assertEqual(list(elsewhere.iterdir()), [])
        self.assertEqual(tree(self.game / 'addons/vantage'), NEW)

    def test_a_game_folder_at_a_drive_root(self):
        # Trimmed to X:, the game's addons folder was looked for in the folder this runs from.
        root = self.drive(self.game)
        code, out, receipt = self.install(game=root, cwd=root / 'scripts')
        self.assertEqual(code, 0, out)
        self.assertEqual(tree(self.game / 'addons/vantage'), NEW)
        self.assertEqual(receipt['addon'], str(root / 'addons' / 'vantage'))

    def test_an_update_with_the_game_folder_at_a_drive_root(self):
        # The backup has to be on the game's drive, and with the game at its root the whole drive is the game folder.
        # So the backup may go anywhere on it but in the addons folder or the settings folder.
        root = self.drive(self.game)
        self.write(self.game / 'addons/vantage', OLD)
        self.write(self.game, SETTINGS)
        refused = ('addons/backups', 'config/addons/vantage/backups')
        for inside in refused:
            (self.game / inside).mkdir()
        self.kept = {name: data for name, data in tree(self.game).items() if not name.startswith('addons/vantage/')}
        for inside in refused:
            with self.subTest(inside=inside):
                code, out, _ = self.install(game=root, backups=root / inside)
                self.assertEqual(code, 1, out)
                self.assertIn('the backup folder must be outside the addons folder and the config\\addons\\vantage folder', out)
                self.assertEqual(tree(self.game / 'addons/vantage'), OLD)
                self.assertEqual(list((self.game / inside).iterdir()), [])
        backups = self.game / 'backups'
        backups.mkdir()
        code, out, receipt = self.install(game=root, backups=root / 'backups')
        self.assertEqual(code, 0, out)
        self.assertEqual(tree(self.game / 'addons/vantage'), NEW)
        moved = list(backups.glob('vantage-addon-backup-*'))
        self.assertEqual(len(moved), 1)
        self.assertEqual(tree(moved[0]), OLD)
        self.assertEqual(receipt['result'], 'installed')
        self.assertEqual(receipt['backup'], str(root / 'backups' / moved[0].name))
        self.assertEqual(receipt['settings_after'], {name: hashlib.sha256(data).hexdigest() for name, data in SETTINGS.items()})
        self.assertEqual(list(backups.glob('vantage-addon-staging-*')), [])
        # The backup and the receipt are all that is new outside addons/vantage.
        self.kept.update({name: data for name, data in tree(self.game).items() if name.startswith('backups/')})


if __name__ == '__main__':
    unittest.main()
