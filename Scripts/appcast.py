#!/usr/bin/env python3
"""Add a release to Spindle's Sparkle appcast.

Usage:
    Scripts/appcast.py --appcast appcast.xml --app dist/release/Spindle.app \\
        --archive dist/Spindle-1.2.3.zip --url https://…/Spindle-1.2.3.zip \\
        --signature 'sparkle:edSignature="…" length="…"' --notes notes.md [--channel beta]

--signature takes the output of Sparkle's sign_update for the archive. --notes takes the
GitHub release body (Markdown); it is embedded as HTML, so the update window shows it without
Spindle loading anything from the network.

Refuses a build number that isn't higher than every build already in the appcast: Sparkle
compares build numbers, and a lower one would never be offered.

Needs only the Python 3 that ships with the Command Line Tools.
"""

import argparse
import email.utils
import html
import plistlib
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
DC = "http://purl.org/dc/elements/1.1/"
ET.register_namespace("sparkle", SPARKLE)
ET.register_namespace("dc", DC)

EMPTY_APPCAST = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="{sparkle}" xmlns:dc="{dc}">
  <channel>
    <title>Spindle</title>
    <link>https://github.com/afshinghezeli/spindle</link>
    <description>Updates for Spindle, a clipboard history for macOS.</description>
    <language>en</language>
  </channel>
</rss>
""".format(sparkle=SPARKLE, dc=DC)


def sparkle(tag):
    return "{%s}%s" % (SPARKLE, tag)


def notes_to_html(markdown):
    """Convert the small Markdown subset release-please writes into HTML."""
    lines = markdown.splitlines()
    # The first heading repeats the version and links to a diff; the update window already
    # shows the version.
    if lines and lines[0].startswith("## "):
        lines = lines[1:]
    out = []
    in_list = False
    for line in lines:
        stripped = line.strip()
        bullet = re.match(r"^[*-] (.*)$", stripped)
        if bullet:
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append("<li>%s</li>" % inline(bullet.group(1)))
            continue
        if in_list:
            out.append("</ul>")
            in_list = False
        heading = re.match(r"^#{1,6} (.*)$", stripped)
        if heading:
            out.append("<h3>%s</h3>" % inline(heading.group(1)))
        elif stripped:
            out.append("<p>%s</p>" % inline(stripped))
    if in_list:
        out.append("</ul>")
    return "\n".join(out)


def inline(text):
    # Commit links like "([abc1234](https://…))" mean nothing to someone updating the app.
    text = re.sub(r"\s*\(\[[0-9a-f]{7,40}\]\([^)]*\)\)", "", text)
    text = html.escape(text, quote=False)
    text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text)
    return re.sub(
        r"\[([^\]]+)\]\(([^)\s]+)\)",
        lambda m: '<a href="%s">%s</a>' % (html.escape(m.group(2)), m.group(1)),
        text,
    )


def parse_signature(output):
    attributes = dict(re.findall(r'([\w:]+)="([^"]*)"', output))
    if "sparkle:edSignature" not in attributes or "length" not in attributes:
        raise SystemExit("error: --signature needs sign_update's output, got %r" % output)
    return attributes["sparkle:edSignature"], attributes["length"]


def add_release(appcast, info, url, signature, length, notes_html, channel):
    channel_element = appcast.getroot().find("channel")
    build = info["CFBundleVersion"]
    existing = [int(v.text) for v in channel_element.iter(sparkle("version")) if v.text and v.text.isdigit()]
    if existing and int(build) <= max(existing):
        raise SystemExit(
            "error: build %s isn't higher than build %d, already in the appcast" % (build, max(existing))
        )

    item = ET.Element("item")
    ET.SubElement(item, "title").text = "Spindle %s" % info["CFBundleShortVersionString"]
    ET.SubElement(item, "pubDate").text = email.utils.formatdate(usegmt=True)
    ET.SubElement(item, sparkle("version")).text = build
    ET.SubElement(item, sparkle("shortVersionString")).text = info["CFBundleShortVersionString"]
    ET.SubElement(item, sparkle("minimumSystemVersion")).text = info["LSMinimumSystemVersion"]
    if channel:
        ET.SubElement(item, sparkle("channel")).text = channel
    ET.SubElement(item, "description").text = notes_html
    ET.SubElement(
        item,
        "enclosure",
        {"url": url, "length": length, "type": "application/octet-stream", sparkle("edSignature"): signature},
    )

    # Newest first, after the channel's own elements.
    position = next((i for i, child in enumerate(channel_element) if child.tag == "item"), len(channel_element))
    channel_element.insert(position, item)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--appcast", type=Path, required=True, help="created if missing")
    parser.add_argument("--app", type=Path, required=True, help="the released Spindle.app")
    parser.add_argument("--url", required=True, help="where the archive can be downloaded")
    parser.add_argument("--signature", required=True, help="sign_update's output for the archive")
    parser.add_argument("--notes", type=Path, required=True, help="release notes in Markdown")
    parser.add_argument("--channel", default="", help='"beta" for betas; empty for releases')
    args = parser.parse_args(argv)

    with open(args.app / "Contents" / "Info.plist", "rb") as f:
        info = plistlib.load(f)
    signature, length = parse_signature(args.signature)
    notes_html = notes_to_html(args.notes.read_text(encoding="utf-8"))

    if args.appcast.exists():
        appcast = ET.parse(args.appcast)
    else:
        appcast = ET.ElementTree(ET.fromstring(EMPTY_APPCAST))
    add_release(appcast, info, args.url, signature, length, notes_html, args.channel)
    ET.indent(appcast, space="  ")
    appcast.write(args.appcast, encoding="utf-8", xml_declaration=True)
    print("Added build %s to %s" % (info["CFBundleVersion"], args.appcast), file=sys.stderr)


if __name__ == "__main__":
    main()
