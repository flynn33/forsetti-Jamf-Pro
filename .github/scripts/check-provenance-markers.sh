#!/usr/bin/env python3
import json
import os
import re
import subprocess
import sys
from pathlib import Path


def join(*parts):
    return "".join(parts)


FIXED_MARKERS = [
    ("tool-origin-01", join("Cod", "ex")),
    ("tool-origin-02", join("Open", "A", "I")),
    ("tool-origin-03", join("Chat", "GPT")),
    ("tool-origin-04", join("Clau", "de")),
    ("tool-origin-05", join("Anth", "ropic")),
    ("tool-origin-06", join("Gem", "ini")),
    ("tool-origin-07", join("Cop", "ilot")),
    ("credit-trailer-01", join("Co-", "Authored-", "By:")),
    ("credit-line-01", join("Gener", "ated by")),
    ("credit-line-02", join("Gener", "ated with")),
    ("origin-phrase-01", join("A", "I-generated")),
    ("origin-phrase-02", join("made with ", "A", "I")),
    ("origin-phrase-03", join("created by ", "A", "I")),
    ("origin-phrase-04", join("assistant-", "generated")),
    ("origin-phrase-05", join("large language ", "model")),
    ("origin-phrase-06", join("artificial ", "intelligence")),
    ("origin-phrase-07", join("vibe ", "coded")),
]

REGEX_MARKERS = [
    ("origin-word-01", re.compile(r"\b" + join("A", "I") + r"\b")),
    ("origin-word-02", re.compile(r"\b" + join("L", "L", "M") + r"\b", re.IGNORECASE)),
]


def run_git(root, args):
    completed = subprocess.run(
        ["git", "-C", str(root), *args],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return completed.stdout


def fixed_marker_match(text):
    lowered = text.casefold()
    for marker_id, marker in FIXED_MARKERS:
        if marker.casefold() in lowered:
            return marker_id
    for marker_id, pattern in REGEX_MARKERS:
        if pattern.search(text):
            return marker_id
    return None


def is_binary(path):
    try:
        with path.open("rb") as handle:
            sample = handle.read(4096)
    except OSError:
        return True
    return b"\0" in sample


def read_text(path):
    try:
        return path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return ""


def tracked_paths(root):
    raw = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-z"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    ).stdout
    for item in raw.split(b"\0"):
        if item:
            yield item.decode("utf-8", errors="surrogateescape")


def add_finding(findings, area, marker_id, location):
    findings.append((area, marker_id, location))


def scan_paths_and_contents(root, findings):
    for relative in tracked_paths(root):
        path_marker = fixed_marker_match(relative)
        if path_marker:
            add_finding(findings, "path", path_marker, relative)

        absolute = root / relative
        if not absolute.is_file() or is_binary(absolute):
            continue

        for line_number, line in enumerate(read_text(absolute).splitlines(), start=1):
            marker = fixed_marker_match(line)
            if marker:
                add_finding(findings, "content", marker, f"{relative}:{line_number}")


def scan_commit_messages(root, findings):
    hashes = [line for line in run_git(root, ["log", "--format=%H"]).splitlines() if line]
    for commit_hash in hashes:
        message = run_git(root, ["log", "--format=%B", "-1", commit_hash])
        marker = fixed_marker_match(message)
        if marker:
            add_finding(findings, "commit-message", marker, commit_hash[:12])


def scan_event_payload(findings):
    event_path = os.environ.get("GITHUB_EVENT_PATH")
    if not event_path:
        return
    try:
        payload = json.loads(Path(event_path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return

    pull_request = payload.get("pull_request")
    if not isinstance(pull_request, dict):
        return

    for field in ("title", "body"):
        value = pull_request.get(field) or ""
        marker = fixed_marker_match(str(value))
        if marker:
            add_finding(findings, f"pull-request-{field}", marker, field)


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    findings = []

    scan_paths_and_contents(root, findings)
    scan_commit_messages(root, findings)
    scan_event_payload(findings)

    if findings:
        print("forbidden provenance marker found:")
        for area, marker_id, location in findings:
            print(f"- {area}: {location} ({marker_id})")
        return 1

    print("Provenance guard passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
