#!/usr/bin/env python3
"""Package verified container contents for GitHub Releases without rebuilding."""

import argparse
import hashlib
import json
import pathlib
import re
import shutil
import stat
import subprocess
import tempfile
import zipfile


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def sha256(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def files(directory):
    result = {}
    for path in sorted(directory.rglob("*")):
        if path.is_symlink():
            raise ValueError(f"unexpected symlink: {path}")
        if path.is_file():
            result[path.relative_to(directory).as_posix()] = sha256(path)
    return result


def archive(directory, destination, executable=None):
    with zipfile.ZipFile(destination, "w") as output:
        for name in files(directory):
            entry = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            entry.create_system = 3
            entry.external_attr = (stat.S_IFREG | (0o755 if name == executable else 0o644)) << 16
            output.writestr(entry, (directory / name).read_bytes(), zipfile.ZIP_DEFLATED, 9)
    with zipfile.ZipFile(destination) as output:
        if output.testzip() is not None:
            raise ValueError(f"invalid archive: {destination}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("component", choices=("nami", "nami-server", "nami-web", "nami-agent"))
    parser.add_argument("version")
    args = parser.parse_args()
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z][0-9A-Za-z.-]*)?", args.version):
        parser.error("version must be a Docker-compatible semantic version, for example 0.3.2")

    root = pathlib.Path(__file__).resolve().parent.parent
    prefix = {"nami": "nami", "nami-server": "server", "nami-web": "web", "nami-agent": "agent"}[args.component]
    tag = f"{prefix}-v{args.version}"
    destination = root / "releases" / tag
    destination.parent.mkdir(exist_ok=True)
    if destination.exists():
        raise FileExistsError(f"refusing to replace {destination}")

    image = f"ghcr.io/cosnami/{args.component}"
    index = json.loads(command("docker", "buildx", "imagetools", "inspect", f"{image}:{args.version}", "--format", "{{json .Manifest}}"))
    reference = f"{image}@{index['digest']}"
    platforms = {item["platform"]["architecture"]: item["digest"] for item in index["manifests"] if item.get("platform", {}).get("os") == "linux"}
    if not {"amd64", "arm64"} <= platforms.keys():
        raise ValueError("the image must contain Linux AMD64 and ARM64")

    manifest = {"component": args.component, "version": args.version, "release_tag": tag, "image": reference, "platforms": [], "assets": []}
    with tempfile.TemporaryDirectory(prefix=f".{tag}-", dir=destination.parent) as temporary:
        staging = pathlib.Path(temporary)
        output = staging / "release"
        output.mkdir()
        static_files = None
        revision = None
        for architecture, suffix in (("amd64", "x86_64"), ("arm64", "arm64")):
            platform = f"linux/{architecture}"
            subprocess.run(["docker", "pull", "--platform", platform, reference], check=True)
            inspected = json.loads(command("docker", "image", "inspect", "--platform", platform, reference))[0]
            labels = inspected["Config"]["Labels"]
            current_revision = labels.get("org.opencontainers.image.revision", "")
            if labels.get("org.opencontainers.image.version") != args.version or not re.fullmatch(r"[0-9a-f]{40}", current_revision):
                raise ValueError("image version or source revision is missing or inconsistent")
            if labels.get("org.opencontainers.image.source") != "https://github.com/cosnami/nami":
                raise ValueError("unexpected image source")
            if revision is not None and revision != current_revision:
                raise ValueError("architectures have different source revisions")
            revision = current_revision
            package = staging / architecture
            package.mkdir()
            container = command("docker", "create", "--platform", platform, "--network", "none", reference)
            try:
                if args.component == "nami-web":
                    subprocess.run(["docker", "cp", f"{container}:/app/.output/public/.", str(package)], check=True)
                else:
                    binary_name = "nami-agent" if args.component == "nami-agent" else "nami-server"
                    subprocess.run(["docker", "cp", f"{container}:/usr/local/bin/{binary_name}", str(package / args.component)], check=True)
            finally:
                subprocess.run(["docker", "rm", container], check=True, stdout=subprocess.DEVNULL)

            record = {"platform": platform, "manifest_digest": platforms[architecture]}
            if args.component == "nami-web":
                current_files = files(package)
                if not (package / "index.html").is_file() or (package / "index.html").stat().st_size == 0:
                    raise ValueError("static output is missing index.html")
                if static_files is not None and static_files != current_files:
                    raise ValueError("static output differs between architectures")
                static_files = current_files
                record["static_file_count"] = len(current_files)
            else:
                binary = package / args.component
                description = command("file", "-b", str(binary))
                expected = "x86-64" if architecture == "amd64" else "aarch64"
                if "ELF" not in description or expected not in description or "statically linked" not in description:
                    raise ValueError(f"unexpected binary: {description}")
                record["binary_sha256"] = sha256(binary)
                if args.component != "nami-agent":
                    shutil.copyfile(root / "server/config.example.toml", package / "config.example.toml")
                archive(package, output / f"{args.component}-linux-{suffix}.zip", args.component)
            manifest["platforms"].append(record)

        if args.component == "nami-web":
            archive(package, output / "nami-web-static.zip")
        manifest["image_source_revision"] = revision
        for asset in sorted(output.glob("*.zip")):
            manifest["assets"].append({"name": asset.name, "size": asset.stat().st_size, "sha256": sha256(asset)})
        (output / "release-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        sums = "".join(f"{sha256(path)}  {path.name}\n" for path in sorted(output.iterdir()))
        (output / "SHA256SUMS").write_text(sums)
        output.rename(destination)
    print(f"Packaged {tag}: {destination}")


if __name__ == "__main__":
    main()
