import Foundation

/// 会议在浮窗中的状态。口径与方案.md「展示/判定」一致：
/// 待审 = 无 started 无回执；审核中 = 有 started 无回执；待决定 = 回执里仍有
/// 未取舍的候选或待补充项；已处理 = 本次记录取舍完成（业务待办可仍在）；
/// 未知 = 回执存在但缺字段/无法解析，禁止补 0。
enum MeetingStatus: String {
    case pending
    case reviewing
    case awaitingDecision
    case processed
    case unknown

    var label: String {
        switch self {
        case .pending: return "待审"
        case .reviewing: return "审核中"
        case .awaitingDecision: return "待你决定"
        case .processed: return "已处理"
        case .unknown: return "状态未知"
        }
    }
}

struct ConflictInfo: Equatable {
    var primarySummary: String
    var secondarySummary: String
    var detail: String
}

struct ReviewResult {
    var itemsPresent = false
    var itemIDs: [String] = []
    var itemCount: Int? = nil
    var acceptedPresent = false
    var acceptedIDs: [String] = []
    var acceptedCount: Int? = nil
    var skippedIDs: [String] = []
    var skippedCount = 0
    var followupCount: Int? = nil
    var completedFlag = false
    var noCandidates = false
    var parseError: String? = nil

    struct Finding: Hashable {
        let kind: String
        let statement: String
    }

    var findings: Set<Finding>? = nil

    /// 用于比较两份判断是否一致；只比较结构，不比较展示文案。
    var signature: String {
        let items = itemIDs.sorted().joined(separator: ",")
        let accepted = acceptedIDs.sorted().joined(separator: ",")
        let skipped = skippedIDs.sorted().joined(separator: ",")
        return "i[\(items)]a[\(accepted)]s[\(skipped)]c[\(completedFlag)]n[\(noCandidates)]"
    }

    static func parse(_ dict: [String: Any]) -> ReviewResult {
        var result = ReviewResult()

        if let rawItems = dict["items"], !(rawItems is NSNull) {
            result.itemsPresent = true
            if let array = rawItems as? [Any] {
                result.itemCount = array.count
                result.itemIDs = array.map(Self.stableID)
                let findings: [Finding] = array.compactMap { entry in
                    guard let item = entry as? [String: Any],
                          let kind = item["kind"] as? String,
                          let statement = item["statement"] as? String else { return nil }
                    return Finding(kind: kind, statement: statement)
                }
                if findings.count == array.count { result.findings = Set(findings) }
            } else if let map = rawItems as? [String: Any] {
                result.itemCount = map.count
                result.itemIDs = map.keys.sorted()
            } else {
                result.itemCount = 1
                result.itemIDs = [Self.stableID(rawItems)]
            }
        }

        if let rawAccepted = dict["accepted"], !(rawAccepted is NSNull) {
            result.acceptedPresent = true
            if let array = rawAccepted as? [Any] {
                result.acceptedCount = array.count
                result.acceptedIDs = array.map(Self.stableID)
                if result.findings != nil, let items = dict["items"] as? [[String: Any]] {
                    let selected = array.compactMap { $0 as? Int }
                    if selected.count != array.count || Set(selected).count != selected.count ||
                        selected.contains(where: { $0 < 1 || $0 > items.count || items[$0 - 1]["kind"] as? String == "待确认" }) {
                        result.parseError = "确认回执的采纳编号无效"
                        result.acceptedCount = nil
                    }
                }
            } else if let map = rawAccepted as? [String: Any] {
                result.acceptedCount = map.count
                result.acceptedIDs = map.keys.sorted()
            } else if let number = rawAccepted as? NSNumber {
                // 兼容旧回执把 accepted 写成数量的情况。
                result.acceptedCount = number.intValue
            } else {
                result.acceptedCount = 1
                result.acceptedIDs = [Self.stableID(rawAccepted)]
            }
        }

        if let rawSkipped = dict["skipped"] ?? dict["rejected"], !(rawSkipped is NSNull) {
            if let array = rawSkipped as? [Any] {
                result.skippedCount = array.count
                result.skippedIDs = array.map(Self.stableID)
            } else if let map = rawSkipped as? [String: Any] {
                result.skippedCount = map.count
                result.skippedIDs = map.keys.sorted()
            }
        }

        if let rawFollowups = dict["followups"], !(rawFollowups is NSNull) {
            if let array = rawFollowups as? [Any] {
                result.followupCount = array.count
            } else if let map = rawFollowups as? [String: Any] {
                result.followupCount = map.count
            }
        }

        if let status = dict["status"] as? String {
            let completed: Set<String> = ["done", "completed", "confirmed", "processed", "closed", "finished"]
            result.completedFlag = completed.contains(status.lowercased())
        }
        if let state = dict["state"] as? String {
            let completed: Set<String> = ["done", "completed", "confirmed", "processed", "closed", "finished"]
            result.completedFlag = result.completedFlag || completed.contains(state.lowercased())
        }
        if let completed = dict["completed"] as? Bool, completed {
            result.completedFlag = true
        }
        if let noCandidates = dict["no_candidates"] as? Bool, noCandidates {
            result.noCandidates = true
        }

        return result
    }

