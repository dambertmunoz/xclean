# xclean

Smart disk-space reclaimer for the macOS / Xcode ecosystem.

`xclean` finds and safely removes cache, build, and orphaned files left behind
by Xcode, the iOS Simulator, CocoaPods, Swift Package Manager and Carthage.
It defaults to a non-destructive dry run, moves removals to the system Trash,
and uses heuristics (age, orphan, corruption, duplication) instead of blanket
deletes.

## Install

```sh
swift build -c release
cp .build/release/xclean /usr/local/bin/
```

## Quickstart

```sh
# Show what would be cleaned (no changes)
xclean scan

# Clean interactively (asks per category)
xclean clean

# Clean everything that matches the balanced profile, no questions
xclean clean --yes

# Aggressive cleanup (older thresholds, touches Archives)
xclean clean --profile aggressive --yes

# Restrict scope
xclean clean --only derived-data,simulators

# Inspect specific plugin findings
xclean doctor simulators
```

## What it cleans

| Plugin | Looks at |
| --- | --- |
| `derived-data` | `~/Library/Developer/Xcode/DerivedData/*` (age + orphan workspace) |
| `archives` | `~/Library/Developer/Xcode/Archives/*` (age, conservative skips) |
| `device-support` | `~/Library/Developer/Xcode/iOS DeviceSupport`, watchOS, tvOS (keep last N) |
| `module-cache` | `~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex` |
| `simulators` | `xcrun simctl` unavailable devices, idle devices, orphan runtimes |
| `cocoapods` | `~/Library/Caches/CocoaPods` |
| `spm` | `~/Library/Caches/org.swift.swiftpm` |
| `carthage` | `~/Library/Caches/org.carthage.CarthageKit` |

## Safety model

* Dry run by default. Nothing is touched until you pass `--apply` or run `clean`.
* Removals are moved to `~/.Trash/xclean-<timestamp>/` so you can restore.
* `--purge` skips the Trash and deletes directly. Use with care.
* `--profile conservative` keeps Archives, recent device supports, and uses a
  larger age threshold.

## Profiles

| | conservative | balanced (default) | aggressive |
| --- | --- | --- | --- |
| Age threshold (days) | 60 | 30 | 14 |
| Keep N device supports | 5 | 3 | 2 |
| Keep N simulator runtimes | 3 | 2 | 1 |
| Touches Archives | no | no | yes (>180d) |
| Touches CocoaPods cache | yes | yes | yes |

## License

MIT
