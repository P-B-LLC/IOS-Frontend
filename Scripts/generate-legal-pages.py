#!/usr/bin/env python3
"""Publish the in-app legal documents as static web pages.

App Store Connect needs a privacy policy at a public URL, and the terms and
licence are worth having somewhere a person can read them before installing
anything. Rather than keeping a second copy of the wording in HTML -- which
would be one copy to forget when the other changes -- this reads the Swift
that the app itself renders and writes the pages from it.

    python3 Scripts/generate-legal-pages.py

Writes Legal/*.html. Drop them behind whatever serves the marketing site.
"""

import html
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = (
    ROOT / "IOS Frontend" / "IOS Frontend" / "Models" / "LegalDocuments.swift"
)
OUTPUT = ROOT / "Legal"


def read_constants(text):
    """The handful of values the documents interpolate."""
    constants = {}
    for name in ("contactEmail", "publisher", "effectiveDate"):
        match = re.search(r'static let %s = "([^"]*)"' % name, text)
        if match is None:
            sys.exit("no value for %s -- has the Swift changed?" % name)
        constants[name] = match.group(1)
    return constants


def unwrap(block, constants):
    """Turn a Swift multiline literal into the string Swift would produce."""
    lines = block.split("\n")
    # Swift strips the closing delimiter's indentation from every line. Here
    # the shallowest non-blank line stands in for it.
    widths = [
        len(line) - len(line.lstrip(" ")) for line in lines if line.strip()
    ]
    indent = min(widths) if widths else 0
    text = "\n".join(line[indent:] if line.strip() else "" for line in lines)

    # A trailing backslash joins the line to the next one.
    text = re.sub(r"\\\n", "", text)

    for name, value in constants.items():
        text = text.replace("\\(%s)" % name, value)

    if "\\(" in text:
        sys.exit("unresolved interpolation in the document text")
    return text.strip()


def read_documents(text, constants):
    """Every LegalDocument literal in the file, in source order."""
    documents = []
    for match in re.finditer(
        r'LegalDocument\(\s*'
        r'id: "(?P<id>[^"]+)",\s*'
        r'title: "(?P<title>[^"]+)",\s*'
        r'symbol: "[^"]*",\s*'
        r'summary: "(?P<summary>[^"]*)",\s*'
        r'body: """\n(?P<body>.*?)\n\s*"""',
        text,
        re.DOTALL,
    ):
        documents.append(
            {
                "id": match.group("id"),
                "title": match.group("title"),
                "summary": match.group("summary"),
                "body": unwrap(match.group("body"), constants),
            }
        )
    return documents


def is_heading(line):
    """Same rule the app uses: short, lettered, and nothing lowercase."""
    line = line.strip()
    if not 2 < len(line) < 60:
        return False
    if not any(c.isalpha() for c in line):
        return False
    return not any(c.islower() for c in line)


def render_body(body):
    parts = []
    paragraph = []

    def flush():
        if paragraph:
            joined = html.escape(" ".join(paragraph))
            parts.append("<p>%s</p>" % joined)
            paragraph.clear()

    for line in body.split("\n"):
        stripped = line.strip()
        if not stripped:
            flush()
        elif is_heading(stripped):
            flush()
            parts.append("<h2>%s</h2>" % html.escape(stripped))
        elif stripped.startswith("•"):
            flush()
            parts.append("<p class=\"bullet\">%s</p>" % html.escape(stripped))
        else:
            paragraph.append(stripped)
    flush()
    return "\n".join(parts)


PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} — Repbase</title>
<style>
  :root {{ color-scheme: light dark; --ink: #1c1a17; --quiet: #5f5952;
           --paper: #faf7f2; --accent: #a9714b; }}
  @media (prefers-color-scheme: dark) {{
    :root {{ --ink: #f2ede6; --quiet: #a9a29a; --paper: #17151300; --paper: #171513; }}
  }}
  body {{ margin: 0; background: var(--paper); color: var(--ink);
          font: 17px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }}
  main {{ max-width: 42rem; margin: 0 auto; padding: 3rem 1.5rem 5rem; }}
  h1 {{ font-size: 2rem; letter-spacing: -0.02em; margin: 0 0 2rem; }}
  h2 {{ font-size: 0.7rem; letter-spacing: 0.12em; color: var(--accent);
        margin: 2.25rem 0 0.5rem; }}
  p {{ color: var(--quiet); margin: 0 0 0.9rem; }}
  p.bullet {{ padding-left: 1rem; }}
  footer {{ margin-top: 3rem; font-size: 0.8rem; color: var(--quiet); }}
</style>
</head>
<body>
<main>
<h1>{title}</h1>
{body}
<footer>Repbase</footer>
</main>
</body>
</html>
"""


def main():
    text = SOURCE.read_text(encoding="utf-8")
    constants = read_constants(text)
    documents = read_documents(text, constants)
    if len(documents) != 3:
        sys.exit("found %d documents, expected 3" % len(documents))

    OUTPUT.mkdir(exist_ok=True)
    for document in documents:
        page = PAGE.format(
            title=html.escape(document["title"]),
            body=render_body(document["body"]),
        )
        path = OUTPUT / ("%s.html" % document["id"])
        path.write_text(page, encoding="utf-8")
        print("wrote %s (%d bytes)" % (path.relative_to(ROOT), len(page)))


if __name__ == "__main__":
    main()
