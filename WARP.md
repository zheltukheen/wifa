# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Essential commands

Build (Release, universal arm64 + x86_64) — produces build/WiFA-Universal/WiFA.app

Output structure:
- Debug builds: build/DerivedData/Build/Products/Debug/WiFA.app
- Release builds: build/WiFA-Universal/WiFA.app (archive removed by default)

```bash
./build.sh
```

Open in Xcode (recommended for iterative dev/run)

```bash
open WiFA.xcodeproj
```

CLI builds with xcodebuild

```bash
# Debug build for macOS
xcodebuild build \
  -scheme WiFA \
  -configuration Debug \
  -destination 'platform=macOS'

# Clean
xcodebuild clean -scheme WiFA -destination 'platform=macOS'

# Open the built app after ./build.sh
open build/WiFA-Universal/WiFA.app
```

Debug build and run from CLI

```bash
# Build Debug into a known DerivedData path and open the app
xcodebuild build \
  -scheme WiFA \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData && \
open build/DerivedData/Build/Products/Debug/WiFA.app
```

Tests

- No unit tests are present in this repo at the moment. If/when XCTest targets are added, you can run a single test from CLI with:

```bash
xcodebuild test \
  -scheme WiFA \
  -destination 'platform=macOS' \
  -only-testing:<TestTarget>/<TestCase>/<testMethod>
```

Lint/format

- No lint/format tool is configured in the repo (e.g., SwiftLint/SwiftFormat are not present).

## Other useful CLI snippets

- Update OUI vendor list into Resources/oui from IEEE registry (requires Python 3):

```bash
python3 scripts/update_oui.py   # downloads and writes Resources/oui
# or with a local file:
python3 scripts/update_oui.py path/to/oui.txt
```

- Resolve the app’s bundle identifier from the Xcode project:

```bash
xcodebuild -showBuildSettings \
  -scheme WiFA \
  -destination 'platform=macOS' \
  | awk -F' = ' '/PRODUCT_BUNDLE_IDENTIFIER/ {print $2; exit}'
```

- Reset saved UI preferences (column order/visibility/widths, refresh interval):

```bash
BID=$(xcodebuild -showBuildSettings -scheme WiFA -destination 'platform=macOS' | awk -F' = ' '/PRODUCT_BUNDLE_IDENTIFIER/ {print $2; exit}')
for k in ColumnOrder ColumnVisibility ColumnWidths RefreshIntervalSeconds; do
  defaults delete "$BID" "$k" 2>/dev/null || true
done
```

## High-level architecture

Platform and UI

- Native macOS app using SwiftUI for screens plus an AppKit NSTableView bridged via NSViewRepresentable for a performant, highly customizable table.
- Entry point WifiAnalyzerApp creates a single AnalyzerViewModel and shows MainTableView; the table itself is implemented in Views/WiFiTableView.swift using a Coordinator as NSTableView delegate/data source.

State and view model

- AnalyzerViewModel (MainActor, ObservableObject) owns the app state: the list of networks, error messages, column definitions (visibility, width, order), refresh interval, and sort state.
- Periodic refresh is driven by a Timer (default 2s) that triggers WiFi scans when Location Services are authorized. Sorting is applied on receipt of new scan results.
- User preferences persist to UserDefaults with keys: `WifiColumns_v2` (column order/visibility/widths) and `RefreshIntervalSeconds`.

Table implementation (AppKit bridge)

- WiFiTableView builds NSTableView columns from the current columnDefinitions, maintains a signature of the last-applied configuration to avoid redundant work, and performs in-place diffs when visibility/order/width change.
- Sorting integrates with NSTableView sort descriptors; the Coordinator syncs the table’s sort indicator with the view model (currentSortKey/isSortAscending) and updates sortDescriptors only when they drift.
- Column reordering is observed via NSTableView.columnDidMoveNotification; new order is written back to the view model and persisted.

Scanning and data model

- WiFiScanner (Services) uses only public CoreWLAN APIs (CWWiFiClient/CWNetwork) to scan and build NetworkModel.
  - No runtime reflection or private parsing; fields are derived from official properties like SSID/BSSID, RSSI, noise, channel, band/width, beacon interval, country code, and IBSS.
  - Security and generation are inferred via `supportsSecurity` and `supportsPHYMode`.
  - A stable network id is computed from BSSID when available, with a safe fallback (SSID/band/channel/width/security) when Location Services are off.
  - firstSeen/lastSeen timestamps are maintained in AnalyzerViewModel to compute `seen`.
- OUIParser maps the BSSID prefix (OUI) to a vendor name via a small in-repo dictionary.
- NetworkModel aggregates both primary and advanced fields (e.g., basicRates, beaconInterval, channelUtilization, protectionMode, streams, wps) so the UI can selectively expose them.

Data flow

1. User opens app → WifiAnalyzerApp instantiates AnalyzerViewModel and shows MainTableView.
2. AnalyzerViewModel requests Location Services via LocationManager; if authorized, starts periodic Timer.
3. On each tick → WiFiScanner.scan() queries CoreWLAN and constructs [NetworkModel].
4. Back on MainActor, AnalyzerViewModel updates networks, applies current sort, and sets/clears error messages.
5. WiFiTableView reads columnDefinitions to render columns, diffs columns on updates, and reflects sort state via Coordinator.
6. User column moves/toggles update columnDefinitions → persisted to UserDefaults (`WifiColumns_v2`).

Permissions and requirements

- Location Services permission is required to display SSID/BSSID. The app requests authorization via Utils/LocationManager (CLLocationManager).
- Info.plist contains NSLocationUsageDescription to explain the need for access.
- README requirements: macOS 13+; works on Apple Silicon and Intel.

## Extending the table/fields

To add a new column that participates in sorting and persistence:

1. Add the property to `Models/NetworkModel.swift`.
2. Populate it in `Services/WiFiScanner.swift` when constructing `NetworkModel`.
3. Register the column in `ViewModels/AnalyzerViewModel.swift` under `ColumnDefinition.defaults` with a stable id, title, default visibility, and width.
4. Render the value in `Views/WiFiTableView.swift` inside `Coordinator.tableView(_:viewFor:row:)` by handling the id in the `switch`.
5. Make it sortable by adding a `case` to `AnalyzerViewModel.sort(by:ascending:)` that compares the new field. The `NSTableColumn` sort descriptor is already created from the id.
6. Sorting UI indicators are kept in sync by `Coordinator.updateSortIndicators()`.

## Notes for future agents

- The Xcode project is WiFA.xcodeproj with scheme WiFA. The provided build.sh archives a universal Release build and copies the .app into build/WiFA-Universal/.
- WiFiScanner intentionally avoids private CoreWLAN reflection to improve long-term stability across macOS releases.
