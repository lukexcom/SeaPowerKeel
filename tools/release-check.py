"""release-check: what GitHub Actions confirms for every Keel release (.github/workflows/release-check.yml).

  python -I tools/release-check.py stage <dist folder>          the program files of a build with their SHA-256 (Markdown)
  python -I tools/release-check.py verify <tag> <dist folder>   compare the build with the release zip, check VirusTotal,
                                                                write the result into the release notes

The dist folder is what tools/package.ps1 staged on the runner from the tagged commit, with the same SDK (global.json) and the
same pinned references (tools/refs.ps1) as the developer's release build, so every program file must match byte for byte.
Needs GITHUB_TOKEN and GITHUB_REPOSITORY (set by Actions); VT_API_KEY (repository secret) for VirusTotal. Standard library only.
"""
import hashlib
import io
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
import uuid
import zipfile
from pathlib import Path

VT = "https://www.virustotal.com/api/v3"
BIG = {"Microsoft", "Kaspersky", "BitDefender", "ESET-NOD32", "Avast", "AVG", "McAfee", "Symantec", "Sophos", "TrendMicro",
       "Malwarebytes", "Avira (no cloud)", "F-Secure", "GData", "Emsisoft", "DrWeb", "Fortinet", "CrowdStrike Falcon", "Google",
       "Panda", "Norton", "WithSecure"}
START, END = "<!-- release-check:start -->", "<!-- release-check:end -->"


def is_program(data):
    return data[:2] == b"MZ"


def stage_files(folder):
    """{relative posix path: sha256} of every program file (by its first bytes: Keel ships a DLL named .bin)."""
    out = {}
    for path in sorted(Path(folder).rglob("*")):
        if path.is_file():
            data = path.read_bytes()
            if is_program(data):
                out[path.relative_to(folder).as_posix()] = hashlib.sha256(data).hexdigest()
    return out


def zip_files(data):
    """{path inside the install folder: sha256} of every program file in the release zip (its root folder taken off)."""
    out = {}
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        for name in z.namelist():
            if not name.endswith("/"):
                body = z.read(name)
                if is_program(body):
                    out[name.split("/", 1)[1] if "/" in name else name] = hashlib.sha256(body).hexdigest()
    return out


def call(url, token=None, method="GET", body=None, headers=None, raw=False):
    request = urllib.request.Request(url, data=body, method=method, headers={"User-Agent": "keel-release-check", **(headers or {})})
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(request, timeout=300) as response:
        payload = response.read()
    return payload if raw else json.loads(payload or b"null")


def github(path, method="GET", body=None):
    return call(f"https://api.github.com/repos/{os.environ['GITHUB_REPOSITORY']}{path}", os.environ["GITHUB_TOKEN"], method,
                json.dumps(body).encode() if body is not None else None, {"Accept": "application/vnd.github+json"})


def wait_for_zip(tag):
    """The release and its zip. The developer's tool attaches the zip right after it creates the release: wait up to 20 minutes."""
    for _ in range(40):
        release = github(f"/releases/tags/{tag}")
        found = [a for a in release["assets"] if a["name"].endswith(".zip") and a["state"] == "uploaded"]
        if found:
            return release, found[0]
        time.sleep(30)
    raise SystemExit(f"release {tag} has no zip after 20 minutes")


def vt(path, key, method="GET", body=None, headers=None):
    """(status, json); waits out the free key's limit of 4 calls a minute."""
    for _ in range(6):
        try:
            return 200, call(VT + path, None, method, body, {"x-apikey": key, **(headers or {})})
        except urllib.error.HTTPError as error:
            if error.code != 429:
                return error.code, {}
            time.sleep(20)
    return 429, {}


def vt_report(digest, key):
    status, data = vt(f"/files/{digest}", key)
    if status != 200:
        return None
    results = data["data"]["attributes"].get("last_analysis_results", {})
    flagged = sorted(n for n, r in results.items() if r.get("category") in ("malicious", "suspicious"))
    ran = sum(1 for r in results.values() if r.get("category") in ("malicious", "suspicious", "undetected", "harmless"))
    return flagged, ran


