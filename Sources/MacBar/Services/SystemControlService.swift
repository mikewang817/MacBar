import Foundation

final class SystemControlService: Sendable {

    // MARK: - Dark Mode (read-only)

    func isDarkModeEnabled() async -> Bool {
        let result = await runShell("defaults read -g AppleInterfaceStyle")
        return result.trimmed == "Dark"
    }

    // MARK: - Accent Color (read-only)

    func accentColor() async -> Int? {
        let result = await runShell("defaults read -g AppleAccentColor")
        return Int(result.trimmed)
    }

    // MARK: - Display Hardware (read-only via system_profiler)

    struct DisplayInfo {
        let displayName: String?
        let resolution: String?
        let gpuName: String?
        let gpuCores: String?
        let metalVersion: String?
        let autoBrightness: Bool
    }

    func displayInfo() async -> DisplayInfo {
        let raw = await runShell("system_profiler SPDisplaysDataType 2>/dev/null")

        let displayName = raw.lineValue(after: "Display Type:")
            ?? raw.lineValue(after: "Display Name:")
        let resolution = raw.lineValue(after: "Resolution:")
        let gpuName = raw.lineValue(after: "Chipset Model:")
        let gpuCores = raw.lineValue(after: "Total Number of Cores:")
        let metalVersion = raw.lineValue(after: "Metal Support:")
            ?? raw.lineValue(after: "Metal Family:")
        let autoBrightness = raw.lineValue(after: "Automatically Adjust Brightness:")?.lowercased() == "yes"

        return DisplayInfo(
            displayName: displayName,
            resolution: resolution,
            gpuName: gpuName,
            gpuCores: gpuCores,
            metalVersion: metalVersion,
            autoBrightness: autoBrightness
        )
    }

    // MARK: - Volume (read-only)

    func outputVolume() async -> Int? {
        let result = await runShell("osascript -e 'output volume of (get volume settings)'")
        return Int(result.trimmed)
    }

    func isOutputMuted() async -> Bool {
        let result = await runShell("osascript -e 'output muted of (get volume settings)'")
        return result.trimmed == "true"
    }

    func inputVolume() async -> Int? {
        let result = await runShell("osascript -e 'input volume of (get volume settings)'")
        return Int(result.trimmed)
    }

    func alertVolume() async -> Int? {
        let result = await runShell("osascript -e 'alert volume of (get volume settings)'")
        return Int(result.trimmed)
    }

    // MARK: - Audio Devices (read-only via system_profiler)

    func defaultOutputDevice() async -> String? {
        let result = await runShell(
            "system_profiler SPAudioDataType 2>/dev/null | awk '/Output/,/Default/' | grep 'Default.*Yes' -B5 | head -1 | sed 's/^ *//' | sed 's/:$//' "
        )
        let name = result.trimmed
        return name.isEmpty ? nil : name
    }

    func defaultInputDevice() async -> String? {
        let result = await runShell(
            "system_profiler SPAudioDataType 2>/dev/null | awk '/Input/,/Default/' | grep 'Default.*Yes' -B5 | head -1 | sed 's/^ *//' | sed 's/:$//' "
        )
        let name = result.trimmed
        return name.isEmpty ? nil : name
    }

    // MARK: - Mouse (read-only)

    func mouseTrackingSpeed() async -> Double? {
        let result = await runShell("defaults read -g com.apple.mouse.scaling")
        return Double(result.trimmed)
    }

    func mouseScrollSpeed() async -> Double? {
        let result = await runShell("defaults read -g com.apple.scrollwheel.scaling")
        return Double(result.trimmed)
    }

    func isNaturalScrollEnabled() async -> Bool {
        let result = await runShell("defaults read -g com.apple.swipescrolldirection")
        return result.trimmed == "1"
    }

    // MARK: - Trackpad (read-only)
    // Check both com.apple.AppleMultitouchTrackpad AND com.apple.driver.AppleBluetoothMultitouch.trackpad
    // because they can have different values; if either is enabled the feature is on.

    func trackpadTrackingSpeed() async -> Double? {
        let result = await runShell("defaults read -g com.apple.trackpad.scaling")
        return Double(result.trimmed)
    }

    func isTapToClickEnabled() async -> Bool {
        let r1 = await runShell("defaults read com.apple.AppleMultitouchTrackpad Clicking")
        let r2 = await runShell("defaults read com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking")
        return r1.trimmed == "1" || r2.trimmed == "1"
    }

