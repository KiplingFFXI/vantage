"""The GitHub workflows check what they say they check.

verify.yml runs every Python test that needs no game and no window. draft-release.yml drafts a release whose notes
name the commit its zip was built from. A run whose version already has a release stops unless that release was built
from the run's commit and, on a tag run, from where the tag points. Its shell steps run here in Git Bash with made-up
gh and git commands, in a temporary folder, never against GitHub.
"""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / '.github/workflows'
# Made-up commits: the one a draft was built from (X), a later one at the same version (Y), and an annotated tag's
# own object (T).
X, Y, T = '1' * 40, '2' * 40, '3' * 40
# The Python tests verify.yml leaves out besides the preview tests, which open a window. These read the game's art and
# skip without it.
GAME_ART = {'action_icons_client', 'draw_digest', 'frame_search', 'frame_shut_cost', 'frame_window_cost'}


def git_bash():
    # Git's own bash. On Windows, a bash.exe in System32 starts WSL instead.
    if os.name != 'nt':
        return shutil.which('bash')
    git = shutil.which('git')
    for folder in Path(git).resolve().parents if git else ():
        if (folder / 'bin/bash.exe').is_file():
            return str(folder / 'bin/bash.exe')
    return None


BASH = git_bash()

# gh and git as bash functions. Each reads its answer from a file in $FAKE, and gh release create keeps the notes it
# was given.
FAKES = r'''
gh() {
    case "$1 $2" in
        'release list') cat "$FAKE/releases" ;;
        'release view') cat "$FAKE/body" ;;
        'release create')
            while [ $# -gt 0 ]; do
                if [ "$1" = --notes-file ]; then cp "$2" "$FAKE/created"; fi
                shift
            done ;;
        *) echo "unexpected: gh $*"; return 1 ;;
    esac
}
git() {
    case "$1" in
        ls-remote) cat "$FAKE/refs" ;;
        *) echo "unexpected: git $*"; return 1 ;;
    esac
}
'''


def step(name):
    """The shell lines of a draft-release.yml step's run: block."""
    lines = (WORKFLOWS / 'draft-release.yml').read_text(encoding='ascii').replace('\r', '').split('\n')
    start = lines.index('      - name: ' + name)
    run = next(index for index in range(start, len(lines)) if lines[index].strip() == 'run: |')
    indent = len(lines[run + 1]) - len(lines[run + 1].lstrip())
    body = []
    for line in lines[run + 1:]:
        if line.strip() and not line.startswith(' ' * indent):
            break
        body.append(line[indent:])
    return '\n'.join(body).rstrip('\n') + '\n'


def tag_commit():
    """The awk program the draft job keeps in its TAG_COMMIT env value, which both steps run."""
    lines = (WORKFLOWS / 'draft-release.yml').read_text(encoding='ascii').replace('\r', '').split('\n')
    start = lines.index('      TAG_COMMIT: |') + 1
    indent = len(lines[start]) - len(lines[start].lstrip())
    body = []
    for line in lines[start:]:
        if line.strip() and not line.startswith(' ' * indent):
            break
        body.append(line[indent:])
    return '\n'.join(body).rstrip('\n') + '\n'


def tag_refs(commit):
    return commit + '\trefs/tags/v1.3.1\n'


class VerifyTests(unittest.TestCase):
    def test_ci_runs_every_python_test_that_needs_no_game_or_window(self):
        text = (WORKFLOWS / 'verify.yml').read_text(encoding='ascii')
        listed = re.search(r'foreach \(\$test in (.*?)\) \{', text, re.S)
        self.assertIsNotNone(listed, 'verify.yml runs its Python tests from one foreach.')
        tests = {path.stem[len('test_'):] for path in (ROOT / 'tests').glob('test_*.py')}
        window = {name for name in tests if name.endswith('preview')}
        self.assertLessEqual(GAME_ART, tests)
        self.assertEqual(sorted(re.findall(r"'(\w+)'", listed.group(1))), sorted(tests - window - GAME_ART))


