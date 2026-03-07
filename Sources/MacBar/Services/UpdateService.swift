import AppKit
import Foundation

struct GitHubRelease: Decodable, Sendable {
    let tagName: String
    let name: String
    let assets: [GitHubAsset]
    let htmlURL: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case assets
        case htmlURL = "html_url"
    }

    init(tagName: String, name: String, assets: [GitHubAsset], htmlURL: String? = nil) {
        self.tagName = tagName
        self.name = name
        self.assets = assets
        self.htmlURL = htmlURL
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

    init(name: String, browserDownloadURL: String, size: Int = 0) {
        self.name = name
        self.browserDownloadURL = browserDownloadURL
        self.size = size
    }
}

private struct WebsiteUpdateManifest: Decodable, Sendable {
    let version: String
    let name: String?
    let downloadURL: String
    let releaseNotesURL: String?

    enum CodingKeys: String, CodingKey {
        case version
        case name
        case downloadURL = "download_url"
        case releaseNotesURL = "release_notes_url"
    }
}

enum UpdateError: LocalizedError {
    case noZipAsset
    case extractFailed
    case appNotFoundInZip
    case invalidResponse
    case invalidWebsiteRelease

    var errorDescription: String? {
        switch self {
        case .noZipAsset: return "No .zip asset found for update release"
        case .extractFailed: return "Failed to extract downloaded archive"
        case .appNotFoundInZip: return "MacBar.app not found in archive"
        case .invalidResponse: return "Unexpected update server response"
        case .invalidWebsiteRelease: return "Failed to parse website update metadata"
        }
    }
}

final class UpdateService: Sendable {
    private static let githubLatestReleaseURL = URL(
        string: "https://api.github.com/repos/mikewang817/MacBar/releases/latest"
    )!
    private static let githubLatestReleasePageURL = URL(
        string: "https://github.com/mikewang817/MacBar/releases/latest"
    )!
    private static let websiteBaseURL = URL(string: "https://macbar.app")!
    private static let websiteUpdateManifestURL = URL(string: "https://macbar.app/update.json")!
    private static let websiteLatestDownloadURL = URL(string: "https://macbar.app/download/latest")!

    func fetchLatestRelease() async throws -> GitHubRelease {
        do {
            return try await fetchLatestReleaseFromGitHub()
        } catch {
            return try await fetchLatestReleaseFromWebsite()
        }
    }

    func manualDownloadURL(for release: GitHubRelease) -> URL {
        if let websiteAsset = release.assets.first(where: {
            URL(string: $0.browserDownloadURL)?.host == Self.websiteBaseURL.host
        }), let url = URL(string: websiteAsset.browserDownloadURL) {
            return url
        }

        return Self.websiteLatestDownloadURL
    }

