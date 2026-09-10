#!/usr/bin/env python3
"""Print the crashed thread of every macOS crash report on this machine.

A native crash inside a test reaches the build log as one line — "Shell
subprocess crashed with segmentation fault" — and nothing else. macOS writes
the stack to ~/Library/Logs/DiagnosticReports a few seconds later, on a CI
machine that is thrown away when the build ends. This prints the part that
says WHERE: the exception, and the frames of the thread that crashed, each
with the image it belongs to.

2026-09-11: the first fix for the Apple reader went into a function the
crash never reached, because the log could not say which one it was.
"""
import glob
import json
import os
import time

REPORTS = os.path.expanduser("~/Library/Logs/DiagnosticReports")


def crashed_frames(doc):
    images = doc.get("usedImages", [])
    for thread in doc.get("threads", []):
        if not thread.get("triggered"):
            continue
        for frame in thread.get("frames", [])[:48]:
            index = frame.get("imageIndex", -1)
            image = images[index] if 0 <= index < len(images) else {}
            name = image.get("name") or os.path.basename(image.get("path", "?"))
            symbol = frame.get("symbol", "?")
            offset = frame.get("symbolLocation", frame.get("imageOffset", 0))
            yield f"  {name:32} {symbol} + {offset}"


def main():
    # ReportCrash writes after the process is gone; the crash that ended
    # the run may still be on its way to disk.
    time.sleep(5)
    paths = sorted(glob.glob(os.path.join(REPORTS, "*.ips")))
    if not paths:
        print(f"crash reports: none in {REPORTS}")
        return
    for path in paths:
        with open(path, encoding="utf-8", errors="replace") as handle:
            raw = handle.read()
        header, _, body = raw.partition("\n")
        print(f"=== crash report {os.path.basename(path)}")
        try:
            meta = json.loads(header)
            doc = json.loads(body)
        except ValueError as error:
            print(f"  (not the JSON report format: {error}); its first lines:")
            print("\n".join(raw.splitlines()[:40]))
            continue
        print(f"  process: {meta.get('app_name') or meta.get('name')}")
        print(f"  exception: {doc.get('exception')}")
        for line in crashed_frames(doc):
            print(line)


if __name__ == "__main__":
    main()
