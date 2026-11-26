"""Fetch locked inputs and stage a clean AOSP source tree for a build group."""

import argparse
from collections.abc import Iterable
from concurrent.futures import ThreadPoolExecutor
from hashlib import file_digest, sha256
import json
from pathlib import Path
import subprocess
import tarfile
from tempfile import TemporaryDirectory
from typing import TypedDict, cast


ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / "out/inputs"


class Download(TypedDict):
    url: str
    sha256: str
    license: str


class Source(Download):
    path: str
    strip: int


class Inputs(TypedDict):
    version: str
    source: dict[str, Source]
    tool: dict[str, Download]


def inputs() -> Inputs:
    return cast(Inputs, json.loads((ROOT / "locks/inputs.json").read_text()))


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return file_digest(stream, "sha256").hexdigest()


def tree_digest(path: Path) -> str:
    # Gitiles repacks immutable trees with variable archive headers.
    entries: dict[str, tuple[str, int, str]] = {}
    with tarfile.open(path) as archive:
        for entry in archive:
            if entry.name in entries:
                raise ValueError(f"Duplicate source entry: {entry.name}")
            stream = archive.extractfile(entry) if entry.isfile() else None
            content = entry.linkname
            if stream is not None:
                with stream:
                    content = sha256(stream.read()).hexdigest()
            entries[entry.name] = (entry.type.decode("ascii"), entry.mode, content)
    return sha256(
        json.dumps(entries, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()


def fetch(kind: str, name: str, record: Download, *, normalize: bool = False) -> None:
    target = CACHE / kind / name
    checksum = tree_digest if normalize else digest
    if target.is_file() and checksum(target) == record["sha256"]:
        return
    url = record["url"]
    if not url.startswith("https://"):
        raise ValueError(f"Only HTTPS is supported: {url}")
    target.parent.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(dir=target.parent) as scratch:
        temporary = Path(scratch) / name
        subprocess.run(
            [
                "curl",
                "--disable",
                "--proto",
                "=https",
                "--proto-redir",
                "=https",
                "--fail",
                "--silent",
                "--show-error",
                "--location",
                "--retry",
                "3",
                "--connect-timeout",
                "20",
                "--max-time",
                "300",
                "--output",
                temporary,
                url,
            ],
            check=True,
        )
        if checksum(temporary) != record["sha256"]:
            raise ValueError(f"SHA-256 mismatch for {url}")
        temporary.replace(target)


def stage_members(
    entries: Iterable[tarfile.TarInfo], prefix: str, strip: int
) -> Iterable[tarfile.TarInfo]:
    for entry in entries:
        parts = Path(entry.name).parts[strip:]
        if parts:
            link = entry.linkname
            if entry.islnk():
                link = str(Path(prefix).joinpath(*Path(link).parts[strip:]))
            yield entry.replace(name=str(Path(prefix).joinpath(*parts)), linkname=link)


def prepare(source: Path | None) -> None:
    locked = inputs()
    projects, tools = locked["source"], locked["tool"]
    with ThreadPoolExecutor(max_workers=6) as pool:
        jobs = [
            pool.submit(fetch, "source", name, entry, normalize=True)
            for name, entry in projects.items()
        ]
        jobs.extend(
            pool.submit(fetch, "tool", name, entry) for name, entry in tools.items()
        )
        for job in jobs:
            job.result()
    if source is None:
        return
    for name, entry in projects.items():
        with tarfile.open(CACHE / "source" / name) as archive:
            archive.extractall(
                source,
                stage_members(archive, entry["path"], entry["strip"]),
                filter="data",
            )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path)
    parser.add_argument("--version", action="store_true")
    args = parser.parse_args()
    if args.version:
        print(inputs()["version"])
    else:
        prepare(args.source)


if __name__ == "__main__":
    main()
