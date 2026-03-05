import AppKit
import Foundation

struct GitHubRelease: Decodable, Sendable {
    let tagName: String
    let name: String
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case assets
    }

    var versionNumber: String {
        tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }
}

struct GitHubAsset: Decodable, Sendable {
    let name: String
    let browserDownloadURL: String
    let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
    }
}

enum UpdateError: LocalizedError {
    case noZipAsset
    case extractFailed
    case appNotFoundInZip

    var errorDescription: String? {
        switch self {
        case .noZipAsset: return "No .zip asset found in GitHub release"
        case .extractFailed: return "Failed to extract downloaded archive"
        case .appNotFoundInZip: return "MacBar.app not found in archive"
        }
    }
}

final class UpdateService: Sendable {
    private static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/mikewang817/MacBar/releases/latest"
    )!

    func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    func isNewerVersion(_ candidate: String, than current: String) -> Bool {
        let parse: (String) -> [Int] = { v in
            v.trimmingCharacters(in: .init(charactersIn: "vV"))
                .split(separator: ".")
                .compactMap { Int($0) }
        }
        let v1 = parse(candidate)
        let v2 = parse(current)
        for i in 0..<max(v1.count, v2.count) {
            let a = i < v1.count ? v1[i] : 0
            let b = i < v2.count ? v2[i] : 0
            if a > b { return true }
            if a < b { return false }
        }
        return false
    }

    func downloadAndInstall(release: GitHubRelease) async throws {
        guard
            let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }),
            let downloadURL = URL(string: asset.browserDownloadURL)
        else { throw UpdateError.noZipAsset }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacBarUpdate_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Download zip
        let (tempFileURL, _) = try await URLSession.shared.download(from: downloadURL)
        let zipURL = tempDir.appendingPathComponent("MacBar.zip")
        try? FileManager.default.removeItem(at: zipURL)
        try FileManager.default.moveItem(at: tempFileURL, to: zipURL)

        // Extract + write install script on background thread
        let installTarget = "/Applications/MacBar.app"
        let scriptURL = tempDir.appendingPathComponent("install.sh")

        try await Task.detached(priority: .utility) {
            let extractDir = tempDir.appendingPathComponent("extracted")
            try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-x", "-k", zipURL.path, extractDir.path]
            try ditto.run()
            ditto.waitUntilExit()
            guard ditto.terminationStatus == 0 else { throw UpdateError.extractFailed }

            let newApp = extractDir.appendingPathComponent("MacBar.app")
            guard FileManager.default.fileExists(atPath: newApp.path) else {
                throw UpdateError.appNotFoundInZip
            }

            // Remove the old bundle first; copying onto an existing directory would
            // place the new .app *inside* the old one instead of replacing it.
            let script = """
            #!/bin/bash
            sleep 2
            /bin/rm -rf "\(installTarget)"
            /bin/cp -Rf "\(newApp.path)" "/Applications/"
            /usr/bin/open "\(installTarget)"
            /bin/rm -rf "\(tempDir.path)"
            """
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o755))],
                ofItemAtPath: scriptURL.path
            )
        }.value

        // Launch install script, then quit
        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/bin/bash")
        launcher.arguments = [scriptURL.path]
        try launcher.run()

        await MainActor.run {
            NSApplication.shared.terminate(nil)
        }
    }
}
