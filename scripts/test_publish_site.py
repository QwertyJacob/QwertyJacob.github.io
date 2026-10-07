#!/usr/bin/env python3
"""Exercise real Git publication in disposable repos, with SSH/rsync/GitHub mocked."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
MOCK = '''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['PUBLISH_TEST_LOG'], 'a') as log:
    log.write(json.dumps([name, args]) + '\\n')
if name == 'ssh' and os.environ.get('PUBLISH_TEST_SSH_FAIL'):
    sys.exit(1)
if name == 'rsync' and os.environ.get('PUBLISH_TEST_RSYNC_FAIL'):
    sys.exit(1)
if name == 'gh':
    if args[:2] == ['run', 'list']:
        print('123')
    elif args[:2] == ['run', 'view']:
        retried = Path(os.environ['PUBLISH_TEST_LOG']).with_suffix('.rerun').exists()
        print('' if retried else os.environ.get('PUBLISH_TEST_GH_CONCLUSION', 'success'))
    elif args[:2] == ['run', 'rerun']:
        Path(os.environ['PUBLISH_TEST_LOG']).with_suffix('.rerun').touch()
    elif args[:2] == ['run', 'watch'] and os.environ.get('PUBLISH_TEST_GH_WATCH_FAIL'):
        sys.exit(1)
'''


class PublishTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='publish-test-')
        self.addCleanup(self.temp.cleanup)
        base = Path(self.temp.name)
        self.repo = base / 'site with spaces'
        self.remote = base / 'remote.git'
        self.repo.mkdir()
        self.git('init', '--initial-branch=main')
        self.git('config', 'user.name', 'Publication test')
        self.git('config', 'user.email', 'test@example.invalid')
        (self.repo / 'scripts').mkdir()
        for name in ['publish_site.sh', 'deploy_dista.sh']:
            shutil.copy2(ROOT / 'scripts' / name, self.repo / 'scripts' / name)
        (self.repo / '.gitignore').write_text('*.env\n.env*\n')
        (self.repo / 'tesi.html').write_text('initial form')
        (self.repo / 'dista_academic_site.html').write_text('DiSTA homepage')
        (self.repo / 'public').mkdir()
        (self.repo / 'public' / 'asset.js').write_text('public asset')
        self.git('add', '--all')
        self.git('commit', '-m', 'Initial site')
        subprocess.run(['git', 'init', '--bare', str(self.remote)], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.git('remote', 'add', 'origin', str(self.remote))
        self.git('push', '-u', 'origin', 'main')
        # Any accidental invocation of the old auto-deploy hooks fails the test.
        for name in ['pre-push', 'post-commit']:
            hook = self.repo / '.git' / 'hooks' / name
            hook.write_text('#!/bin/sh\nexit 91\n')
            hook.chmod(0o755)
        self.log = base / 'commands.jsonl'
        mock_bin = base / 'bin'
        mock_bin.mkdir()
        for name in ['ssh', 'rsync', 'gh']:
            mock = mock_bin / name
            mock.write_text(MOCK)
            mock.chmod(0o755)
        self.env = {**os.environ, 'PATH': f'{mock_bin}:{os.environ["PATH"]}',
                    'PUBLISH_TEST_LOG': str(self.log)}
        (self.repo / 'supa.env').write_text('PRIVATE_TEST_VALUE=do-not-publish\n')
        (self.repo / 'tesi.html').write_text('updated form')
        (self.repo / 'public' / 'new.js').write_text('new public asset')

    def git(self, *args):
        return subprocess.run(['git', *args], cwd=self.repo, check=True,
                              text=True, capture_output=True).stdout.strip()

    def publish(self, *args):
        return subprocess.run(['bash', 'scripts/publish_site.sh', *args],
                              cwd=self.repo, env=self.env, text=True, capture_output=True)

    def calls(self, name):
        rows = [json.loads(line) for line in self.log.read_text().splitlines()]
        return [args for command, args in rows if command == name]

    def test_publication_and_repeat_without_duplicate_commit(self):
        result = self.publish('-m', 'Test publication')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.git('log', '-1', '--format=%s'), 'Test publication')
        sha = self.git('rev-parse', 'HEAD')
        self.assertEqual(self.git('rev-parse', 'origin/main'), sha)
        self.assertEqual(self.git('status', '--porcelain'), '')
        self.assertNotIn('supa.env', self.git('ls-tree', '-r', '--name-only', 'HEAD'))
        copies = self.calls('rsync')
        self.assertEqual(len(copies), 3)
        self.assertTrue(any(args[-2].endswith('/tesi.html') for args in copies))
        self.assertTrue(all(str(self.repo) not in args[-2] for args in copies))
        self.assertTrue(any(args[:2] == ['run', 'watch'] for args in self.calls('gh')))
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.git('rev-parse', 'HEAD'), sha)

    def test_dry_run_changes_nothing(self):
        sha = self.git('rev-parse', 'HEAD')
        status = self.git('status', '--porcelain')
        self.assertEqual(self.publish('--dry-run').returncode, 0)
        self.assertEqual(self.git('rev-parse', 'HEAD'), sha)
        self.assertEqual(self.git('status', '--porcelain'), status)
        self.assertFalse(self.log.exists())

    def test_ssh_failure_stops_before_commit_and_push(self):
        sha = self.git('rev-parse', 'HEAD')
        self.env['PUBLISH_TEST_SSH_FAIL'] = '1'
        self.assertNotEqual(self.publish().returncode, 0)
        self.assertEqual(self.git('rev-parse', 'HEAD'), sha)
        self.assertEqual(self.git('rev-parse', 'origin/main'), sha)

    def test_dista_failure_can_be_retried_without_duplicate_commit(self):
        self.env['PUBLISH_TEST_RSYNC_FAIL'] = '1'
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('DiSTA deployment', result.stderr)
        sha = self.git('rev-parse', 'HEAD')
        self.assertEqual(self.git('rev-parse', 'origin/main'), sha)
        del self.env['PUBLISH_TEST_RSYNC_FAIL']
        self.assertEqual(self.publish().returncode, 0)
        self.assertEqual(self.git('rev-parse', 'HEAD'), sha)

    def test_force_added_credentials_are_rejected(self):
        self.git('add', '--force', 'supa.env')
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('do-not-publish', result.stdout + result.stderr)
        self.assertFalse(self.log.exists())

    def test_pages_failure_is_reported_and_failed_run_is_retried(self):
        self.env['PUBLISH_TEST_GH_WATCH_FAIL'] = '1'
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('GitHub Pages deployment', result.stderr)
        sha = self.git('rev-parse', 'HEAD')
        del self.env['PUBLISH_TEST_GH_WATCH_FAIL']
        self.env['PUBLISH_TEST_GH_CONCLUSION'] = 'failure'
        self.assertEqual(self.publish().returncode, 0)
        self.assertEqual(self.git('rev-parse', 'HEAD'), sha)
        self.assertTrue(any(args[:2] == ['run', 'rerun'] for args in self.calls('gh')))

    def test_remote_changes_are_not_overwritten(self):
        other = Path(self.temp.name) / 'other'
        subprocess.run(['git', 'clone', '--branch', 'main', str(self.remote), str(other)],
                       check=True, capture_output=True)
        subprocess.run(['git', '-C', str(other), '-c', 'user.name=Other',
                        '-c', 'user.email=other@example.invalid', 'commit',
                        '--allow-empty', '-m', 'New remote changes'], check=True, capture_output=True)
        subprocess.run(['git', '-C', str(other), 'push', 'origin', 'main'],
                       check=True, capture_output=True)
        sha = self.git('rev-parse', 'HEAD')
        status = self.git('status', '--porcelain')
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Synchronize main', result.stderr)
        self.assertEqual(self.git('rev-parse', 'HEAD'), sha)
        self.assertEqual(self.git('status', '--porcelain'), status)

    def test_other_branch_is_rejected(self):
        self.git('switch', '-c', 'feature')
        self.assertNotEqual(self.publish().returncode, 0)
        self.assertFalse(self.log.exists())


if __name__ == '__main__':
    unittest.main()