    /// 从 Array 元素提取稳定 ID；对象优先 id/key/name，避免把整段内容带进 UI。
    static func stableID(_ value: Any) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        if let dict = value as? [String: Any] {
            for key in ["id", "key", "item_id", "name"] {
                if let raw = dict[key], !(raw is NSNull) { return "\(raw)" }
            }
            return "item:" + dict.keys.sorted().joined(separator: ",")
        }
        return "\(value)"
    }

    static func derivedStatus(result: ReviewResult, hasConflict: Bool) -> MeetingStatus {
        if hasConflict { return .awaitingDecision }
        if result.parseError != nil { return .unknown }
        if result.completedFlag || result.noCandidates { return .processed }
        if result.itemsPresent {
            guard let items = result.itemCount else { return .unknown }
            if items == 0 { return .processed }
            // The review CLI writes this field only on explicit confirmation.
            // Unselected candidates are declined even when accepted is empty.
            if result.acceptedPresent { return .processed }
            // 有明确候选但缺 accepted：保留数未知，仍需用户取舍。
            return .awaitingDecision
        }
        if (result.followupCount ?? 0) > 0 { return .awaitingDecision }
        // 回执存在但既无 items、accepted，也无待补充项：不允许猜成 0 或待审。
        return .unknown
    }
}

struct ParsedReceipt {
    var result = ReviewResult()
    var conflict: ConflictInfo? = nil
    var invalidReason: String? = nil

    static func parse(data: Data) -> ParsedReceipt {
        var parsed = ParsedReceipt()
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            parsed.result.parseError = "回执 JSON 无法解析"
            parsed.invalidReason = "回执无法解析（旧版或损坏）"
            return parsed
        }
        guard let root = object as? [String: Any] else {
            parsed.result.parseError = "回执不是 JSON 对象"
            parsed.invalidReason = "回执格式不是对象"
            return parsed
        }

        var primary = root
        if root["items"] == nil, let review = root["review"] as? [String: Any] {
            primary = review
        }
        parsed.result = ReviewResult.parse(primary)

