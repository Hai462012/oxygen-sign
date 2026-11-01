"""Private IPA signer: requires zsign executable and HTTPS reverse proxy."""
import os
import json
import plistlib
import secrets
import shutil
import time
import zipfile
from urllib.parse import urljoin
import subprocess
import tempfile
from pathlib import Path
import requests
from flask import Flask, jsonify, request, send_file, after_this_request, Response

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = int(os.getenv("SIGN_MAX_BYTES", str(600 * 1024 * 1024)))
VERIFY_URL = os.getenv("LICENSE_VERIFY_URL", "").strip()
ZSIGN = os.getenv("ZSIGN_BIN", "zsign")
PUBLIC_BASE_URL = os.getenv("PUBLIC_BASE_URL", "").rstrip("/")
OTA_ROOT = Path(os.getenv("OTA_STORAGE_DIR", "./ota-private")).resolve()
OTA_TTL = min(max(int(os.getenv("OTA_TTL_SECONDS", "3600")), 300), 86400)
OTA_ROOT.mkdir(parents=True, exist_ok=True)

def clear_expired():
    now = time.time()
    for path in OTA_ROOT.iterdir():
        if not path.is_dir():
            continue
        try:
            meta = json.loads((path / "meta.json").read_text())
            if float(meta["expires_at"]) < now:
                shutil.rmtree(path, ignore_errors=True)
        except (OSError, ValueError, KeyError, TypeError):
            # Never delete unfamiliar folders automatically.
            continue

def get_ipa_metadata(path):
    with zipfile.ZipFile(path) as archive:
        plist_candidates = [name for name in archive.namelist()
                            if name.startswith("Payload/") and name.count("/") == 2
                            and name.endswith(".app/Info.plist")]
        if len(plist_candidates) != 1:
            raise ValueError("IPA must contain one application Info.plist")
        info = plistlib.loads(archive.read(plist_candidates[0]))
    bundle = info.get("CFBundleIdentifier", "")
    version = info.get("CFBundleShortVersionString", "1.0")
    name = info.get("CFBundleDisplayName") or info.get("CFBundleName") or "Signed App"
    if not isinstance(bundle, str) or not bundle or not all(isinstance(x, str) for x in (version, name)):
        raise ValueError("Invalid IPA metadata")
    return {"bundle": bundle, "version": version, "name": name}

def checked_install(token):
    if len(token) != 48 or any(c not in "0123456789abcdef" for c in token):
        return None
    folder = OTA_ROOT / token
    try:
        meta = json.loads((folder / "meta.json").read_text())
        if time.time() >= float(meta["expires_at"]):
            shutil.rmtree(folder, ignore_errors=True)
            return None
        if not (folder / "signed.ipa").is_file():
            return None
        return folder, meta
    except (ValueError, OSError, KeyError, TypeError):
        return None

@app.get("/install/<token>/manifest.plist")
def install_manifest(token):
    found = checked_install(token)
    if not found:
        return "Not found", 404
    _, meta = found
    ipa_url = f"{PUBLIC_BASE_URL}/install/{token}/app.ipa"
    manifest = {"items": [{"assets": [{"kind": "software-package", "url": ipa_url}],
                           "metadata": {"bundle-identifier": meta["bundle"],
                                        "bundle-version": meta["version"],
                                        "kind": "software", "title": meta["name"]}}]}
    return Response(plistlib.dumps(manifest), content_type="application/xml", headers={"Cache-Control": "no-store"})

@app.get("/install/<token>/app.ipa")
def install_ipa(token):
    found = checked_install(token)
    if not found:
        return "Not found", 404
    folder, _ = found
    return send_file(folder / "signed.ipa", mimetype="application/octet-stream", as_attachment=True,
                     download_name="Oxygen-Signed.ipa", conditional=True)


@app.get("/health")
def health():
    return jsonify(ok=True)

@app.post("/api/sign")
@app.post("/api/sign/install")
def sign():
    wants_install = request.path.endswith("/install")
    if wants_install and (not PUBLIC_BASE_URL.startswith("https://") or PUBLIC_BASE_URL.endswith("/")):
        return jsonify(error="Set PUBLIC_BASE_URL to your public HTTPS signing domain"), 503
    clear_expired()
    if not VERIFY_URL or not VERIFY_URL.startswith("https://"):
        return jsonify(error="Administrator must configure HTTPS LICENSE_VERIFY_URL"), 503
    key = request.form.get("key", "")
    device = request.form.get("device_id", "")
    if not (1 <= len(key) <= 80 and 1 <= len(device) <= 150):
        return jsonify(error="Invalid license payload"), 400
    try:
        verified = requests.post(VERIFY_URL, json={"key": key, "device_id": device}, timeout=15)
        if verified.status_code != 200 or verified.json().get("valid") is not True:
            return jsonify(error="License rejected"), 403
    except (requests.RequestException, ValueError):
        return jsonify(error="License verification unavailable"), 503

    uploads = {k: request.files.get(k) for k in ("ipa", "p12", "profile")}
    if any(v is None for v in uploads.values()):
        return jsonify(error="Missing ipa / p12 / profile"), 400
    if not (uploads["ipa"].filename.lower().endswith(".ipa")
            and uploads["p12"].filename.lower().endswith(".p12")
            and uploads["profile"].filename.lower().endswith(".mobileprovision")):
        return jsonify(error="Invalid file types"), 400
    password = request.form.get("p12_password", "")
    temp = tempfile.TemporaryDirectory(prefix="oxygen-sign-")
    root = Path(temp.name)
    paths = {"ipa": root / "input.ipa", "p12": root / "cert.p12", "profile": root / "profile.mobileprovision"}
    try:
        for name, upload in uploads.items():
            upload.save(paths[name])
        output = root / "signed.ipa"
        # NOTE: zsign requires the p12 password as an argument; protect access to process listings.
        result = subprocess.run([ZSIGN, "-f", "-k", str(paths["p12"]), "-p", password,
                                 "-m", str(paths["profile"]), "-o", str(output),
                                 str(paths["ipa"])], capture_output=True, text=True, timeout=300)
        if result.returncode != 0 or not output.is_file():
            temp.cleanup()
            return jsonify(error="Signing failed. Check P12 password, profile and zsign logs."), 422
        if wants_install:
            try:
                metadata = get_ipa_metadata(output)
                token = secrets.token_hex(24)
                destination = OTA_ROOT / token
                destination.mkdir(mode=0o700)
                shutil.move(str(output), str(destination / "signed.ipa"))
                metadata["expires_at"] = int(time.time()) + OTA_TTL
                (destination / "meta.json").write_text(json.dumps(metadata), encoding="utf-8")
            except (ValueError, zipfile.BadZipFile, KeyError, OSError) as error:
                temp.cleanup()
                return jsonify(error=f"Cannot prepare install manifest: {error}"), 422
            temp.cleanup()
            return jsonify(ok=True,
                           ipa_url=f"{PUBLIC_BASE_URL}/install/{token}/app.ipa",
                           manifest_url=f"{PUBLIC_BASE_URL}/install/{token}/manifest.plist",
                           expires_at=metadata["expires_at"])
        @after_this_request
        def cleanup(response):
            response.call_on_close(temp.cleanup)
            return response
        return send_file(output, as_attachment=True, download_name="Oxygen-Signed.ipa", mimetype="application/octet-stream")
    except (OSError, subprocess.TimeoutExpired):
        temp.cleanup()
        return jsonify(error="Signing engine unavailable or timed out"), 503
