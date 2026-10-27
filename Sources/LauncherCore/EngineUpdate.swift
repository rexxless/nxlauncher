import Foundation

/// Newer nxnative from GitHub. nxnative has no releases, so a version is a commit on its main branch: the check asks for
/// the branch's head and how far it is ahead of the installed commit, and the download is that commit's tarball.
/// This, LauncherUpdate and the links to what changed are the launcher's only network use.
public enum EngineUpdate {
    public static let repo = "seedds/nxnative"
    public static let branch = "main"

    public struct Release: Equatable, Sendable {
        public let version: Engine.Version
        /// The commit message's first line.
        public let message: String
        public init(version: Engine.Version, message: String) { self.version = version; self.message = message }
    }

    public struct Status: Equatable, Sendable {
        public let latest: Release
        /// Commits the branch is ahead of the installed one, when GitHub could compare them.
        public let aheadBy: Int?
        public let isNewer: Bool
        /// The newest commits since the installed one, newest first (at most `maxChanges`).
        public let changes: [Release]
    }

    public static let maxChanges = 20

    public struct UpdateError: Error, LocalizedError, Equatable {
        public let message: String
        /// GitHub's HTTP status, when it answered with an error.
        var status: Int? = nil
        public var errorDescription: String? { message }
    }

    public static func compareURL(from old: String, to new: String) -> URL {
        URL(string: "https://github.com/\(repo)/compare/\(old)...\(new)")!
    }

    /// Asks GitHub for the head of main and compares it with the installed commit.
    public static func check(installed: Engine.Version, session: URLSession = .shared) async throws -> Status {
        let latest = try parseCommit(try await get("https://api.github.com/repos/\(repo)/commits/\(branch)", session))
        if latest.version.sha == installed.sha { return Status(latest: latest, aheadBy: 0, isNewer: false, changes: []) }
        let compare = try? parseCompare(try await get("https://api.github.com/repos/\(repo)/compare/\(installed.sha)...\(latest.version.sha)", session))
        return status(latest: latest, installed: installed, compare: compare)
    }

    static func status(latest: Release, installed: Engine.Version, compare: Compare?) -> Status {
        if let compare {
            return Status(latest: latest, aheadBy: compare.aheadBy,
                          isNewer: compare.status == "ahead" || compare.status == "diverged" && compare.aheadBy > 0, changes: compare.changes)
        }
        // GitHub could not compare them (a commit it does not know): the dates decide.
        guard let new = latest.version.date, let old = installed.date else { return Status(latest: latest, aheadBy: nil, isNewer: true, changes: [latest]) }
        return Status(latest: latest, aheadBy: nil, isNewer: new > old, changes: [latest])
    }

    /// Downloads the commit's tarball into `folder` and returns its path. Unpack it with `stripComponents: 1`.
    public static func download(_ release: Release, to folder: URL, session: URLSession = .shared) async throws -> URL {
        let url = URL(string: "https://codeload.github.com/\(repo)/tar.gz/\(release.version.sha)")!
        let (tmp, response) = try await session.download(from: url)
        try checkResponse(response)
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = folder.appending(path: "nxnative-\(release.version.sha).tar.gz")
        try? fm.removeItem(at: dest)
        try fm.moveItem(at: tmp, to: dest)
        return dest
    }

    static func get(_ url: String, _ session: URLSession) async throws -> Data {
        var req = URLRequest(url: URL(string: url)!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 30
        let (data, response) = try await session.data(for: req)
        try checkResponse(response)
        return data
    }

    static func checkResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300: return
        case 403, 429: throw UpdateError(message: "GitHub's rate limit was reached, try again later", status: http.statusCode)
        default: throw UpdateError(message: "GitHub answered \(http.statusCode)", status: http.statusCode)
        }
    }

    private struct CommitJSON: Decodable {
        struct Commit: Decodable {
            struct Person: Decodable { let date: String }
            let committer: Person
            let message: String
        }
        let sha: String
        let commit: Commit
    }

    static func parseCommit(_ data: Data) throws -> Release {
        guard let c = try? JSONDecoder().decode(CommitJSON.self, from: data) else { throw UpdateError(message: "GitHub's answer could not be read") }
        return release(c)
    }

    private static func release(_ c: CommitJSON) -> Release {
        let message = c.commit.message.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return Release(version: Engine.Version(sha: c.sha, date: try? Date(c.commit.committer.date, strategy: .iso8601)), message: message)
    }

    struct Compare: Equatable {
        let status: String
        let aheadBy: Int
        let changes: [Release]
    }

    private struct CompareJSON: Decodable {
        let status: String
        let ahead_by: Int
        let commits: [CommitJSON]?
    }

    /// GitHub lists a comparison's commits oldest first.
    static func parseCompare(_ data: Data) throws -> Compare {
        guard let c = try? JSONDecoder().decode(CompareJSON.self, from: data) else { throw UpdateError(message: "GitHub's answer could not be read") }
        return Compare(status: c.status, aheadBy: c.ahead_by, changes: (c.commits ?? []).reversed().prefix(maxChanges).map(release))
    }
}
