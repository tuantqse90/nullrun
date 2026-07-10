# ios/ — NullShift consumer app

iOS native app: Swift + SwiftUI. Source scaffold exists; the Xcode project is generated with XcodeGen.

> ⚠️ **Not compiled yet** — Xcode is not installed on the machine that wrote this scaffold.
> Expect minor fixes on first build.

## Generate & open

```sh
brew install xcodegen
cd ios
xcodegen generate
open NullShift.xcodeproj
```

## What's here

- `NullShift/Onboarding/` — phone → OTP flow against the backend (`/v1/auth/*`), permission priming (location "Always" two-step ask, motion)
- `NullShift/Core/` — `APIClient` (async URLSession), `AuthStore` (session state), `Keychain` (token storage — never UserDefaults)
- `project.yml` — Info.plist strings (VN copy), background-location mode, App Attest entitlement (development)

Backend must run locally (`docker-compose up -d && cd backend && cargo run`). Simulator uses `http://localhost:8080`; set your Mac's LAN IP in `APIClient.baseURL` for a physical device.

Key constraints (see root `CLAUDE.md`):
- Core Motion + CoreLocation with reliable background GPS — this IS the product.
- 3D body scan on-device: Core ML (MediaPipe pose + SMPL fitting). Raw images/mesh never leave the device.
- ZK proof generation on-device: Rust/Noir compiled for iOS, bridged via UniFFI.
- Device attestation via App Attest from day 1 (backend `ATTEST_MODE=apple` once real attestations exist).
