#!/usr/bin/env python3
"""Release identity checks must isolate the app while checking every configuration."""
import plistlib
from pathlib import Path
import tempfile
import unittest

from check_hub_ball_release import PROJECT_FILE, project_identity


class ReleaseIdentityTests(unittest.TestCase):
    def setUp(self):
        settings = {
            "PRODUCT_BUNDLE_IDENTIFIER": "com.sfrancoe.HubBall",
            "MARKETING_VERSION": "1.1", "CURRENT_PROJECT_VERSION": "117",
        }
        self.project = {"rootObject": "root", "objects": {
            "root": {"targets": ["app", "tests"]},
            "app": {"productType": "com.apple.product-type.application",
                    "buildConfigurationList": "app-configs"},
            "tests": {"productType": "com.apple.product-type.bundle.unit-test",
                      "buildConfigurationList": "test-configs"},
            "app-configs": {"buildConfigurations": ["debug", "release"]},
            "test-configs": {"buildConfigurations": ["test-debug"]},
            "debug": {"buildSettings": dict(settings)},
            "release": {"buildSettings": dict(settings)},
            "test-debug": {"buildSettings": {
                "PRODUCT_BUNDLE_IDENTIFIER": "com.example.Tests",
                "MARKETING_VERSION": "0.1", "CURRENT_PROJECT_VERSION": "999",
            }},
        }}

    def identity(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "project.pbxproj"
            path.write_bytes(plistlib.dumps(self.project))
            return project_identity(path)

    def test_ignores_test_target_identity(self):
        self.assertEqual(self.identity(), ("com.sfrancoe.HubBall", "1.1", 117))

    def test_rejects_disagreement_between_app_configurations(self):
        settings = self.project["objects"]["release"]["buildSettings"]
        for key in tuple(settings):
            with self.subTest(setting=key):
                previous = settings[key]
                settings[key] = "999"
                with self.assertRaisesRegex(ValueError, key):
                    self.identity()
                settings[key] = previous

    def test_rejects_missing_identity_in_a_configuration(self):
        del self.project["objects"]["release"]["buildSettings"]["CURRENT_PROJECT_VERSION"]
        with self.assertRaisesRegex(ValueError, "CURRENT_PROJECT_VERSION"):
            self.identity()

    def test_rejects_ambiguous_app_targets(self):
        self.project["objects"]["tests"]["productType"] = "com.apple.product-type.application"
        with self.assertRaisesRegex(ValueError, "one application target"):
            self.identity()

    def test_actual_project_matches_release_manifest(self):
        import json
        from check_hub_ball_release import MANIFEST_PATH
        manifest = json.loads(MANIFEST_PATH.read_text())
        self.assertEqual(project_identity(PROJECT_FILE), (
            manifest["bundle_id"], manifest["version"], manifest["build"],
        ))


if __name__ == "__main__":
    unittest.main()