    func isThreeFingerDragEnabled() async -> Bool {
        let r1 = await runShell("defaults read com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag")
        let r2 = await runShell("defaults read com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag")
        return r1.trimmed == "1" || r2.trimmed == "1"
    }

    // MARK: - Keyboard (read-only)
    // Modern macOS stores key repeat in com.apple.Accessibility, not global domain

    func keyRepeatInterval() async -> Double? {
        let result = await runShell("defaults read com.apple.Accessibility KeyRepeatInterval")
        return Double(result.trimmed)
    }

    func keyRepeatDelay() async -> Double? {
        let result = await runShell("defaults read com.apple.Accessibility KeyRepeatDelay")
        return Double(result.trimmed)
    }

    // MARK: - Wi-Fi (read-only)

    func isWiFiEnabled() async -> Bool {
        let result = await runShell("networksetup -getairportpower en0")
        return result.lowercased().contains("on")
    }

    func currentSSID() async -> String? {
        let result = await runShell("networksetup -getairportnetwork en0")
        guard result.contains(":") else { return nil }
        let ssid = result.components(separatedBy: ":").last?.trimmed
        return (ssid?.isEmpty == false) ? ssid : nil
    }

    func wifiMACAddress() async -> String? {
        let result = await runShell("networksetup -getmacaddress en0 | awk '{print $3}'")
        let mac = result.trimmed
        return mac.isEmpty ? nil : mac
    }

    // MARK: - Bluetooth (read-only via system_profiler)

    func bluetoothPowerState() async -> Bool {
        let result = await runShell("system_profiler SPBluetoothDataType 2>/dev/null | grep 'State:' | head -1 | awk '{print $2}'")
        return result.trimmed == "On"
    }

    func bluetoothVersion() async -> String? {
        let result = await runShell("system_profiler SPBluetoothDataType 2>/dev/null | grep 'Bluetooth Low Energy' | head -1 | awk -F': ' '{print $2}'")
        let v = result.trimmed
        return v.isEmpty ? nil : v
    }

