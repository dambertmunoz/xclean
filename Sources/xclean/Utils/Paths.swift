import Foundation

enum Paths {
    static let home: URL = {
        let h = FileManager.default.homeDirectoryForCurrentUser
        return h
    }()

    private static func dev(_ tail: String) -> URL {
        return home.appendingPathComponent("Library/Developer/" + tail)
    }
    private static func caches(_ tail: String) -> URL {
        return home.appendingPathComponent("Library/Caches/" + tail)
    }

    // Xcode
    static let derivedData       = dev("Xcode/DerivedData")
    static let archives          = dev("Xcode/Archives")
    static let iOSDeviceSupport  = dev("Xcode/iOS DeviceSupport")
    static let watchOSDeviceSupport = dev("Xcode/watchOS DeviceSupport")
    static let tvOSDeviceSupport = dev("Xcode/tvOS DeviceSupport")
    static let moduleCache       = dev("Xcode/DerivedData/ModuleCache.noindex")

    // CoreSimulator
    static let coreSimulator        = dev("CoreSimulator")
    static let coreSimulatorDevices = dev("CoreSimulator/Devices")
    static let coreSimulatorCaches  = dev("CoreSimulator/Caches")

    // Caches
    static let cocoaPodsCache = caches("CocoaPods")
    static let spmCache       = caches("org.swift.swiftpm")
    static let carthageCache  = caches("org.carthage.CarthageKit")

    static let trash = home.appendingPathComponent(".Trash")
}
