import Combine
import Foundation
import IOKit.hid

private func hidMouseMatchingDictionaries() -> [[String: Any]] {
    [
        [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Mouse
        ]
    ]
}

private func hidDeviceChangeCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice?
) {
    guard let context else {
        return
    }

    let monitor = Unmanaged<InputDeviceMonitor>.fromOpaque(context).takeUnretainedValue()
    monitor.refreshState()
}

protocol InputDeviceDetecting {
    func hasMouseDevice() -> Bool
}

struct InputDeviceDetector: InputDeviceDetecting {
    func hasMouseDevice() -> Bool {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(manager, hidMouseMatchingDictionaries() as CFArray)

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            return false
        }

        defer {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        return InputDeviceMonitor.mouseDeviceCount(from: manager) > 0
    }
}

final class InputDeviceMonitor: ObservableObject, InputDeviceDetecting {
    @Published private(set) var isMouseConnected: Bool

    private let manager: IOHIDManager
    private var isStarted = false

    init(initialDetector: InputDeviceDetecting = InputDeviceDetector()) {
        self.manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.isMouseConnected = initialDetector.hasMouseDevice()
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    func hasMouseDevice() -> Bool {
        isMouseConnected
    }

    private func startMonitoring() {
        guard !isStarted else {
            return
        }

        isStarted = true
        IOHIDManagerSetDeviceMatchingMultiple(manager, hidMouseMatchingDictionaries() as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, hidDeviceChangeCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, hidDeviceChangeCallback, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        _ = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        refreshState()
    }

    private func stopMonitoring() {
        guard isStarted else {
            return
        }

        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        isStarted = false
    }

    fileprivate func refreshState() {
        let hasMouse = Self.mouseDeviceCount(from: manager) > 0
        if isMouseConnected != hasMouse {
            isMouseConnected = hasMouse
        }
    }

    fileprivate static func mouseDeviceCount(from manager: IOHIDManager) -> Int {
        guard let rawDevices = IOHIDManagerCopyDevices(manager) else {
            return 0
        }

        let devices = rawDevices as NSSet
        var count = 0

        for case let device as IOHIDDevice in devices {
            if isExternalMouseDevice(device) {
                count += 1
            }
        }

        return count
    }

    private static func isExternalMouseDevice(_ device: IOHIDDevice) -> Bool {
        guard let usagePage = intProperty(device, key: kIOHIDPrimaryUsagePageKey as CFString),
              usagePage == Int(kHIDPage_GenericDesktop),
              let usage = intProperty(device, key: kIOHIDPrimaryUsageKey as CFString),
              usage == Int(kHIDUsage_GD_Mouse) else {
            return false
        }

        if let isBuiltIn = boolProperty(device, key: kIOHIDBuiltInKey as CFString), isBuiltIn {
            return false
        }

        if let transport = stringProperty(device, key: kIOHIDTransportKey as CFString)?
            .uppercased()
            .trimmingCharacters(in: .whitespacesAndNewlines),
           ["FIFO", "SPI", "I2C"].contains(transport) {
            return false
        }

        if let productName = stringProperty(device, key: kIOHIDProductKey as CFString)?
            .lowercased(),
           productName.contains("trackpad") {
            return false
        }

        return true
    }

    private static func intProperty(_ device: IOHIDDevice, key: CFString) -> Int? {
        guard let value = IOHIDDeviceGetProperty(device, key) else {
            return nil
        }

        if CFGetTypeID(value) == CFNumberGetTypeID() {
            return (value as? NSNumber)?.intValue
        }

        return nil
    }

    private static func boolProperty(_ device: IOHIDDevice, key: CFString) -> Bool? {
        guard let value = IOHIDDeviceGetProperty(device, key) else {
            return nil
        }

        if CFGetTypeID(value) == CFBooleanGetTypeID() {
            return (value as! CFBoolean) == kCFBooleanTrue
        }

        if CFGetTypeID(value) == CFNumberGetTypeID() {
            return (value as? NSNumber)?.boolValue
        }

        return nil
    }

    private static func stringProperty(_ device: IOHIDDevice, key: CFString) -> String? {
        guard let value = IOHIDDeviceGetProperty(device, key) else {
            return nil
        }

        if CFGetTypeID(value) == CFStringGetTypeID() {
            return value as? String
        }

        return nil
    }
}
