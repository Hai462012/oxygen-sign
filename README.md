# Oxygen Sign iOS — IPA signing upgrade

Includes SwiftUI iOS 15+ app, GitHub Actions unsigned IPA workflow, and a **real signing server integration** using zsign.

## Use

1. Upload this project to GitHub, open **Actions → Build Oxygen Sign Unsigned IPA**, and download the build artifact.
2. Deploy `signing-server/` on a **trusted HTTPS host** with `zsign` installed, and configure `LICENSE_VERIFY_URL` to your HTTPS Flask license verification endpoint.
3. In the app: activate license, import IPA, P12, mobileprovision through Files, open **Ký IPA bằng P12**, enter P12 password and HTTPS `/api/sign/install` URL, select files and sign.
4. A resulting IPA is saved to the app file manager; tap **Cài IPA lên iPhone** to open the OTA manifest install link, or share/export via Share Sheet.

## Implemented vs limitations

- **Implemented in source**: HTTPS OTA hosting with expiring random URL, manifest.plist, post-sign **Cài IPA** action; multipart streaming upload of IPA+P12+profile, HTTPS request to your signing server; server validates license+device, executes `zsign -k -p -m -o`, returns signed IPA; import/export and certificate picker.
- **Not implemented**: on-device offline signing, full ESign feature parity, native iOS26 Liquid Glass effects, Share Extension (OS share-to Files works).
- This is a source delivery, **not verified to compile on macOS or to sign a real IPA in this environment**. GitHub Actions builds unsigned IPA, which needs signing to install on iPhone.
- Current legacy license app URL uses plain HTTP and permits ATS exception only for that domain. Migrate license server to HTTPS before production. The new signing API **requires HTTPS**.
- Signing only succeeds when P12+profile match and Apple permits the target app/device. The app never stores P12 password, but uploads it securely to *your server* for each request.

See `signing-server/README.md` for server setup and security requirements.

## OTA installation caveats
- Set `PUBLIC_BASE_URL=https://sign.example.com` on the signing server and use `/api/sign/install` in the app. HTTPS must be publicly reachable and trusted by iOS; port 80 plain HTTP will not work for the installer.
- iOS OTA installation only works where Apple permits distribution of that signed app: matching Ad Hoc registration, authorized Enterprise distribution, etc. Ordinary development/App Store profiles are not guaranteed to work this way.
- The server temporarily holds **signed IPAs**, and the installation link is a bearer URL valid for `OTA_TTL_SECONDS` (default one hour). Treat links as private. Cleanup runs opportunistically when requests arrive; use a scheduled cleanup service for robust storage retention.
- `itms-services` must be opened by iOS on the target iPhone; OS prompts and trust restrictions apply.
- No iOS build or end-to-end install verified here.
