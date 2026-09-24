#!/usr/bin/env python3
"""Check that a desktop-opened book precedes the last-book fallback."""

import argparse
import ast
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time
from urllib.parse import unquote, urlparse


SCHEMA = "org.gnucash.GnuCash.history"


def settings(env, *arguments):
    result = subprocess.run(["gsettings", *arguments], env=env, text=True,
                            capture_output=True, timeout=15, check=False)
    if result.returncode:
        raise RuntimeError(f"gsettings {' '.join(arguments)}: {result.stderr}")
    return result.stdout.strip()


def history_entry(env, key):
    return ast.literal_eval(settings(env, "get", SCHEMA, key))


def bundle_processes(executable):
    result = subprocess.run(["ps", "-axo", "pid=,command="], text=True,
                            capture_output=True, timeout=15, check=True)
    prefix = str(executable)
    for line in result.stdout.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) == 2 and (parts[1] == prefix or
                                parts[1].startswith(prefix + " ")):
            yield int(parts[0])


def stop_bundle(executable):
    pids = list(bundle_processes(executable))
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline and list(bundle_processes(executable)):
        time.sleep(0.2)
    for pid in bundle_processes(executable):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def is_book(entry, book):
    if not entry:
        return False
    parsed = urlparse(entry)
    path = Path(unquote(parsed.path)) if parsed.scheme == "file" else Path(entry)
    return path.exists() and path.samefile(book)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--sample-book", type=Path, required=True)
    parser.add_argument("--runtime-root", type=Path, required=True)
    args = parser.parse_args()

    if sys.platform != "darwin":
        raise RuntimeError("This test needs macOS Launch Services")
    app = args.app.resolve()
    executable = app / "Contents/MacOS/Gnucash"
    schemas = list(app.glob("Contents/Resources/**/gschemas.compiled"))
    if not executable.is_file() or len(schemas) != 1:
        raise RuntimeError("Expected the GnuCash executable and one bundled schema set")
    if list(bundle_processes(executable)):
        raise RuntimeError("A GnuCash bundle process is already running")

    root = args.runtime_root.resolve()
    root.mkdir(parents=True, exist_ok=True)
    for name in ("home", "config", "data", "cache", "gnc-config", "gnc-data"):
        (root / name).mkdir(exist_ok=True)
    last_book = root / "last-book.gnucash"
    requested_book = root / "finder-book.gnucash"
    shutil.copyfile(args.sample_book, last_book)
    shutil.copyfile(args.sample_book, requested_book)

    env = os.environ.copy()
    env.update(HOME=str(root / "home"), XDG_CONFIG_HOME=str(root / "config"),
               XDG_DATA_HOME=str(root / "data"),
               XDG_CACHE_HOME=str(root / "cache"),
               GNC_CONFIG_HOME=str(root / "gnc-config"),
               GNC_DATA_HOME=str(root / "gnc-data"),
               GSETTINGS_BACKEND="keyfile",
               GSETTINGS_SCHEMA_DIR=str(schemas[0].parent))

    # A URI in file0 remains byte-for-byte unchanged if only the requested
    # book opens. If the fallback opens first, GnuCash also inserts A's local
    # path into history, so the final file1/file2 values expose that order.
    last_uri = last_book.as_uri()
    settings(env, "set", SCHEMA, "file0", repr(last_uri))
    settings(env, "set", "org.gnucash.GnuCash.dialogs.new-user",
             "first-startup", "false")
    if history_entry(env, "file0") != last_uri:
        raise RuntimeError("Could not seed the isolated last-book history")

    stdout_log = root / "finder-open.stdout.log"
    stderr_log = root / "finder-open.stderr.log"
    command = ["open", "-W", "-n", "-a", str(app),
               "--stdout", str(stdout_log), "--stderr", str(stderr_log)]
    for key in ("HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME",
                "GNC_CONFIG_HOME", "GNC_DATA_HOME", "GSETTINGS_BACKEND",
                "GSETTINGS_SCHEMA_DIR"):
        command.extend(("--env", f"{key}={env[key]}"))
    command.append(str(requested_book))

    launched = subprocess.Popen(command, env=env, text=True,
                                stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE)
    try:
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            if launched.poll() is not None:
                stdout, stderr = launched.communicate()
                raise RuntimeError(
                    f"Launch Services exited before opening the book: "
                    f"status={launched.returncode}, stdout={stdout}, stderr={stderr}")
            if is_book(history_entry(env, "file0"), requested_book):
                break
            time.sleep(0.5)
        else:
            raise RuntimeError("Finder-requested book did not reach history in 120 s")

        entries = [history_entry(env, f"file{i}") for i in range(3)]
        if entries[1] != last_uri or entries[2]:
            raise AssertionError(
                "Last-book fallback was opened before the Finder book: "
                f"history={entries!r}")
        print(f"Finder book opened first; history={entries!r}")
    finally:
        stop_bundle(executable)
        if launched.poll() is None:
            try:
                launched.communicate(timeout=10)
            except subprocess.TimeoutExpired:
                launched.terminate()
                launched.communicate(timeout=10)


if __name__ == "__main__":
    main()
