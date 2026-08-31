# GARMIN BUILD REPORT

Date: 2026-08-31

| Item | Value |
| --- | --- |
| Target | `fenix7pro` |
| Jungle file | `app/fenix7-v1.jungle` |
| SDK / compiler | Connect IQ SDK 8.4.1 / monkeyc 8.4.1 |
| Build flags | `-d fenix7pro -l 2 -r -O z` |
| Build result | PASS |
| Compile errors | 0 |
| PRG path | `/Users/dove/Documents/BatteryGuesstimate/Artifacts/Release/BatteryTelemetry-fenix7pro.prg` |
| PRG size | 57,724 bytes |
| PRG SHA-256 | `4a8a6773645deba1dd4680d6e3f621aaee57dd2b1b2411caafbaffc41fc46fe6` |
| Manifest UUID | `05d38102-5aa5-4628-be94-94665e629840` |
| Background permission | Present |
| Communications permission | Present |
| SensorHistory permission | Present |
| Legacy Graph/History/WebDAV production path | Not compiled |

The production build uses the lightweight source allowlist in
`app/fenix7-v1.jungle`. Graph, History, watch-side analytics, WebDAV export, and
legacy UI delegates are not part of this PRG.

Test PRG compilation also succeeded (`tests/fenix7-v1.jungle`, `BUILD
SUCCESSFUL`). Simulator/device execution was not completed in this round
because the user asked to focus on code work and to not consider real-device
testing/matching.

## Developer key note

No pre-existing Garmin developer key was found on this machine. The PRG was
signed with a freshly generated local PKCS#8 key at
`/tmp/battery_devkey_pkcs8.der`. It is a valid compiler-signed PRG, but it is
not tied to an existing Garmin developer account key; replace the key file and
rebuild before installing on a production watch if account-matching is
required.
