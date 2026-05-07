#!/usr/bin/env python3
import argparse
import shutil
from pathlib import Path


def move_if_exists(path, dest_dir):
    if not path.exists():
        return None
    dest_dir.mkdir(parents=True, exist_ok=True)
    target = dest_dir / path.name
    if target.exists():
        stem = target.stem
        suffix = target.suffix
        i = 2
        while target.exists():
            target = dest_dir / f"{stem}_{i}{suffix}"
            i += 1
    shutil.move(str(path), str(target))
    return target


def main():
    parser = argparse.ArgumentParser(description="Organize BGM video project outputs without deleting source media.")
    parser.add_argument("--final", nargs="*", default=[])
    parser.add_argument("--reviews", nargs="*", default=[])
    parser.add_argument("--metadata", nargs="*", default=[])
    parser.add_argument("--intermediates", nargs="*", default=[])
    parser.add_argument("--final-dir", default="00_FINAL")
    parser.add_argument("--work-dir", default="80_work")
    args = parser.parse_args()

    final_dir = Path(args.final_dir)
    work_dir = Path(args.work_dir)
    moved = []

    for item in args.final:
        result = move_if_exists(Path(item), final_dir)
        if result:
            moved.append(result)
    for item in args.reviews:
        result = move_if_exists(Path(item), work_dir / "reviews")
        if result:
            moved.append(result)
    for item in args.metadata:
        result = move_if_exists(Path(item), work_dir / "metadata")
        if result:
            moved.append(result)
    for item in args.intermediates:
        result = move_if_exists(Path(item), work_dir / "old_renders")
        if result:
            moved.append(result)

    print("Moved files:")
    for path in moved:
        print(path)


if __name__ == "__main__":
    main()