@unittest.skipUnless(BASH, 'needs Git Bash')
class DraftReleaseTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix='vantage_workflow_')
        root = Path(self.work.name)
        self.fake, self.repo, self.script, self.output = root / 'fake', root / 'repo', root / 'step.sh', root / 'output'
        self.fake.mkdir()
        (self.repo / 'vantage').mkdir(parents=True)
        (self.repo / 'vantage/vantage.lua').write_bytes(b"addon.name = 'vantage';\naddon.version = '1.3.1';\n")
        (self.repo / 'CHANGELOG.md').write_bytes(b'# Changelog\n\n## 1.3.1\n\n- A fix.\n\n## 1.3.0\n\n- Older.\n')

    def tearDown(self):
        self.work.cleanup()

    def run_step(self, name, releases=(), body='', refs='', **env):
        for file, text in (('releases', ''.join(tag + '\n' for tag in releases)), ('body', body), ('refs', refs)):
            (self.fake / file).write_bytes(text.encode('ascii'))
        self.script.write_bytes((FAKES + step(name)).encode('ascii'))
        self.output.write_bytes(b'')
        environment = dict(os.environ, FAKE=self.fake.as_posix(), RUNNER_TEMP=self.fake.as_posix(),
                           GITHUB_OUTPUT=self.output.as_posix(), BEFORE='', TAG_COMMIT=tag_commit(), **env)
        result = subprocess.run([BASH, '-e', self.script.as_posix()], cwd=self.repo, capture_output=True, text=True,
                                timeout=120, env=environment)
        return result.returncode, result.stdout + result.stderr, self.output.read_text(encoding='ascii')

    def draft(self, commit):
        """The notes Draft the release gives a draft it builds at this commit, before any tag exists."""
        code, out, _ = self.run_step('Draft the release', VERSION='1.3.1', GITHUB_SHA=commit)
        self.assertEqual(code, 0, out)
        return (self.fake / 'created').read_text(encoding='ascii')

    def check(self, body, commit, refs='', tag=True):
        """Check the version on a tag run, or on a run by hand on main, when v1.3.1 already has a release."""
        kind, name = ('tag', 'v1.3.1') if tag else ('branch', 'main')
        return self.run_step('Check the version', releases=('v1.3.0', 'v1.3.1'), body=body, refs=refs,
                             GITHUB_REF_TYPE=kind, GITHUB_REF_NAME=name, GITHUB_SHA=commit)

    def test_the_draft_notes_end_with_a_hidden_line_naming_the_build(self):
        notes = self.draft(X)
        self.assertIn('- A fix.', notes)
        self.assertNotIn('Older', notes)
        self.assertRegex(notes.splitlines()[-1], '^<!-- .*' + X + '.* -->$')

    def test_a_tag_on_a_later_commit_stops(self):
        # A same-version commit Y after the draft, then the tag at Y: pushed by hand, or made by publishing with the
        # Target on main. Publishing keeps the zip built from X, so the run has to fail.
        code, out, outputs = self.check(self.draft(X), Y, tag_refs(Y))
        self.assertEqual(code, 1, out)
        self.assertIn('built from ' + X + ', not ' + Y, out)
        self.assertNotIn('draft=true', outputs)

    def test_a_run_by_hand_on_a_later_commit_stops(self):
        code, out, outputs = self.check(self.draft(X), Y, tag=False)
        self.assertEqual(code, 1, out)
        self.assertIn('built from ' + X + ', not ' + Y, out)
        self.assertNotIn('draft=true', outputs)

    def test_a_tag_moved_after_the_run_started_stops(self):
        code, out, outputs = self.check(self.draft(X), X, tag_refs(Y))
        self.assertEqual(code, 1, out)
        self.assertIn('v1.3.1 points to ' + Y, out)
        self.assertNotIn('draft=true', outputs)

    def test_a_release_whose_notes_name_no_build_stops(self):
        code, out, outputs = self.check('- A fix.\r\n', X, tag_refs(X))
        self.assertEqual(code, 1, out)
        self.assertIn("don't say which commit", out)
        self.assertNotIn('draft=true', outputs)

    def test_the_tag_on_the_drafts_own_commit_passes(self):
        # Pushing main and its tag together: the tag run sees the draft the main run made. Notes edited in a browser
        # come back with CRLF line ends.
        notes = self.draft(X)
        for refs in (tag_refs(X), T + '\trefs/tags/v1.3.1\n' + X + '\trefs/tags/v1.3.1^{}\n'):
            for body in (notes, notes.replace('\n', '\r\n')):
                with self.subTest(refs=refs, crlf='\r' in body):
                    code, out, outputs = self.check(body, X, refs)
                    self.assertEqual(code, 0, out)
                    self.assertIn('v1.3.1 already has a release', out)
                    self.assertNotIn('draft=true', outputs)

    def test_a_draft_checks_a_tag_that_already_exists(self):
        # A tag pushed before the draft run reaches gh release create. The draft keeps that tag, so it has to point at
        # the commit the zip was built from.
        for refs, code in ((tag_refs(X), 0), (T + '\trefs/tags/v1.3.1\n' + X + '\trefs/tags/v1.3.1^{}\n', 0),
                           (tag_refs(Y), 1)):
            with self.subTest(refs=refs):
                if (self.fake / 'created').exists():
                    (self.fake / 'created').unlink()
                result, out, _ = self.run_step('Draft the release', refs=refs, VERSION='1.3.1', GITHUB_SHA=X)
                self.assertEqual(result, code, out)
                self.assertEqual((self.fake / 'created').exists(), code == 0, out)
                if code:
                    self.assertIn('v1.3.1 points to ' + Y + ', but this zip was built from ' + X
                                  + '. No release was drafted.', out)

    def test_refs_that_name_no_single_commit_stop_both_steps(self):
        # Both steps share one program that reads the tag's commit. A short hash or the tag named twice gives none.
        for refs in (X[:39] + '\trefs/tags/v1.3.1\n', tag_refs(X) + tag_refs(Y)):
            with self.subTest(refs=refs):
                if (self.fake / 'created').exists():
                    (self.fake / 'created').unlink()
                result, out, _ = self.run_step('Draft the release', refs=refs, VERSION='1.3.1', GITHUB_SHA=X)
                self.assertEqual(result, 1, out)
                self.assertFalse((self.fake / 'created').exists(), out)
                self.assertIn('Could not resolve v1.3.1 to a single commit. No release was drafted.', out)
                code, out, outputs = self.check(self.draft(X), X, refs)
                self.assertEqual(code, 1, out)
                self.assertIn('Could not resolve v1.3.1 to a single commit.', out)
                self.assertNotIn('draft=true', outputs)

    def test_a_version_with_no_release_gets_a_draft(self):
        code, out, outputs = self.run_step('Check the version', releases=('v1.3.0',), GITHUB_REF_TYPE='tag',
                                           GITHUB_REF_NAME='v1.3.1', GITHUB_SHA=X)
        self.assertEqual(code, 0, out)
        self.assertIn('draft=true', outputs)


if __name__ == '__main__':
    unittest.main()
