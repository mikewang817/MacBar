import Combine
import Foundation
import IOKit.hid

private func hidMouseMatchingDictionaries() -> [[String: Any]] {
    [
        [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Mouse
        ],
        [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Pointer
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
        return devices.count
    }
}
