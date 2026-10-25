"""Release safety boundaries; these do not simulate Apple accepting a signature."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

MODULE = Path(__file__).resolve().parents[2] / "scripts/notarize-release.py"
spec = importlib.util.spec_from_file_location("mica_notarization", MODULE)
notarization = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notarization)


class NotarizationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.job = self.root / "job"
        self.binary = self.job / "Mica.app/Contents/MacOS/Mica"
        self.binary.parent.mkdir(parents=True)
        self.binary.write_bytes(b"signed-candidate-fixture")
        archive = self.job / "submission.zip"
        archive.write_bytes(b"submitted-archive-fixture")
        self.metadata = {
            "id": "18ac0bed-c1b7-4a66-8fa9-de485df3210c",
            "profile": "fixture-profile",
            "binary_sha256": notarization.digest(self.binary),
            "archive_sha256": notarization.digest(archive),
        }
        self.save_metadata()
        self.addCleanup(patch.stopall)
        patch.object(notarization, "ROOT", self.root).start()

    def save_metadata(self):
        (self.job / "job.json").write_text(json.dumps(self.metadata))

    def test_processing_does_not_staple_or_create_a_release(self):
        def run(*arguments, **options):
            if "info" in arguments:
                return json.dumps({"status": "In Progress"})
        with patch.object(notarization, "run", side_effect=run) as command:
            with contextlib.redirect_stdout(io.StringIO()):
                notarization.finish(self.job)
            self.assertFalse((self.root / "dist").exists())
            self.assertFalse(any("stapler" in call.args for call in command.call_args_list))

    def test_rejection_downloads_diagnostics_without_creating_a_release(self):
        def run(*arguments, **options):
            if "info" in arguments:
                return json.dumps({"status": "Invalid"})
        with patch.object(notarization, "run", side_effect=run) as command:
            with self.assertRaisesRegex(ValueError, "Invalid"):
                notarization.finish(self.job)
            self.assertFalse((self.root / "dist").exists())
            self.assertTrue(any("log" in call.args for call in command.call_args_list))
            self.assertFalse(any("stapler" in call.args for call in command.call_args_list))

    def test_candidate_changed_after_upload_cannot_be_finished(self):
        self.binary.write_bytes(b"different-candidate")
        with patch.object(notarization, "run") as command:
            with self.assertRaisesRegex(ValueError, "candidate changed"):
                notarization.finish(self.job)
            command.assert_not_called()

    def test_invalid_submission_id_stops_before_network_access(self):
        self.metadata["id"] = "-" * 36
        self.save_metadata()
        with patch.object(notarization, "run") as command:
            with self.assertRaisesRegex(ValueError, "submission ID"):
                notarization.finish(self.job)
            command.assert_not_called()

    def test_development_certificate_is_not_a_distribution_identity(self):
        identities = '  1) ' + 'A' * 40 + ' "Apple Development: Fixture"\n  1 valid identities found'
        with patch.object(notarization, "run", return_value=identities):
            with self.assertRaisesRegex(ValueError, "No usable Developer ID"):
                notarization.signing_identity()


if __name__ == "__main__":
    unittest.main()
