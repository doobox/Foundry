#!/usr/bin/env python3

"""Generate a large physical .foundry package from an existing project."""

from __future__ import annotations

import argparse
import copy
import json
import os
from pathlib import Path
import shutil
import sys
import uuid


CHUNK_SIZE = 8 * 1024 * 1024


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Duplicate a Foundry project's asset library into a separate stress fixture."
    )
    parser.add_argument("source", type=Path, help="Source .foundry package")
    parser.add_argument("output", type=Path, help="New .foundry package to create")
    parser.add_argument(
        "--factor",
        type=int,
        default=10,
        help="Total copies of the source asset library (2-50, default: 10)",
    )
    return parser.parse_args()


def validate_arguments(source: Path, output: Path, factor: int) -> None:
    source = source.resolve()
    output = output.resolve()
    if source.suffix.lower() != ".foundry" or not source.is_dir():
        raise ValueError(f"Source is not a .foundry package: {source}")
    if output.suffix.lower() != ".foundry":
        raise ValueError(f"Output must use the .foundry extension: {output}")
    if output.exists():
        raise FileExistsError(f"Output already exists: {output}")
    if source == output or source in output.parents or output in source.parents:
        raise ValueError("Source and output must be separate, non-nested packages.")
    if not 2 <= factor <= 50:
        raise ValueError("Factor must be between 2 and 50.")
    if not (source / "project.json").is_file() or not (source / "assets").is_dir():
        raise ValueError("Source does not contain project.json and an assets directory.")


def physical_copy(source: str, destination: str) -> str:
    """Stream bytes into a new file, avoiding clonefile/copy-on-write copies."""
    with open(source, "rb") as input_file, open(destination, "xb") as output_file:
        while chunk := input_file.read(CHUNK_SIZE):
            output_file.write(chunk)
    shutil.copystat(source, destination, follow_symlinks=False)
    return destination


def asset_files_by_id(assets_directory: Path) -> dict[str, Path]:
    result: dict[str, Path] = {}
    for path in assets_directory.iterdir():
        if path.is_file():
            result[path.stem.upper()] = path
    return result


def clone_asset_node(
    node: dict,
    round_number: int,
    source_files: dict[str, Path],
    output_assets: Path,
) -> dict:
    cloned = copy.deepcopy(node)
    if "asset" in cloned:
        asset = cloned["asset"]["_0"]
        original_id = asset["id"].upper()
        source_file = source_files.get(original_id)
        if source_file is None:
            raise FileNotFoundError(f"Asset data is missing for {asset['id']}")
        new_id = str(uuid.uuid4()).upper()
        asset["id"] = new_id
        asset["filename"] = f"Stress {round_number:02d} - {asset['filename']}"
        destination = output_assets / f"{new_id}{source_file.suffix}"
        physical_copy(str(source_file), str(destination))
        return cloned

    if "folder" in cloned:
        folder = cloned["folder"]["_0"]
        folder["id"] = str(uuid.uuid4()).upper()
        folder["name"] = f"Stress {round_number:02d} - {folder['name']}"
        folder["children"] = [
            clone_asset_node(child, round_number, source_files, output_assets)
            for child in folder.get("children", [])
        ]
        return cloned

    raise ValueError(f"Unknown asset-library node: {node}")


def directory_size(path: Path) -> int:
    return sum(item.stat().st_size for item in path.rglob("*") if item.is_file())


def format_bytes(byte_count: int) -> str:
    value = float(byte_count)
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if value < 1024 or unit == "TiB":
            return f"{value:.1f} {unit}"
        value /= 1024
    return f"{value:.1f} TiB"


def generate(source: Path, output: Path, factor: int) -> None:
    source = source.resolve()
    output = output.resolve()
    validate_arguments(source, output, factor)

    source_size = directory_size(source)
    estimated_size = source_size * factor
    free_space = shutil.disk_usage(output.parent).free
    if estimated_size + 512 * 1024 * 1024 > free_space:
        raise OSError(
            f"Insufficient free space: approximately {format_bytes(estimated_size)} required, "
            f"{format_bytes(free_space)} available."
        )

    staging = output.parent / f".{output.name}.staging-{uuid.uuid4()}"
    try:
        print(f"Copying source package ({format_bytes(source_size)})…", flush=True)
        shutil.copytree(source, staging, copy_function=physical_copy)

        project_path = staging / "project.json"
        with project_path.open("r", encoding="utf-8") as file:
            project = json.load(file)
        original_library = copy.deepcopy(project.get("assetLibrary", []))
        source_files = asset_files_by_id(source / "assets")
        output_assets = staging / "assets"

        for round_number in range(2, factor + 1):
            print(f"Generating asset-library copy {round_number} of {factor}…", flush=True)
            project["assetLibrary"].extend(
                clone_asset_node(node, round_number, source_files, output_assets)
                for node in original_library
            )

        project["id"] = str(uuid.uuid4()).upper()
        project["name"] = f"{project.get('name', source.stem)} Asset Stress {factor}x"
        temporary_project_path = staging / ".project.json.tmp"
        with temporary_project_path.open("w", encoding="utf-8") as file:
            json.dump(project, file, ensure_ascii=False, separators=(",", ":"))
        os.replace(temporary_project_path, project_path)
        os.replace(staging, output)
    except BaseException:
        shutil.rmtree(staging, ignore_errors=True)
        raise

    asset_count = sum(1 for item in (output / "assets").iterdir() if item.is_file())
    actual_size = directory_size(output)
    print("Created Foundry asset stress project:")
    print(f"  path: {output}")
    print(f"  assets: {asset_count}")
    print(f"  size: {format_bytes(actual_size)}")
    print("Move this generated project to Trash when testing is complete.")


def main() -> int:
    arguments = parse_arguments()
    try:
        generate(arguments.source, arguments.output, arguments.factor)
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
