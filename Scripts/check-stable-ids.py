#!/usr/bin/env python3
"""Every decoded model must be given an id, not handed a fresh one.

Several models carry a client-side UUID that defaults to `UUID()`. That is
right for something made on the phone and wrong for something read off the
server: decoding the same row twice produced two different ids, so reading a
collection again renamed everything in it.

The visible failure was the meal page. Applying a saved meal refetches the
day it went into, every meal came back with a new id, and the open page --
holding the id it was given when it opened -- matched nothing and drew
"Meal Not Found" over a meal that was still there.

The rest were quiet, which is why this exists. A `ForEach` rebuilds and
re-animates rows that did not change. A sheet bound to `item:` closes
because its item stopped existing. A selection clears itself. None of that
announces a cause.

The rule checked here: inside an API repository, constructing a model whose
id is a stored UUID, while passing `serverID:`, requires passing `id:` too.
`serverID:` is what marks the value as a server row rather than something
being drafted locally -- a blank set being added to a workout has no server
id yet and legitimately takes a fresh UUID.

    python3 Scripts/check-stable-ids.py

Exits non-zero and names every offender.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "IOS Frontend" / "IOS Frontend"

STRUCT = re.compile(r"^(?:nonisolated |private |public )*struct (\w+)", re.MULTILINE)
STORED_UUID_ID = re.compile(r"^\s*(?:let|var) id: UUID\b", re.MULTILINE)


def uuid_identified_models() -> set[str]:
    """Model types whose id is a stored UUID rather than a server value."""
    found: set[str] = set()
    for path in sorted((APP / "Models").glob("*.swift")):
        text = path.read_text(encoding="utf-8")
        starts = [(m.start(), m.group(1)) for m in STRUCT.finditer(text)]
        for index, (offset, name) in enumerate(starts):
            end = starts[index + 1][0] if index + 1 < len(starts) else len(text)
            if STORED_UUID_ID.search(text, offset, end):
                found.add(name)
    return found


def call_body(text: str, open_paren: int) -> tuple[str, int]:
    """The text between `open_paren` and the paren that closes it."""
    depth = 0
    for position in range(open_paren, len(text)):
        character = text[position]
        if character == "(":
            depth += 1
        elif character == ")":
            depth -= 1
            if depth == 0:
                return text[open_paren + 1 : position], position
    return "", len(text)


def without_prose(body: str) -> str:
    """The call with comment and string contents blanked out.

    Splitting on commas needs to see only the ones separating arguments. A
    comment explaining why an id is derived can easily contain one -- the
    first version of this check reported five false offenders, all of them
    sites already fixed, because a comma inside the comment above `id:` cut
    the argument in half and the label went missing.
    """
    out: list[str] = []
    position = 0
    in_string = False
    while position < len(body):
        character = body[position]
        if in_string:
            if character == "\\":
                out.append("  ")
                position += 2
                continue
            if character == '"':
                in_string = False
            out.append("\n" if character == "\n" else " ")
            position += 1
            continue
        if character == '"':
            in_string = True
            out.append(" ")
            position += 1
            continue
        if character == "/" and body[position + 1 : position + 2] == "/":
            while position < len(body) and body[position] != "\n":
                out.append(" ")
                position += 1
            continue
        out.append(character)
        position += 1
    return "".join(out)


def top_level_labels(body: str) -> list[str]:
    """Argument labels at the call's own depth, ignoring nested calls."""
    body = without_prose(body)
    labels: list[str] = []
    depth = 0
    start = 0
    for position, character in enumerate(body):
        if character in "([{":
            depth += 1
        elif character in ")]}":
            depth -= 1
        elif character == "," and depth == 0:
            labels.append(body[start:position])
            start = position + 1
    labels.append(body[start:])
    return [
        match.group(1)
        for match in (re.match(r"\s*(\w+):", part) for part in labels)
        if match
    ]


def offenders(models: set[str]) -> list[str]:
    problems: list[str] = []
    for path in sorted((APP / "API").glob("*.swift")):
        text = path.read_text(encoding="utf-8")
        for name in models:
            for match in re.finditer(rf"\b{re.escape(name)}\s*\(", text):
                body, _ = call_body(text, match.end() - 1)
                labels = top_level_labels(body)
                # Only rows that came from the server. Something drafted on
                # the phone has no server id and may take a fresh UUID.
                if "serverID" not in labels:
                    continue
                if "id" in labels:
                    continue
                line = text.count("\n", 0, match.start()) + 1
                problems.append(
                    f"{path.relative_to(ROOT)}:{line}: {name} is built from a "
                    f"server row without an id, so decoding it twice makes two "
                    f"of it. Pass id: .stable(forServerID:) — see "
                    f"Models/StableIdentity.swift."
                )
    return sorted(problems)


def main() -> int:
    models = uuid_identified_models()
    if not models:
        print("no UUID-identified models found; has the layout moved?")
        return 1

    print(f"checking {len(models)} UUID-identified models: {', '.join(sorted(models))}")
    problems = offenders(models)
    if problems:
        print(f"\n{len(problems)} decoded without a stable id:")
        for problem in problems:
            print(f"  {problem}")
        return 1

    print("every decoded model is given an id")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