    private func fetchLatestReleaseFromGitHub() async throws -> GitHubRelease {
        var request = URLRequest(url: Self.githubLatestReleaseURL)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let data = try await fetchData(for: request)
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func fetchLatestReleaseFromWebsite() async throws -> GitHubRelease {
        do {
            return try await fetchLatestReleaseFromWebsiteManifest()
        } catch {
            return try await fetchLatestReleaseFromWebsiteDownload()
        }
    }

    private func fetchLatestReleaseFromWebsiteManifest() async throws -> GitHubRelease {
        var request = URLRequest(url: Self.websiteUpdateManifestURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let data = try await fetchData(for: request)
        let manifest = try JSONDecoder().decode(WebsiteUpdateManifest.self, from: data)

        let downloadURL = try resolvedWebsiteURL(from: manifest.downloadURL)
        let releaseNotesURL = try manifest.releaseNotesURL.map(resolvedWebsiteURL(from:))?.absoluteString
        let assetName = inferredAssetName(from: downloadURL, version: manifest.version)

        return GitHubRelease(
            tagName: "v\(manifest.version)",
            name: manifest.name ?? "MacBar v\(manifest.version)",
            assets: [
                GitHubAsset(
                    name: assetName,
                    browserDownloadURL: downloadURL.absoluteString
                )
            ],
            htmlURL: releaseNotesURL
        )
    }

    private func fetchLatestReleaseFromWebsiteDownload() async throws -> GitHubRelease {
        var request = URLRequest(url: Self.websiteLatestDownloadURL)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (_, response) = try await URLSession.shared.data(for: request)
        try validate(response)

        guard
            let finalURL = response.url,
            let version = extractVersion(fromAssetName: finalURL.lastPathComponent)
        else {
            throw UpdateError.invalidWebsiteRelease
        }

        return GitHubRelease(
            tagName: "v\(version)",
            name: "MacBar v\(version)",
            assets: [
                GitHubAsset(
                    name: finalURL.lastPathComponent,
                    browserDownloadURL: finalURL.absoluteString
                )
            ],
            htmlURL: Self.websiteBaseURL.absoluteString
        )
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
        var candidateDownloadURLs = zipAssetURLs(in: release)
        let websiteFallbackURLs = await websiteFallbackDownloadURLs(for: release)
        for fallbackURL in websiteFallbackURLs where !candidateDownloadURLs.contains(fallbackURL) {
            candidateDownloadURLs.append(fallbackURL)
        }

        guard !candidateDownloadURLs.isEmpty else { throw UpdateError.noZipAsset }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacBarUpdate_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let zipURL = tempDir.appendingPathComponent("MacBar.zip")
        try await downloadArchive(from: candidateDownloadURLs, to: zipURL)

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

    private func fetchData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return data
    }

    private func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw UpdateError.invalidResponse
        }
    }

    private func zipAssetURLs(in release: GitHubRelease) -> [URL] {
        release.assets.compactMap { asset in
            guard asset.name.hasSuffix(".zip") else { return nil }
            return URL(string: asset.browserDownloadURL)
        }
    }

    private func websiteFallbackDownloadURLs(for release: GitHubRelease) async -> [URL] {
        guard let websiteRelease = try? await fetchLatestReleaseFromWebsite(),
              websiteRelease.versionNumber == release.versionNumber else {
            return []
        }

        return zipAssetURLs(in: websiteRelease)
    }

    private func downloadArchive(from urls: [URL], to destinationURL: URL) async throws {
        var lastError: Error?

        for url in urls {
            do {
                try await downloadArchive(from: url, to: destinationURL)
                return
            } catch {
                lastError = error
            }
        }

        throw lastError ?? UpdateError.noZipAsset
    }

    private func downloadArchive(from url: URL, to destinationURL: URL) async throws {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (tempFileURL, response) = try await URLSession.shared.download(for: request)
        try validate(response)

        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.moveItem(at: tempFileURL, to: destinationURL)
    }

    private func resolvedWebsiteURL(from value: String) throws -> URL {
        if let absoluteURL = URL(string: value), absoluteURL.scheme != nil {
            return absoluteURL
        }

        if let relativeURL = URL(string: value, relativeTo: Self.websiteBaseURL)?.absoluteURL {
            return relativeURL
        }

        throw UpdateError.invalidWebsiteRelease
    }

    private func inferredAssetName(from url: URL, version: String) -> String {
        if !url.lastPathComponent.isEmpty {
            return url.lastPathComponent
        }

        return "MacBar-v\(version).zip"
    }

    private func extractVersion(fromAssetName assetName: String) -> String? {
        guard assetName.hasSuffix(".zip") else {
            return nil
        }

        let withoutExtension = assetName.replacingOccurrences(of: ".zip", with: "")
        if withoutExtension.hasPrefix("MacBar-v") {
            return String(withoutExtension.dropFirst("MacBar-v".count))
        }

        if withoutExtension.hasPrefix("MacBar-") {
            return String(withoutExtension.dropFirst("MacBar-".count))
        }

        return nil
    }
}