    func connectedBluetoothDevices() async -> [String] {
        let result = await runShell(
            "system_profiler SPBluetoothDataType 2>/dev/null | awk '/Connected:/{found=1; next} found && /^          [^ ]/{gsub(/:$/,\"\"); gsub(/^ +/,\"\"); print} found && /^      [^ ]/{found=0}'"
        )
        let trimmed = result.trimmed
        guard !trimmed.isEmpty else { return [] }
        return trimmed.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    func pairedBluetoothDevices() async -> [String] {
        let result = await runShell(
            "system_profiler SPBluetoothDataType 2>/dev/null | awk '/Paired:/{found=1; next} found && /^          [^ ]/{gsub(/:$/,\"\"); gsub(/^ +/,\"\"); print} found && /^      [^ ]/{found=0}'"
        )
        let trimmed = result.trimmed
        guard !trimmed.isEmpty else { return [] }
        return trimmed.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    // MARK: - Network (read-only)

    func localIPAddress() async -> String? {
        let result = await runShell("ipconfig getifaddr en0")
        let ip = result.trimmed
        return ip.isEmpty ? nil : ip
    }

    func dnsServers() async -> [String] {
        let result = await runShell("scutil --dns | grep 'nameserver\\[0\\]' | head -3 | awk '{print $3}'")
        return result.trimmed.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    func routerIP() async -> String? {
        let result = await runShell("netstat -rn | grep default | head -1 | awk '{print $2}'")
        let ip = result.trimmed
        return ip.isEmpty ? nil : ip
    }

    func subnetMask() async -> String? {
        let result = await runShell("ifconfig en0 | grep 'inet ' | awk '{print $4}'")
        let mask = result.trimmed
        return mask.isEmpty ? nil : mask
    }

    // MARK: - Battery (read-only)

    struct BatteryInfo {
        let percentage: Int?
        let isCharging: Bool
        let isPluggedIn: Bool
        let cycleCount: Int?
        let condition: String?
        let maxCapacity: String?
        let timeRemaining: String?
    }

    func batteryInfo() async -> BatteryInfo {
        async let pmsetResult = runShell("pmset -g batt")
        async let powerResult = runShell("system_profiler SPPowerDataType 2>/dev/null")

        let pmset = await pmsetResult
        let power = await powerResult

        let percentMatch = pmset.range(of: #"(\d+)%"#, options: .regularExpression)
        let percentage = percentMatch.flatMap { Int(pmset[$0].dropLast()) }
        let isCharging = pmset.contains("charging") && !pmset.contains("not charging")
        let isPluggedIn = pmset.contains("AC Power")

        let cycleCount = power.lineValue(after: "Cycle Count:")
        let condition = power.lineValue(after: "Condition:")
        let maxCapacity = power.lineValue(after: "Maximum Capacity:")
            ?? power.lineValue(after: "State of Charge (%):")

        // Parse time remaining from pmset output (e.g., "3:45 remaining")
        let timeMatch = pmset.range(of: #"(\d+:\d+) remaining"#, options: .regularExpression)
        let timeRemaining = timeMatch.map { String(pmset[$0].dropLast(" remaining".count)) }

        return BatteryInfo(
            percentage: percentage,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            cycleCount: cycleCount.flatMap { Int($0) },
            condition: condition,
            maxCapacity: maxCapacity,
            timeRemaining: timeRemaining
        )
    }

    // MARK: - Accessibility (read-only via com.apple.Accessibility)

    func isReduceMotionEnabled() async -> Bool {
        let result = await runShell("defaults read com.apple.Accessibility ReduceMotionEnabled")
        return result.trimmed == "1"
    }

    func isReduceTransparencyEnabled() async -> Bool {
        // DarkenSystemColors corresponds to "Reduce Transparency" in System Settings
        let result = await runShell("defaults read com.apple.Accessibility DarkenSystemColors")
        return result.trimmed == "1"
    }

    func isIncreaseContrastEnabled() async -> Bool {
        let result = await runShell("defaults read com.apple.Accessibility EnhancedBackgroundContrastEnabled")
        return result.trimmed == "1"
    }

    // MARK: - Notifications / Focus (read-only)
    // Modern macOS (Monterey+) uses Focus mode — the old DND key no longer exists.
    // We check via `plutil` the Focus configuration.

    func isFocusEnabled() async -> Bool {
        // Check if any Focus mode assertions are active
        let result = await runShell(
            "plutil -extract dnd_prefs.userPref.enabled raw -o - ~/Library/DoNotDisturb/DB/Assertions/v1/combined.json 2>/dev/null"
        )
        return result.trimmed == "true" || result.trimmed == "1"
    }

    // MARK: - Date & Time (read-only)

    func is24HourClock() async -> Bool {
        let result = await runShell("defaults read com.apple.menuextra.clock Show24Hour")
        return result.trimmed == "1"
    }

    func currentTimezone() async -> String {
        let result = await runShell("readlink /etc/localtime | sed 's|/var/db/timezone/zoneinfo/||'")
        let tz = result.trimmed
        return tz.isEmpty ? TimeZone.current.identifier : tz
    }

    // MARK: - Login Items (read-only)

    func loginItems() async -> [String] {
        let result = await runShell(
            "osascript -e 'tell application \"System Events\" to get the name of every login item'"
        )
        let trimmed = result.trimmed
        guard !trimmed.isEmpty else { return [] }
        return trimmed.components(separatedBy: ", ").filter { !$0.isEmpty }
    }

    // MARK: - Software Update (read-only)

    func pendingUpdateCount() async -> Int? {
        let result = await runShell("defaults read /Library/Preferences/com.apple.SoftwareUpdate LastUpdatesAvailable 2>/dev/null")
        return Int(result.trimmed)
    }

    func lastCheckDate() async -> String? {
        let result = await runShell("defaults read /Library/Preferences/com.apple.SoftwareUpdate LastSuccessfulDate 2>/dev/null")
        let trimmed = result.trimmed
        return trimmed.isEmpty ? nil : String(trimmed.prefix(19))
    }

    // MARK: - Shell Execution

    private func runShell(_ command: String) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-c", command]
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    continuation.resume(returning: "")
                    return
                }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: output)
            }
        }
    }

}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extract the value portion after a label like "Cycle Count: 73"
    func lineValue(after label: String) -> String? {
        guard let range = range(of: label) else { return nil }
        let afterLabel = self[range.upperBound...]
        let line = afterLabel.prefix(while: { $0 != "\n" })
        let value = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
