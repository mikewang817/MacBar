import Foundation

struct SecurityScopedResolvedFile {
    let originalURL: URL
    let resolvedURL: URL
    let bookmarkData: Data?
}

extension SecurityScopedResolvedFile: Equatable {
    static func == (lhs: SecurityScopedResolvedFile, rhs: SecurityScopedResolvedFile) -> Bool {
        lhs.originalURL == rhs.originalURL && lhs.resolvedURL == rhs.resolvedURL
    }
}

final class SecurityScopedFileAccessService {
    func makeReadOnlyBookmark(for fileURL: URL) -> Data? {
        guard fileURL.isFileURL else {
            return nil
        }

        do {
            return try fileURL.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            return nil
        }
    }

    func resolveFile(_ fileURL: URL, bookmarkData: Data?) -> SecurityScopedResolvedFile {
        guard let bookmarkData else {
            let standardizedURL = fileURL.standardizedFileURL
            return SecurityScopedResolvedFile(
                originalURL: fileURL,
                resolvedURL: standardizedURL,
                bookmarkData: nil
            )
        }

        var bookmarkIsStale = false
        if let resolvedURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &bookmarkIsStale
        ) {
            return SecurityScopedResolvedFile(
                originalURL: fileURL,
                resolvedURL: resolvedURL.standardizedFileURL,
                bookmarkData: bookmarkData
            )
        }

        return SecurityScopedResolvedFile(
            originalURL: fileURL,
            resolvedURL: fileURL.standardizedFileURL,
            bookmarkData: nil
        )
    }

    func withAccess<T>(
        to resolvedFile: SecurityScopedResolvedFile,
        _ body: (URL) throws -> T
    ) rethrows -> T {
        let startedAccess = resolvedFile.bookmarkData != nil
            && resolvedFile.resolvedURL.startAccessingSecurityScopedResource()
        defer {
            if startedAccess {
                resolvedFile.resolvedURL.stopAccessingSecurityScopedResource()
            }
        }

        return try body(resolvedFile.resolvedURL)
    }
}
