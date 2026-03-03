import Foundation

@MainActor
final class QuickControlsState: ObservableObject {

    // MARK: - Displays
    @Published var isDarkMode: Bool = false
    @Published var accentColorValue: Int? = nil
    @Published var displayName: String?
    @Published var displayResolution: String?
    @Published var gpuName: String?
    @Published var gpuCores: String?
    @Published var metalVersion: String?
    @Published var autoBrightness: Bool = false

    // MARK: - Sound
    @Published var outputVolume: Int?
    @Published var isOutputMuted: Bool = false
    @Published var inputVolume: Int?
    @Published var alertVolume: Int?
    @Published var defaultOutputDevice: String?
    @Published var defaultInputDevice: String?

    // MARK: - Mouse
    @Published var mouseTrackingSpeed: Double = 1.0
    @Published var mouseScrollSpeed: Double = 1.0
    @Published var isNaturalScrollEnabled: Bool = true

    // MARK: - Trackpad
    @Published var trackpadTrackingSpeed: Double = 1.0
    @Published var isTapToClickEnabled: Bool = false
    @Published var isThreeFingerDragEnabled: Bool = false

    // MARK: - Keyboard
    @Published var keyRepeatInterval: Double = 0.083
    @Published var keyRepeatDelay: Double = 0.5

    // MARK: - Wi-Fi
    @Published var isWiFiEnabled: Bool = true
    @Published var currentSSID: String?
    @Published var wifiMACAddress: String?

    // MARK: - Bluetooth
    @Published var isBluetoothOn: Bool = false
    @Published var bluetoothVersion: String?
    @Published var connectedBluetoothDevices: [String] = []
    @Published var pairedBluetoothDevices: [String] = []

    // MARK: - Network
    @Published var localIP: String?
    @Published var dnsServers: [String] = []
    @Published var routerIP: String?
    @Published var subnetMask: String?

    // MARK: - Battery
    @Published var batteryPercentage: Int?
    @Published var isBatteryCharging: Bool = false
    @Published var isBatteryPluggedIn: Bool = false
    @Published var batteryCycleCount: Int?
    @Published var batteryCondition: String?
    @Published var batteryMaxCapacity: String?
    @Published var batteryTimeRemaining: String?

    // MARK: - Accessibility
    @Published var isReduceMotionEnabled: Bool = false
    @Published var isReduceTransparencyEnabled: Bool = false
    @Published var isIncreaseContrastEnabled: Bool = false

    // MARK: - Focus
    @Published var isFocusEnabled: Bool = false

    // MARK: - Date & Time
    @Published var is24HourClock: Bool = false
    @Published var currentTimezone: String = ""

    // MARK: - Login Items
    @Published var loginItems: [String] = []

    // MARK: - Software Update
    @Published var pendingUpdates: Int?
    @Published var lastUpdateCheck: String?

    private(set) var loadedDestinationID: String?
    private let service = SystemControlService()

    // MARK: - Load

    func loadValues(for destinationID: String) {
        guard loadedDestinationID != destinationID else { return }
        loadedDestinationID = destinationID

        Task {
            switch destinationID {
            case "displays":
                isDarkMode = await service.isDarkModeEnabled()
                accentColorValue = await service.accentColor()
                let info = await service.displayInfo()
                displayName = info.displayName
                displayResolution = info.resolution
                gpuName = info.gpuName
                gpuCores = info.gpuCores
                metalVersion = info.metalVersion
                autoBrightness = info.autoBrightness
            case "sound":
                outputVolume = await service.outputVolume()
                isOutputMuted = await service.isOutputMuted()
                inputVolume = await service.inputVolume()
                alertVolume = await service.alertVolume()
                defaultOutputDevice = await service.defaultOutputDevice()
                defaultInputDevice = await service.defaultInputDevice()
            case "mouse":
                if let s = await service.mouseTrackingSpeed() { mouseTrackingSpeed = s }
                if let s = await service.mouseScrollSpeed() { mouseScrollSpeed = s }
                isNaturalScrollEnabled = await service.isNaturalScrollEnabled()
            case "trackpad":
                if let s = await service.trackpadTrackingSpeed() { trackpadTrackingSpeed = s }
                isTapToClickEnabled = await service.isTapToClickEnabled()
                isThreeFingerDragEnabled = await service.isThreeFingerDragEnabled()
            case "keyboard":
                if let r = await service.keyRepeatInterval() { keyRepeatInterval = r }
                if let d = await service.keyRepeatDelay() { keyRepeatDelay = d }
            case "wifi":
                isWiFiEnabled = await service.isWiFiEnabled()
                currentSSID = await service.currentSSID()
                wifiMACAddress = await service.wifiMACAddress()
            case "bluetooth":
                isBluetoothOn = await service.bluetoothPowerState()
                bluetoothVersion = await service.bluetoothVersion()
                connectedBluetoothDevices = await service.connectedBluetoothDevices()
                pairedBluetoothDevices = await service.pairedBluetoothDevices()
            case "network":
                localIP = await service.localIPAddress()
                dnsServers = await service.dnsServers()
                routerIP = await service.routerIP()
                subnetMask = await service.subnetMask()
            case "battery":
                let info = await service.batteryInfo()
                batteryPercentage = info.percentage
                isBatteryCharging = info.isCharging
                isBatteryPluggedIn = info.isPluggedIn
                batteryCycleCount = info.cycleCount
                batteryCondition = info.condition
                batteryMaxCapacity = info.maxCapacity
                batteryTimeRemaining = info.timeRemaining
            case "accessibility":
                isReduceMotionEnabled = await service.isReduceMotionEnabled()
                isReduceTransparencyEnabled = await service.isReduceTransparencyEnabled()
                isIncreaseContrastEnabled = await service.isIncreaseContrastEnabled()
            case "notifications":
                isFocusEnabled = await service.isFocusEnabled()
            case "date-time":
                is24HourClock = await service.is24HourClock()
                currentTimezone = await service.currentTimezone()
            case "login-items":
                loginItems = await service.loginItems()
            case "software-update":
                pendingUpdates = await service.pendingUpdateCount()
                lastUpdateCheck = await service.lastCheckDate()
            default:
                break
            }
        }
    }

    func invalidate() {
        loadedDestinationID = nil
    }
}
