# WiFA — Native macOS Wi‑Fi Analyzer

WiFA is a native macOS Wi‑Fi scanner and analyzer built on CoreWLAN. It provides a fast live table, spectrum/history charts, and a detailed “Raw Data” view of information elements (IEs) without relying on external parsing tools.

## Highlights
- Live scanning with configurable refresh interval
- Extensive column set (signal, security, channel, bandwidth, vendor, rates, timing, etc.)
- Spectrum and History charts
- Raw Data tab with expandable Information Elements and detailed decoding
- Sidebar filters for quick exploration
- CSV export

## Requirements
- macOS 13+
- Location Services permission (required by macOS to access BSSID/SSID)

## Build & Run
```bash
./build.sh
```
Result: `build/WiFA-Universal/WiFA.app`

Open the `.app` file to run.

## Permissions
macOS requires Location Services permission to reveal SSID/BSSID.  
If the system prompt is not shown, enable it manually:
**System Settings → Privacy & Security → Location Services → WiFA**

## Menu Bar Commands
WiFA adds useful commands to the macOS menu bar:
- **Scan**: Refresh, interval selection, custom interval
- **Filters**: Band filters, minimum signal threshold, clear quick filters
- **Display**: Signal units, highlight connected network
- **Panels**: Toggle sidebar/inspector, choose bottom panel
- **Data**: Export CSV

## Release Process
1. Add a new section to `CHANGELOG.md` (keep history, do not replace):
   ```
   ## 1.2.1 — 2026-02-08
   - Added …
   ```
2. Run the release script:
   ```bash
   ./release.sh 1.2.1
   ```
   This updates `Info.plist`, commits all changes, pushes `main`, creates tag `v1.2.1`, and triggers the automated GitHub Release workflow (build + zip + sha256).

## Data Sources & Limitations
WiFA uses CoreWLAN APIs only (no external CLI parsing).  
Some advanced fields depend on beacon IE availability; if an AP does not broadcast a specific IE, values are shown as “-”.

## Project Structure
```
Models/        Data models and types
Services/      Core scanning and parsing
ViewModels/    App logic and state
Views/         SwiftUI/AppKit UI
Utils/         Helpers (OUI vendor lookup, location)
Resources/     OUI databases
```

## Troubleshooting
- **No networks / missing BSSID/SSID**: check Location Services permission.
- **Vendor missing**: ensure `Resources/oui` or `Resources/oui.csv` is bundled.

## License
MIT (or update as needed).