        if let second = primary["second"] as? [String: Any] {
            let a = parsed.result
            let b = ReviewResult.parse(second)
            let resolution = primary["resolution"] as? Int
            if resolution == 2 {
                var active = second
                // The selection and its notes are recorded on the primary receipt.
                active["accepted"] = primary["accepted"]
                active["followups"] = primary["followups"]
                parsed.result = ReviewResult.parse(active)
            } else if resolution != 1 {
                let differs: Bool
                if let aFindings = a.findings, let bFindings = b.findings {
                    differs = aFindings != bFindings
                } else {
                    differs = a.signature != b.signature
                }
                if differs {
                    parsed.conflict = ConflictInfo(
                        primarySummary: "主审：候选 \(a.itemCount.map(String.init) ?? "未记录")",
                        secondarySummary: "复核：候选 \(b.itemCount.map(String.init) ?? "未记录")",
                        detail: "两份判断结论不同，请回原审核窗口确认。"
                    )
                }
            }
        } else if let first = root["review"] as? [String: Any],
           let second = (root["recheck"] ?? root["second_review"]) as? [String: Any] {
            let a = ReviewResult.parse(first)
            let b = ReviewResult.parse(second)
            if a.signature != b.signature {
                let aCount = a.acceptedCount.map(String.init) ?? "未记录"
                let bCount = b.acceptedCount.map(String.init) ?? "未记录"
                let idsDiffer = a.acceptedIDs.sorted() != b.acceptedIDs.sorted()
                parsed.conflict = ConflictInfo(
                    primarySummary: "主审：候选 \(a.itemCount.map(String.init) ?? "未记录") · 保留 \(aCount)",
                    secondarySummary: "复核：候选 \(b.itemCount.map(String.init) ?? "未记录") · 保留 \(bCount)",
                    detail: idsDiffer ? "两份判断保留的条目不同，需在原文确认。" : "两份判断结论不同，需在原文确认。"
                )
            }
        }
        return parsed
    }
}

struct Meeting: Equatable {
    var sha256: String
    var displayName: String
    var primaryPath: String
    var latestModified: Date
    var duplicateCount: Int
    var status: MeetingStatus
    var candidateCount: Int?
    var retainedCount: Int?
    var followupCount: Int?
    var startedAt: Date?
    var waitingLong: Bool
    var conflict: ConflictInfo?
    var note: String?
    var summary: String
    var htmlURL: URL?

    var nextStep: String {
        switch status {
        case .pending: return "尚未发起审核"
        case .reviewing: return waitingLong ? "审核中，等待较久，可回原窗口查看" : "AI 审核中，等待回执"
        case .awaitingDecision:
            if conflict != nil { return "两份判断不一致，请回原审核窗口确认" }
            if (followupCount ?? 0) > 0 && candidateCount == nil { return "有待补充项，回原审核窗口处理" }
            return "在原审核窗口保留、跳过或暂缓"
        case .processed:
            if let followups = followupCount, followups > 0 { return "本次取舍已完成；会后更新 \(followups) 项" }
            return "本次记录取舍已完成"
        case .unknown: return "回执缺字段，无法判断阶段"
        }
    }
}

struct VaultSnapshot {
    var meetings: [Meeting]
    var inboxFileCount: Int
    var readAt: Date
}

struct PanelCounts: Equatable {
    var pending = 0
    var reviewing = 0
    var awaiting = 0
    var processed = 0
    var unknown = 0
    var duplicateExtras = 0
    var conflicts = 0
    var waitingLong = 0

    var totalMeetings: Int { pending + reviewing + awaiting + processed + unknown }

    static func make(from meetings: [Meeting]) -> PanelCounts {
        var counts = PanelCounts()
        for meeting in meetings {
            switch meeting.status {
            case .pending: counts.pending += 1
            case .reviewing: counts.reviewing += 1
            case .awaitingDecision: counts.awaiting += 1
            case .processed: counts.processed += 1
            case .unknown: counts.unknown += 1
            }
            counts.duplicateExtras += meeting.duplicateCount
            if meeting.conflict != nil { counts.conflicts += 1 }
            if meeting.waitingLong { counts.waitingLong += 1 }
        }
        return counts
    }
}

enum VaultReadError: LocalizedError {
    case notFound(String)
    case notReadable(String, String)
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let path): return "找不到或不是目录：\(path)"
        case .notReadable(let path, let reason): return "无法读取：\(path)（\(reason)）"
        case .invalid(let reason): return reason
        }
    }

    var isPermissionFailure: Bool {
        if case .notReadable = self { return true }
        return false
    }
}