def vt_send(name, data, key):
    """Sends a file VirusTotal has never seen (up to 32 MB) and waits for the scanners, at most 13 minutes."""
    if len(data) > 32 * 1024 * 1024:
        return
    boundary = uuid.uuid4().hex
    body = (f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{name}"\r\n'
            f"Content-Type: application/octet-stream\r\n\r\n").encode() + data + f"\r\n--{boundary}--\r\n".encode()
    status, sent = vt("/files", key, "POST", body, {"Content-Type": f"multipart/form-data; boundary={boundary}"})
    if status != 200:
        return
    for _ in range(40):
        time.sleep(20)
        status, analysis = vt(f"/analyses/{sent['data']['id']}", key)
        if status == 200 and analysis["data"]["attributes"].get("status") == "completed":
            return


def vt_cell(digest, data, name, key):
    """(Markdown cell, failed?) for one file."""
    if not key:
        return "not checked (no key)", False
    report = vt_report(digest, key)
    if report is None and data:
        vt_send(name, data, key)
        report = vt_report(digest, key)
    if report is None:
        return "not on VirusTotal", False
    flagged, ran = report
    bad = any(n in BIG for n in flagged) or len(flagged) >= 3
    return f"[{len(flagged)} / {ran}](https://www.virustotal.com/gui/file/{digest})", bad


def block(tag, rows, zip_row, all_match):
    run = f"{os.environ.get('GITHUB_SERVER_URL', 'https://github.com')}/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ.get('GITHUB_RUN_ID', '')}"
    sha = os.environ.get("GITHUB_SHA", "")[:10]
    verdict = "every program file matches the release zip byte for byte" if all_match else "**the rebuild does NOT match the release zip**"
    lines = [START, "", f"**Checked by GitHub Actions** ([run]({run}))", "",
             f"- Rebuilt from `{tag}` (commit `{sha}`) on GitHub's servers: {verdict}",
             f"- Signed build proof for each file: `gh attestation verify <file> --repo {os.environ['GITHUB_REPOSITORY']}`", "",
             "| File | SHA-256 | Rebuild | VirusTotal |", "|---|---|---|---|"]
    lines += [f"| `{name}` | `{digest}` | {match} | {cell} |" for name, digest, match, cell in rows + [zip_row]]
    return "\n".join(lines + ["", END])


def with_block(body, text):
    body = body or ""
    if START in body and END in body:
        return body[:body.index(START)] + text + body[body.index(END) + len(END):]
    return body.rstrip() + "\n\n" + text + "\n"


def verify(tag, dist):
    built = stage_files(dist)
    release, asset = wait_for_zip(tag)
    zip_data = call(asset["url"], os.environ["GITHUB_TOKEN"], headers={"Accept": "application/octet-stream"}, raw=True)
    published = zip_files(zip_data)
    key = os.environ.get("VT_API_KEY", "")
    rows, failed = [], False
    for name in sorted(set(built) | set(published)):
        match = "yes" if built.get(name) == published.get(name) else "NO" if name in built and name in published else "missing"
        digest = published.get(name) or built[name]
        cell, bad = vt_cell(digest, (Path(dist) / name).read_bytes() if name in built else b"", name, key)
        rows.append((name, digest, match, cell))
        failed |= match != "yes" or bad
    zip_digest = hashlib.sha256(zip_data).hexdigest()
    cell, bad = vt_cell(zip_digest, zip_data, asset["name"], key)
    failed |= bad
    text = block(tag, rows, (asset["name"], zip_digest, "-", cell), all(r[2] == "yes" for r in rows))
    github(f"/releases/{release['id']}", "PATCH", {"body": with_block(release["body"], text)})
    print(text)
    return 1 if failed else 0


def main(argv):
    if len(argv) == 2 and argv[0] == "stage":
        print("| File | SHA-256 |\n|---|---|\n" + "\n".join(f"| `{n}` | `{d}` |" for n, d in stage_files(argv[1]).items()))
        return 0
    if len(argv) == 3 and argv[0] == "verify" and re.fullmatch(r"v[\w.\-]+", argv[1]):
        return verify(argv[1], argv[2])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
