import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock

spec = importlib.util.spec_from_file_location('sources', Path(__file__).resolve().parents[1] / 'scripts/sources.py')
sources = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sources)


class SourceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.data = b'valid source\n'
        self.package = dict(filename='sample.tar.xz', url='https://example.org/sample.tar.xz',
                            sha256=hashlib.sha256(self.data).hexdigest(), size_bytes=len(self.data))

    def opener(self, data):
        response = io.BytesIO(data)
        response.geturl = lambda: self.package['url']
        return Mock(open=Mock(return_value=response))

    def test_fetch_promotes_verified_partial_and_reuses_without_network(self):
        partial = self.directory / 'sample.tar.xz.part'
        partial.write_bytes(b'old incomplete download')
        opener = self.opener(self.data)
        sources.fetch(self.package, self.directory, opener)
        self.assertFalse(partial.exists())
        self.assertEqual((self.directory / 'sample.tar.xz').read_bytes(), self.data)
        sources.fetch(self.package, self.directory, opener)
        opener.open.assert_called_once()

    def test_bad_download_is_never_promoted(self):
        with self.assertRaisesRegex(ValueError, 'SHA-256 mismatch'):
            sources.fetch(self.package, self.directory, self.opener(b'x' * len(self.data)))
        self.assertFalse((self.directory / 'sample.tar.xz').exists())
        self.assertTrue((self.directory / 'sample.tar.xz.part').exists())

    def test_bad_cached_file_is_preserved_without_network(self):
        path = self.directory / 'sample.tar.xz'
        path.write_bytes(b'x' * len(self.data))
        opener = Mock()
        with self.assertRaisesRegex(ValueError, 'SHA-256 mismatch'):
            sources.fetch(self.package, self.directory, opener)
        opener.open.assert_not_called()
        self.assertEqual(path.read_bytes(), b'x' * len(self.data))

    def test_manifest_rejects_paths_duplicates_and_insecure_urls(self):
        for change in [dict(filename='../escape'), dict(url='http://example.org/source'),
                       dict(sha256='invalid'), dict(size_bytes=0)]:
            with self.subTest(change=change):
                path = self.directory / 'manifest.json'
                path.write_text(json.dumps(dict(schema_version=1, packages=[self.package | change])))
                with self.assertRaises(ValueError):
                    sources.load_manifest(path)
        path.write_text(json.dumps(dict(schema_version=1, packages=[self.package, self.package])))
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            sources.load_manifest(path)

    def test_redirect_rejects_http(self):
        with self.assertRaisesRegex(ValueError, 'HTTPS'):
            sources.HTTPSRedirect().redirect_request(None, None, 302, '', {}, 'http://example.org/source')

    def test_missing_and_symlink_are_rejected(self):
        path = self.directory / 'sample.tar.xz'
        with self.assertRaises(ValueError):
            sources.verify(path, self.package)
        target = self.directory / 'target'
        target.write_bytes(self.data)
        path.symlink_to(target)
        with self.assertRaises(ValueError):
            sources.fetch(self.package, self.directory, Mock())


if __name__ == '__main__':
    unittest.main()
