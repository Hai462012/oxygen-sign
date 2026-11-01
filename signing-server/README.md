# Oxygen Sign signing backend (real P12 signing via zsign)

This is a **separate** signing service, not a replacement for the existing Flask license server. Requires zsign installed and on PATH; see https://github.com/zhlynn/zsign .

1. Deploy on a **private, trusted server**. Set `LICENSE_VERIFY_URL=https://your-license-domain/api/verify` (must be HTTPS).
2. Install dependencies: `pip install -r requirements.txt`.
3. Start locally: `waitress-serve --host=127.0.0.1 --port=8090 server:app`.
4. Configure a reverse proxy with **HTTPS**, request upload limits, access logs without POST bodies, and network access restrictions. Set `ZSIGN_BIN` to the path to zsign when needed.
5. Set `PUBLIC_BASE_URL=https://your-signing-domain` and in iOS set `https://your-signing-domain/api/sign/install`. Signed IPA + manifest are hosted at a random URL for at most 1 hour (`OTA_TTL_SECONDS`).
6. Tap **Cài IPA lên iPhone** after signing; this opens the Apple OTA installer through `itms-services`.

**Security**: The app uploads the customer's P12, password, profile and IPA to YOUR server. This is sensitive signing material. Use a trusted private service, encrypted transport, minimum privileges, rate limits, isolation, careful retention/logging, and disable access when unneeded. Temporary files are cleaned after request completion; avoid persistent request-body logging and never share certificates with third-party endpoints. License verification is not a substitute for full abuse controls. API response does not promise successful device installation.

This implementation has not been live-tested with real P12 or Xcode here. A valid profile must match the app, capabilities and device installation entitlement. Not suitable for untrusted public deployment as-is.

## OTA notes
- Only expose this service over publicly trusted HTTPS. The server stores signed IPA artifacts temporarily under `OTA_STORAGE_DIR` (default `./ota-private`). URLs act as download credentials until expiry; limit access and do not print them into logs.
- Periodic cleanup is recommended in addition to opportunistic cleanup. Provisioning must permit installing onto the target device. Apple may reject installation despite successful signing.
- For security hardening before public deployment add authenticated upload quotas, storage limits, robust rate limiting and safe multipart handling.
