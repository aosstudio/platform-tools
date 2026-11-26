"""Create an SDK-layout ZIP with normalized per-entry timestamps."""

from pathlib import Path
from shutil import copyfileobj
import sys
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo


def main() -> None:
    work, output = map(Path, sys.argv[1:])
    with ZipFile(output, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted((work / "platform-tools").rglob("*")):
            if not path.is_file():
                continue
            info = ZipInfo(path.relative_to(work).as_posix(), (2026, 6, 5, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            info.compress_level = 9
            info.create_system = 3
            info.external_attr = path.stat().st_mode << 16
            with path.open("rb") as source, archive.open(info, "w") as member:
                copyfileobj(source, member)


if __name__ == "__main__":
    main()
