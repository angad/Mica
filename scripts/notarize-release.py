#!/usr/bin/env python3
"""Stage, sign, submit and finish a Mica Developer ID release. Never publishes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import uuid

ROOT = Path(__file__).resolve().parent.parent
VERIFY = ROOT / "scripts/verify-release.sh"


def run(*arguments, capture=False):
    return subprocess.run(
        [str(a) for a in arguments], check=True,
        stdout=subprocess.PIPE if capture else None, text=True).stdout


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def profile_name():
    profile = os.environ.get("MICA_NOTARY_PROFILE", "").strip()
    if not profile:
        raise ValueError("Set MICA_NOTARY_PROFILE to a notarytool Keychain profile. Do not put passwords in this script.")
    return profile


def signing_identity():
    requested = os.environ.get("MICA_SIGNING_IDENTITY", "").strip()
    identities = run("security", "find-identity", "-v", "-p", "codesigning", capture=True)
    usable = re.findall(
        r'^\s*\d+\)\s+([A-Fa-f0-9]{40})\s+"(Developer ID Application: [^"]+)"',
        identities, re.M)
    if not usable:
        raise ValueError("No usable Developer ID Application certificate and private key. Apple Developer Program enrollment and certificate installation are required.")
    if not requested:
        raise ValueError("Set MICA_SIGNING_IDENTITY to the exact Developer ID Application name or SHA-1 from security find-identity.")
    matches = [sha for sha, name in usable if requested == name or requested.upper() == sha.upper()]
    if len(matches) != 1:
        raise ValueError("MICA_SIGNING_IDENTITY must identify exactly one usable Developer ID Application certificate.")
    return matches[0]


def preflight():
    identity = signing_identity()
    profile = profile_name()
    # Validate access without printing the team's submission history or credentials.
    run("xcrun", "notarytool", "history", "--keychain-profile", profile,
        "--output-format", "json", capture=True)
    return identity, profile


def submit():
    identity, profile = preflight()
    source = ROOT / "dist/Mica.app"
    run(VERIFY, source)
    # Mica currently contains one app executable and optional top-level Swift dylibs.
    # Refuse a new nested-code layout until the signing order is reviewed.
    for folder in ("PlugIns", "XPCServices", "Helpers", "Library"):
        location = source / "Contents" / folder
        if location.exists() and any(location.iterdir()):
            raise ValueError(f"Review signing for newly added nested code in {location}")
    frameworks = source / "Contents/Frameworks"
    for item in frameworks.iterdir():
        if item.is_symlink() or not item.is_file() or item.suffix != ".dylib":
            raise ValueError(f"Review signing for unexpected nested code: {item}")
    work_root = ROOT / ".build/notarization"
    work_root.mkdir(parents=True, exist_ok=True)
    job = Path(tempfile.mkdtemp(prefix="mica-", dir=work_root))
    app = job / "Mica.app"
    run("ditto", source, app)
    # Sign libraries individually, then the outer bundle. No deep-sign shortcut,
    # debugger entitlement or hardened-runtime exceptions.
    for library in sorted((app / "Contents/Frameworks").glob("*.dylib")):
        run("codesign", "--force", "--sign", identity, "--timestamp", library)
    run("codesign", "--force", "--sign", identity, "--timestamp",
        "--options", "runtime", app)
    run(VERIFY, "--distribution", app)
    archive = job / "submission.zip"
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, archive)
    metadata = {
        "profile": profile,
        "binary_sha256": digest(app / "Contents/MacOS/Mica"),
        "archive_sha256": digest(archive),
    }
    write_json(job / "job.json", metadata)
    print(f"Staged signed candidate: {job}", flush=True)
    result = json.loads(run(
        "xcrun", "notarytool", "submit", archive, "--keychain-profile", profile,
        "--output-format", "json", capture=True))
    write_json(job / "submission.json", result)
    metadata["id"] = result["id"]
    write_json(job / "job.json", metadata)
    print(f"Submitted to Apple: {result['id']}")
    print("Submission is not acceptance. Finish after processing with:")
    print(f"  ./scripts/notarize-release.py finish {job}")


def finish(job):
    job = job.resolve()
    metadata = json.loads((job / "job.json").read_text())
    try:
        uuid.UUID(str(metadata.get("id", "")))
    except ValueError:
        raise ValueError("Missing or invalid submission ID; inspect submission.json before retrying.")
    app = job / "Mica.app"
    if digest(app / "Contents/MacOS/Mica") != metadata["binary_sha256"]:
        raise ValueError("Signed candidate changed after submission.")
    if digest(job / "submission.zip") != metadata["archive_sha256"]:
        raise ValueError("Submitted archive changed.")
    run(VERIFY, "--distribution", app)
    result = json.loads(run(
        "xcrun", "notarytool", "info", metadata["id"], "--keychain-profile",
        metadata["profile"], "--output-format", "json", capture=True))
    write_json(job / "status.json", result)
    status = result["status"]
    if status != "Accepted":
        if status == "In Progress":
            print(f"Still processing: {metadata['id']}. Run finish again later. No release archive created.")
            return
        run("xcrun", "notarytool", "log", metadata["id"], "--keychain-profile",
            metadata["profile"], job / "notarization-log.json")
        raise ValueError(f"Apple returned {status}; inspect {job / 'notarization-log.json'}. No release archive created.")
    run("xcrun", "stapler", "staple", app)
    run(VERIFY, "--notarized", app)
    version = plistlib.loads((app / "Contents/Info.plist").read_bytes())["CFBundleShortVersionString"]
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Unexpected release version")
    staged_zip = job / f"Mica-{version}-universal.zip"
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, staged_zip)
    # Verify the ticket survives the exact archive that will be distributed.
    with tempfile.TemporaryDirectory(prefix="extract-", dir=job) as extracted:
        run("ditto", "-x", "-k", staged_zip, extracted)
        run(VERIFY, "--notarized", Path(extracted) / "Mica.app")
    output = ROOT / "dist/notarized"
    output.mkdir(parents=True, exist_ok=True)
    final = output / staged_zip.name
    # ditto into a temporary sibling, then atomically expose a verified archive.
    temporary = output / f".{job.name}.zip"
    run("ditto", staged_zip, temporary)
    temporary.replace(final)
    checksums = output / f"Mica-{version}-SHA256SUMS.txt"
    checksums.write_text(f"{digest(final)}  {final.name}\n")
    print(f"Accepted, stapled, Gatekeeper-approved archive: {final}")
    print(f"Checksums: {checksums}")
    print("No GitHub release was changed. Publish this archive after runtime smoke testing.")


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("check", help="Validate Developer ID and Keychain notarization access")
    commands.add_parser("submit", help="Sign a staged app and submit it; preserve the local development build")
    end = commands.add_parser("finish", help="Check acceptance, staple and verify, then create release ZIP")
    end.add_argument("job", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "check":
            preflight()
            print("Developer ID signing identity and notarization credentials are ready.")
        elif args.command == "submit":
            submit()
        else:
            finish(args.job)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print(f"Notarization stopped: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
