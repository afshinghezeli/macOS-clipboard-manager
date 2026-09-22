"""Tests for Scripts/appcast.py. Run with `make check`."""

import plistlib
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import appcast  # noqa: E402

NOTES = """## [0.2.0](https://github.com/afshinghezeli/spindle/compare/v0.1.0...v0.2.0) (2026-10-01)


### Added

* **search:** match text inside <images> ([abc1234](https://github.com/afshinghezeli/spindle/commit/abc1234))
* see [the docs](https://example.org/a)
"""


class AppcastTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.feed = self.directory / "appcast.xml"
        (self.directory / "notes.md").write_text(NOTES, encoding="utf-8")

    def release(self, version, build, channel=""):
        app = self.directory / ("Spindle-%s.app" % version)
        (app / "Contents").mkdir(parents=True)
        info = {
            "CFBundleShortVersionString": version,
            "CFBundleVersion": str(build),
            "LSMinimumSystemVersion": "15.0",
        }
        with open(app / "Contents" / "Info.plist", "wb") as f:
            plistlib.dump(info, f)
        arguments = [
            "--appcast", str(self.feed), "--app", str(app),
            "--url", "https://github.com/x/Spindle-%s.zip" % version,
            "--signature", 'sparkle:edSignature="c2lnbmF0dXJl" length="4789397"',
            "--notes", str(self.directory / "notes.md"),
        ]
        if channel:
            arguments += ["--channel", channel]
        appcast.main(arguments)

    def items(self):
        return ET.parse(self.feed).getroot().find("channel").findall("item")

    def test_creates_the_feed_and_lists_the_newest_release_first(self):
        self.release("0.1.0", 120)
        self.release("0.2.0-beta.1", 130, channel="beta")
        items = self.items()
        self.assertEqual([i.findtext(appcast.sparkle("version")) for i in items], ["130", "120"])
        self.assertEqual(items[0].findtext(appcast.sparkle("channel")), "beta")
        self.assertIsNone(items[1].find(appcast.sparkle("channel")))
        enclosure = items[1].find("enclosure")
        self.assertEqual(enclosure.get("length"), "4789397")
        self.assertEqual(enclosure.get(appcast.sparkle("edSignature")), "c2lnbmF0dXJl")
        self.assertIn('xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"', self.feed.read_text())

    def test_refuses_a_build_that_is_not_newer(self):
        self.release("0.1.0", 120)
        with self.assertRaises(SystemExit):
            self.release("0.1.1", 120)
        self.assertEqual(len(self.items()), 1)

    def test_notes_become_html_without_commit_links(self):
        html = appcast.notes_to_html(NOTES)
        self.assertNotIn("0.2.0", html)
        self.assertNotIn("abc1234", html)
        self.assertIn("<h3>Added</h3>", html)
        self.assertIn("<li><b>search:</b> match text inside &lt;images&gt;</li>", html)
        self.assertIn('<a href="https://example.org/a">the docs</a>', html)

    def test_rejects_output_that_is_not_a_signature(self):
        with self.assertRaises(SystemExit):
            appcast.parse_signature("ERROR: no key")


if __name__ == "__main__":
    unittest.main()
