import unittest
import plistlib
from pathlib import Path
import tempfile
from unittest.mock import patch
import app_store_preflight as preflight


class PrivacyManifestTests(unittest.TestCase):
    def check(self, manifest, source='@AppStorage("favorite") var favorite = ""'):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "PrivacyInfo.xcprivacy"
            if manifest is not None:
                path.write_bytes(plistlib.dumps(manifest))
            (root / "Preferences.swift").write_text(source)
            with patch.object(preflight, "PRIVACY_MANIFEST", path), patch.object(preflight, "SOURCE_ROOT", root):
                return preflight.check_privacy_manifest()

    def manifest(self, reasons):
        return {"NSPrivacyAccessedAPITypes": [{
            "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
            "NSPrivacyAccessedAPITypeReasons": reasons,
        }]}

    def test_missing_manifest_fails(self):
        self.assertEqual(self.check(None).status, "FAIL")

    def test_empty_declarations_fail_for_app_storage_and_user_defaults(self):
        for source in ('@AppStorage("favorite") var favorite = ""', 'UserDefaults.standard.string(forKey: "favorite")'):
            self.assertEqual(self.check({"NSPrivacyAccessedAPITypes": []}, source).status, "FAIL")

    def test_app_local_reason_passes(self):
        self.assertEqual(self.check(self.manifest(["CA92.1"])).status, "PASS")

    def test_missing_wrong_or_malformed_reasons_fail(self):
        for reasons in ([], ["INVALID"], "CA92.1"):
            self.assertEqual(self.check(self.manifest(reasons)).status, "FAIL")

    def test_malformed_manifest_structure_fails(self):
        for manifest in ([], {"NSPrivacyAccessedAPITypes": {}}, {"NSPrivacyAccessedAPITypes": ["bad"]}):
            self.assertEqual(self.check(manifest).status, "FAIL")

    def test_no_user_defaults_does_not_require_category(self):
        self.assertEqual(self.check({}, "struct Example {}").status, "PASS")


class EndpointTests(unittest.TestCase):
    def check(self, url, payload):
        with patch.object(preflight, 'discovered_urls', return_value=[url]), patch.object(preflight, 'fetch_url', return_value=(200, payload)):
            return preflight.check_live_endpoints()[0]

    def test_editorial_article_is_html(self):
        url = next(iter(preflight.EDITORIAL_LINKS))
        self.assertEqual(self.check(url, b'<html><head><title>Brewers</title></head></html>').status, 'PASS')
        self.assertEqual(self.check(url, b'not a page').status, 'FAIL')

    def test_data_endpoint_still_requires_json(self):
        url = 'https://red-sox.netlify.app/api/data/seasons.json'
        self.assertEqual(self.check(url, b'<html><title>Error</title></html>').status, 'FAIL')
        self.assertEqual(self.check(url, b'{"2026": {}}').status, 'PASS')


if __name__ == '__main__':
    unittest.main()
