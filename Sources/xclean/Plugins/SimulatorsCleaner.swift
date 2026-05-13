import Foundation

/// Cleans iOS / watchOS / tvOS simulators via `xcrun simctl`.
///
/// Emits three kinds of candidates:
/// * **corruption** — devices in the "unavailable" state (e.g. missing runtime)
/// * **age**        — devices not booted within the profile age threshold
/// * **duplicate**  — older runtimes beyond the keep-N quota
/// * **generic**    — `~/Library/Developer/CoreSimulator/Caches` if non-empty
struct SimulatorsCleaner: Cleaner {
    let id = "simulators"
    let title = "iOS Simulators"

    func discover(config: RunConfig) throws -> [Candidate] {
        var out: [Candidate] = []

        // 1) simctl device inventory
        let devicesResult = Shell.xcrun(["simctl", "list", "devices", "-j"])
        if devicesResult.success, let data = devicesResult.stdout.data(using: .utf8) {
            out.append(contentsOf: discoverDevices(from: data, config: config))
        }

        // 2) Orphan / extra runtimes
        let runtimesResult = Shell.xcrun(["simctl", "runtime", "list", "-j"])
        if runtimesResult.success, let data = runtimesResult.stdout.data(using: .utf8) {
            out.append(contentsOf: discoverRuntimes(from: data, config: config))
        }

        // 3) CoreSimulator caches directory
        if FS.exists(Paths.coreSimulatorCaches) {
            let size = FS.sizeOf(Paths.coreSimulatorCaches)
            if size > 0 {
                out.append(Candidate(
                    cleanerID: id,
                    displayName: "CoreSimulator/Caches",
                    sizeBytes: size,
                    lastUsed: FS.lastModified(Paths.coreSimulatorCaches),
                    category: .generic,
                    detail: "global simulator cache",
                    removal: .path(Paths.coreSimulatorCaches)
                ))
            }
        }

        return out
    }

    // MARK: - simctl devices parsing

    private struct DeviceList: Decodable {
        let devices: [String: [Device]]
    }
    private struct Device: Decodable {
        let udid: String
        let name: String
        let state: String?
        let isAvailable: Bool?
        let availabilityError: String?
        let lastBootedAt: String?
        let dataPath: String?
    }

    private func discoverDevices(from data: Data, config: RunConfig) -> [Candidate] {
        guard let list = try? JSONDecoder().decode(DeviceList.self, from: data) else { return [] }
        var out: [Candidate] = []
        // simctl emits ISO timestamps in both forms (with and without fractional
        // seconds). ISO8601DateFormatter is strict about the flag matching, so
        // we try both.
        let isoExact = ISO8601DateFormatter()
        isoExact.formatOptions = [.withInternetDateTime]
        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso: (String) -> Date? = { s in isoExact.date(from: s) ?? isoFractional.date(from: s) }

        for (runtime, devices) in list.devices {
            for d in devices {
                let folder = d.dataPath.map { URL(fileURLWithPath: $0) }
                let size = folder.map { FS.sizeOf($0) } ?? 0

                if d.isAvailable == false {
                    out.append(Candidate(
                        cleanerID: id,
                        displayName: "\(d.name) (unavailable)",
                        sizeBytes: size,
                        lastUsed: nil,
                        category: .corruption,
                        detail: d.availabilityError ?? "unavailable on \(runtime)",
                        removal: .simulatorDevice(udid: d.udid, name: d.name)
                    ))
                    continue
                }

                let lastUsed: Date? = d.lastBootedAt.flatMap { iso($0) }
                    ?? folder.flatMap { FS.lastModified($0) }

                if let when = lastUsed {
                    let days = Classifier.daysSince(when)
                    if days >= config.profile.ageThresholdDays {
                        out.append(Candidate(
                            cleanerID: id,
                            displayName: d.name,
                            sizeBytes: size,
                            lastUsed: when,
                            category: .age,
                            detail: "not booted in \(days)d (\(runtime))",
                            removal: .simulatorDevice(udid: d.udid, name: d.name)
                        ))
                    }
                }
            }
        }
        return out
    }

    // MARK: - simctl runtime parsing

    private struct Runtime: Decodable {
        let identifier: String
        let version: String?
        let platform: String?
        let runtimeName: String?
        let kind: String?     // .legacyRuntime, .image, etc on newer Xcode
        let state: String?    // "Ready", etc
        let mountPath: String?
    }

    private func discoverRuntimes(from data: Data, config: RunConfig) -> [Candidate] {
        guard let runtimes = try? JSONDecoder().decode([String: Runtime].self, from: data) else { return [] }
        // Group by platform; keep N most recent (by version) per group.
        let grouped = Dictionary(grouping: runtimes.values) { $0.platform ?? "Unknown" }
        var out: [Candidate] = []
        let keep = max(0, config.profile.keepSimulatorRuntimes)

        for (_, items) in grouped {
            let sorted = items.sorted { lhs, rhs in
                (lhs.version ?? "") > (rhs.version ?? "")
            }
            guard sorted.count > keep else { continue }
            for r in sorted.dropFirst(keep) {
                let size: UInt64 = r.mountPath.map { FS.sizeOf(URL(fileURLWithPath: $0)) } ?? 0
                let name = r.runtimeName ?? "\(r.platform ?? "?") \(r.version ?? "?")"
                out.append(Candidate(
                    cleanerID: id,
                    displayName: name,
                    sizeBytes: size,
                    lastUsed: nil,
                    category: .duplicate,
                    detail: "extra runtime beyond keep=\(keep)",
                    removal: .simulatorRuntime(identifier: r.identifier, name: name)
                ))
            }
        }
        return out
    }
}
