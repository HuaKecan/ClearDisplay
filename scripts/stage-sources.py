#!/usr/bin/env python3
"""Mirror build inputs into a local cache, without cloud extended attributes."""
import os
from pathlib import Path
import sys
import tempfile

source, destination = (Path(value).resolve() for value in sys.argv[1:3])
destination.mkdir(parents=True, exist_ok=True)
inputs = [source / "Package.swift"]
for directory in ("Sources", "Tests", "Resources"):
    inputs.extend(path for path in (source / directory).rglob("*") if path.is_file())
expected = set()
for original in inputs:
    relative = original.relative_to(source)
    expected.add(relative)
    target = destination / relative
    content = original.read_bytes()
    if target.is_file() and target.read_bytes() == content:
        continue
    target.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(dir=target.parent, prefix=".stage-")
    with os.fdopen(descriptor, "wb") as output:
        output.write(content)
    os.replace(temporary, target)
for directory in ("Sources", "Tests", "Resources"):
    for path in (destination / directory).rglob("*"):
        if path.is_file() and path.relative_to(destination) not in expected:
            path.unlink()
