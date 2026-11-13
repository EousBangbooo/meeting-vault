import Foundation

/// 浮窗与菜单栏共用的只读展示模型。
/// 读取失败时保留最后一次成功快照和计数，只标记过期；首次失败则计数为“—”。
final class PanelModel {
    private(set) var snapshot: VaultSnapshot?
    private(set) var lastSuccess: Date?
    private(set) var failureMessage: String?
    private(set) var hasVault = false

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var meetings: [Meeting] { snapshot?.meetings ?? [] }
    var counts: PanelCounts? { snapshot.map { PanelCounts.make(from: $0.meetings) } }
    var isStale: Bool { failureMessage != nil }

    var nextMeeting: Meeting? {
        let active = meetings.filter { meeting in
            meeting.status == .awaitingDecision || meeting.status == .reviewing || meeting.status == .pending
        }
        let ordered = active.sorted { lhs, rhs in
            func rank(_ status: MeetingStatus) -> Int {
                switch status {
                case .awaitingDecision: return 0
                case .reviewing: return 1
                case .pending: return 2
                default: return 3
                }
            }
            if rank(lhs.status) != rank(rhs.status) { return rank(lhs.status) < rank(rhs.status) }
            return lhs.latestModified > rhs.latestModified
        }
        return ordered.first ?? meetings.first
    }

    func beginVault() {
        hasVault = true
        snapshot = nil
        lastSuccess = nil
        failureMessage = nil
    }

    func clearVault() {
        hasVault = false
        snapshot = nil
        lastSuccess = nil
        failureMessage = nil
    }

    func apply(_ snapshot: VaultSnapshot) {
        hasVault = true
        self.snapshot = snapshot
        lastSuccess = snapshot.readAt
        failureMessage = nil
    }

    func applyFailure(_ message: String) {
        hasVault = true
        failureMessage = message
    }

    var countsLine: String {
        guard let counts else { return "待审 — · 审核中 — · 待你决定 —" }
        return "待审 \(counts.pending) · 审核中 \(counts.reviewing) · 待你决定 \(counts.awaiting)"
    }

    var secondaryLine: String {
        guard let counts else {
            return hasVault ? "尚无成功读取，计数未显示" : "未选择会议库"
        }
        var parts = ["已处理 \(counts.processed)", "未知 \(counts.unknown)"]
        if counts.duplicateExtras > 0 { parts.append("重复 \(counts.duplicateExtras)") }
        if counts.conflicts > 0 { parts.append("冲突 \(counts.conflicts)") }
        if counts.waitingLong > 0 { parts.append("等待较久 \(counts.waitingLong)") }
        return parts.joined(separator: " · ")
    }

    var statusLine: String {
        let time = lastSuccess.map { Self.timeFormatter.string(from: $0) }
        if let failureMessage {
            let suffix = time.map { "上次成功 \($0)" } ?? "尚无成功读取"
            return "无法读取会议库：\(failureMessage) · \(suffix) · 数字已过期"
        }
        if !hasVault { return "未选择会议库，只读 inbox 与 .meeting-review" }
        guard let time else { return "正在读取会议库…" }
        return "更新于 \(time) · 目录变化 0.3 秒合并、3 秒内补读"
    }

    var menuTitle: String {
        if !hasVault { return "MV —" }
        guard let counts else { return isStale ? "MV ⚠︎ —" : "MV …" }
        var title = "待审 \(counts.pending) · 待定 \(counts.awaiting)"
        if counts.reviewing > 0 { title += " · 审核中 \(counts.reviewing)" }
        return isStale ? "⚠︎ " + title : title
    }

    var detailCountsLine: String {
        guard let meeting = nextMeeting else { return "" }
        let candidates = meeting.candidateCount.map(String.init) ?? "未记录"
        let retained = meeting.retainedCount.map(String.init) ?? "未记录"
        var text = "候选 \(candidates) · 已保留 \(retained) · AI 略过：未记录"
        if let followups = meeting.followupCount, followups > 0 {
            text += " · 会后更新 \(followups)"
        }
        if meeting.duplicateCount > 0 {
            text += " · 重复 \(meeting.duplicateCount)"
        }
        return text
    }
}
