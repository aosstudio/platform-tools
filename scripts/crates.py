"""Stage verified Cargo packages and their notices for the ADB mDNS build."""

from hashlib import sha256
import json
from pathlib import Path
import shutil
import sys
import tarfile
import tomllib

from inputs import CACHE, ROOT


def main() -> None:
    vendor, licenses = map(Path, sys.argv[1:])
    vendor.mkdir()
    locked = tomllib.loads((ROOT / "locks/Cargo.lock").read_text())
    for dependency in locked["package"]:
        if "source" not in dependency:
            continue
        name = f"{dependency['name']}-{dependency['version']}"
        with tarfile.open(CACHE / "tool" / f"{name}.crate") as archive:
            archive.extractall(vendor, filter="data")
        crate = vendor / name
        files = {
            file.relative_to(crate).as_posix(): sha256(file.read_bytes()).hexdigest()
            for file in sorted(crate.rglob("*"))
            if file.is_file()
        }
        (crate / ".cargo-checksum.json").write_text(
            json.dumps({"package": dependency["checksum"], "files": files}) + "\n"
        )
        for notice in crate.iterdir():
            if notice.is_file() and notice.name.startswith(
                ("LICENSE", "COPYING", "NOTICE", "UNLICENSE")
            ):
                shutil.copyfile(notice, licenses / f"{name}-{notice.name}")


if __name__ == "__main__":
    main()
