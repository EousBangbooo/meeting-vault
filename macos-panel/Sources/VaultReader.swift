import Foundation
import CryptoKit

/// 只读访问：<vault>/inbox/*.txt 与
/// <vault>/.meeting-review/<sha256>.{started,json}。
/// 不扫描其他目录，不写入会议库。
final class VaultReader {
    private struct CachedFile {
        var modification: Date
        var size: Int
        var sha: String
        var summary: String
    }

    private struct InboxFile {
        var url: URL
        var name: String
        var modification: Date
        var sha: String
        var summary: String
    }

    private var digestCache: [String: CachedFile] = [:]

    private let fileManager = FileManager.default
    private let startedThreshold: TimeInterval = 15 * 60

    func scan(vaultURL: URL) throws -> VaultSnapshot {
        let vault = vaultURL.standardizedFileURL
        let inboxURL = vault.appendingPathComponent("inbox", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: inboxURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw VaultReadError.notFound(inboxURL.path)
        }

        let listing: [URL]
        do {
            listing = try fileManager.contentsOfDirectory(
                at: inboxURL,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw VaultReadError.notReadable(inboxURL.path, error.localizedDescription)
        }

        let reviewURL = vault.appendingPathComponent(".meeting-review", isDirectory: true)
        var reviewIsDirectory: ObjCBool = false
        let hasReviewDirectory = fileManager.fileExists(atPath: reviewURL.path, isDirectory: &reviewIsDirectory)
            && reviewIsDirectory.boolValue
        if hasReviewDirectory {
            // 显式探测可读性：目录存在但不可读时不能当成“没有回执”。
            do {
                _ = try fileManager.contentsOfDirectory(atPath: reviewURL.path)
            } catch {
                throw VaultReadError.notReadable(reviewURL.path, error.localizedDescription)
            }
        }

        var files: [InboxFile] = []
        for candidate in listing {
            guard candidate.pathExtension.lowercased() == "txt" else { continue }
            let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }

            let modification = (try? candidate.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? Date.distantPast
            let size = (try? candidate.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
            let cacheKey = candidate.standardizedFileURL.path

            let digest: CachedFile
            if let cached = digestCache[cacheKey],
               cached.modification == modification,
               cached.size == size {
                digest = cached
            } else {
                let data: Data
                do {
                    data = try Data(contentsOf: candidate, options: [.mappedIfSafe])
                } catch {
                    throw VaultReadError.notReadable(candidate.path, error.localizedDescription)
                }
                let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                let summary = Self.summary(from: data)
                digest = CachedFile(modification: modification, size: data.count, sha: sha, summary: summary)
                digestCache[cacheKey] = digest
            }

            files.append(InboxFile(
                url: candidate,
                name: candidate.lastPathComponent,
                modification: modification,
                sha: digest.sha,
                summary: digest.summary
            ))
        }

        // 同一内容 SHA 合并为一场会议，重复复制只记“重复”，不重复计数。
        var grouped: [String: [InboxFile]] = [:]
        for file in files { grouped[file.sha, default: []].append(file) }

        var meetings: [Meeting] = []
        for (sha, group) in grouped {
            let sorted = group.sorted { $0.modification > $1.modification }
            guard let primary = sorted.first else { continue }

            var receipt: ParsedReceipt? = nil
            var startedAt: Date? = nil
            var receiptModified: Date? = nil

            if hasReviewDirectory {
                let startedURL = reviewURL.appendingPathComponent("\(sha).started")
                if fileManager.fileExists(atPath: startedURL.path) {
                    startedAt = (try? startedURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                        ?? Date.distantPast
                }
                let jsonURL = reviewURL.appendingPathComponent("\(sha).json")
                if fileManager.fileExists(atPath: jsonURL.path) {
                    let data: Data
                    do {
                        data = try Data(contentsOf: jsonURL, options: [.mappedIfSafe])
                    } catch {
                        throw VaultReadError.notReadable(jsonURL.path, error.localizedDescription)
                    }
                    receipt = ParsedReceipt.parse(data: data)
                    receiptModified = (try? jsonURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                        ?? Date.distantPast
                }
            }

            let status: MeetingStatus
            if let receipt {
                status = ReviewResult.derivedStatus(result: receipt.result, hasConflict: receipt.conflict != nil)
            } else if startedAt != nil {
                status = .reviewing
            } else {
                status = .pending
            }

            let waitingLong: Bool = {
                guard status == .reviewing, let startedAt else { return false }
                return Date().timeIntervalSince(startedAt) > startedThreshold
            }()

            var note: String? = nil
            if let invalid = receipt?.invalidReason {
                note = invalid
            } else if let result = receipt?.result {
                if let error = result.parseError {
                    note = error
                } else if result.itemsPresent == false && result.acceptedPresent == false && (result.followupCount ?? 0) > 0 {
                    note = "旧回执缺 items，候选数未记录"
                } else if result.itemsPresent == false && result.acceptedPresent == false {
                    note = "回执缺 items/accepted，显示未记录"
                } else if result.itemsPresent && !result.acceptedPresent {
                    note = "回执缺 accepted，保留数未记录"
                }
            }

            let latest = [primary.modification, receiptModified, startedAt]
                .compactMap { $0 }
                .max() ?? primary.modification

            let html = Self.htmlURL(vault: vault, inboxName: primary.name, sha: sha)

            meetings.append(Meeting(
                sha256: sha,
                displayName: (primary.name as NSString).deletingPathExtension,
                primaryPath: primary.url.path,
                latestModified: latest,
                duplicateCount: max(0, group.count - 1),
                status: status,
                candidateCount: receipt?.result.itemCount,
                retainedCount: receipt?.result.acceptedCount,
                followupCount: receipt?.result.followupCount,
                startedAt: startedAt,
                waitingLong: waitingLong,
                conflict: receipt?.conflict,
                note: note,
                summary: primary.summary.isEmpty ? "（转写无文本摘要）" : primary.summary,
                htmlURL: html
            ))
        }

        meetings.sort { $0.latestModified > $1.latestModified }
        return VaultSnapshot(meetings: meetings, inboxFileCount: files.count, readAt: Date())
    }

    private static func summary(from data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8) else { return "" }
        for rawLine in text.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            line = line.replacingOccurrences(of: "^#{1,6}\\s*", with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            if line.isEmpty { continue }
            if line.count > 90 { line = String(line.prefix(90)) + "…" }
            return line
        }
        return ""
    }

    private static func htmlURL(vault: URL, inboxName: String, sha: String) -> URL? {
        let base = (inboxName as NSString).deletingPathExtension
        let candidates = [
            vault.appendingPathComponent("\(base).html"),
            vault.appendingPathComponent("inbox/\(base).html"),
            vault.appendingPathComponent(".meeting-review/\(sha).html"),
            vault.appendingPathComponent("\(base)/index.html"),
            vault.appendingPathComponent("会议处理.html")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
