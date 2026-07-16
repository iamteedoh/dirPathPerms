#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
#
## Author: Tito Valentin
## Name of Program: dirPathPerms interactive test
## Date Created: 2026-07-16
## Description: Drives dirPathPerms.sh through a real pseudo-terminal to cover
##              the two behaviors that only exist interactively: entering a path
##              to check at the prompt, and recalling earlier entries with the
##              arrow keys. Both need a tty, so they cannot be tested by piping.

import os
import pty
import select
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(ROOT, "dirPathPerms.sh")

PROMPT = "Path or list file"
WHO_PROMPT = "(O)wner"
PERM_PROMPT = "(R)ead"


class Session:
    """A dirPathPerms.sh process attached to a pty."""

    def __init__(self, *args, color=False):
        self.buf = ""
        argv = [SCRIPT] + ([] if color else ["--no-color"]) + list(args)
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            if color:
                os.environ["TERM"] = "xterm-256color"
                os.environ.pop("NO_COLOR", None)
            os.execvp(SCRIPT, argv)

    def expect(self, marker, timeout=15):
        deadline = time.time() + timeout
        while time.time() < deadline:
            if marker in self.buf:
                return
            if select.select([self.fd], [], [], 0.2)[0]:
                try:
                    chunk = os.read(self.fd, 8192)
                except OSError:
                    break
                if not chunk:
                    break
                self.buf += chunk.decode(errors="replace").replace("\r", "")
        raise AssertionError(
            "timed out waiting for %r\n--- output so far ---\n%s" % (marker, self.buf)
        )

    def send(self, data):
        os.write(self.fd, data)

    def drain(self, timeout=2.5):
        deadline = time.time() + timeout
        while time.time() < deadline:
            if select.select([self.fd], [], [], 0.2)[0]:
                try:
                    chunk = os.read(self.fd, 8192)
                except OSError:
                    break
                if not chunk:
                    break
                self.buf += chunk.decode(errors="replace").replace("\r", "")
        return self.buf

    def close(self):
        try:
            os.close(self.fd)
        except OSError:
            pass
        try:
            os.waitpid(self.pid, 0)
        except OSError:
            pass


results = []


def check(name, condition, detail=""):
    results.append((name, condition, detail))
    if condition:
        print("  PASS  %s" % name)
    else:
        print("  FAIL  %s" % name)
        if detail:
            print("        " + detail.replace("\n", "\n        "))


def test_path_at_prompt():
    """A path typed at the prompt is checked directly, tilde and all."""
    d = tempfile.mkdtemp(prefix=".dirpathperms_it_", dir=os.path.expanduser("~"))
    rel = os.path.basename(d)
    s = Session()
    try:
        s.expect(PROMPT)
        s.send(("~/%s\n" % rel).encode())
        s.expect(WHO_PROMPT)
        s.send(b"u\n")
        s.expect(PERM_PROMPT)
        s.send(b"r\n")
        s.expect("Summary:")
        out = s.drain()
        check("a ~ path typed at the prompt is checked directly", d in out,
              "expected the resolved path %r in the output" % d)
        check("that path reports a result rather than an error",
              "1 granted" in out and "file not found" not in out,
              "output:\n%s" % out)
    finally:
        s.close()
        os.rmdir(d)


def test_arrow_key_history():
    """Up-arrow recalls what was typed earlier in the session."""
    s = Session()
    try:
        s.expect(PROMPT)
        s.send(b"/nope/typo/path\n")
        s.expect("No such path")
        before = s.buf.count("No such path")
        # Up-arrow, then Enter: readline should resubmit the recalled line.
        s.send(b"\x1b[A\n")
        time.sleep(0.6)
        s.drain(timeout=1.5)
        after = s.buf.count("No such path")
        check("up-arrow recalls the previous entry", after > before,
              "saw %d 'No such path' errors, expected more than %d\n%s"
              % (after, before, s.buf))
        check("the recalled text is the original entry",
              s.buf.count("/nope/typo/path") >= 2,
              "output:\n%s" % s.buf)
    finally:
        s.send(b"\x03")
        s.close()


def test_session_loop():
    """After a result the session keeps asking, and q ends it."""
    d = tempfile.mkdtemp(prefix=".dirpathperms_it_", dir=os.path.expanduser("~"))
    rel = os.path.basename(d)
    s = Session()
    try:
        s.expect(PROMPT)
        s.send(("~/%s\n" % rel).encode())
        s.expect(WHO_PROMPT)
        s.send(b"u\n")
        s.expect(PERM_PROMPT)
        s.send(b"r\n")
        s.expect("Summary:")
        # It must come back for another path instead of exiting.
        s.drain(timeout=0.8)
        check("the session asks for another path after a result",
              s.buf.count(PROMPT) >= 2,
              "saw the prompt %d time(s):\n%s" % (s.buf.count(PROMPT), s.buf[-400:]))
        # /etc/passwd's mode only appears in a second table.
        s.send(b"/etc/passwd\n")
        s.expect("-rw-r--r--")
        s.drain(timeout=0.8)
        check("a second path is checked without re-asking who/perm",
              s.buf.count("Summary:") >= 2 and s.buf.count(WHO_PROMPT) == 1,
              "saw %d summaries, %d who-prompts"
              % (s.buf.count("Summary:"), s.buf.count(WHO_PROMPT)))
        # q ends the session cleanly.
        s.send(b"q\n")
        out = s.drain()
        check("q ends the session", "Done." in out, "output tail:\n%s" % out[-400:])
    finally:
        s.close()
        os.rmdir(d)


def test_table_is_rendered():
    """The interactive result is the bordered table, with headers."""
    s = Session()
    try:
        s.expect(PROMPT)
        s.send(b"/etc/passwd\n")
        s.expect(WHO_PROMPT)
        s.send(b"a\n")
        s.expect(PERM_PROMPT)
        s.send(b"a\n")
        s.expect("Summary:")
        out = s.drain()
        check("interactive output is a bordered table",
              "┌" in out and "├" in out and "└" in out, "output:\n%s" % out[-600:])
        check("the table carries headers", "Path" in out and "Mode" in out and "Owner" in out)
        check("--perm all renders the R/W/X matrix", "R   W   X" in out)
    finally:
        s.send(b"q\n")
        s.close()


def test_zebra_striping():
    """Adjacent rows differ: every other row carries the stripe."""
    home = os.path.expanduser("~")
    listing = tempfile.NamedTemporaryFile(
        mode="w", suffix=".txt", prefix="dpp_", delete=False, dir=home
    )
    for _ in range(3):
        listing.write("/etc/passwd\n/var/log\n")
    listing.close()
    s = Session(color=True)
    try:
        s.expect(PROMPT)
        s.send((listing.name + "\n").encode())
        s.expect(WHO_PROMPT)
        s.send(b"u\n")
        s.expect(PERM_PROMPT)
        s.send(b"r\n")
        s.expect("Summary:")
        out = s.drain()
        striped = out.count("48;5;236")
        check("alternate rows carry a background stripe", striped >= 2,
              "found %d striped rows" % striped)
    finally:
        s.send(b"q\n")
        s.close()
        os.unlink(listing.name)


def main():
    print("\ndirPathPerms interactive (pty) tests\n")
    test_path_at_prompt()
    test_arrow_key_history()
    test_session_loop()
    test_table_is_rendered()
    test_zebra_striping()
    failed = [n for n, ok, _ in results if not ok]
    print("\nSummary: %d passed, %d failed\n" % (len(results) - len(failed), len(failed)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
