import Foundation

func runSelfTest(vaultPath: String?) -> Int32 {
    var checks = 0
    var failures = 0

    func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        checks += 1
        if condition() {
            print("PASS  \(label)")
        } else {
            failures += 1
            print("FAIL  \(label)")
        }
    }

    let path = vaultPath ?? "fixtures/vault"
    let vaultURL = URL(fileURLWithPath: path).standardizedFileURL
    print("== Meeting Vault Panel 自测 ==")
    print("fixture: \(vaultURL.path)")

    let reader = VaultReader()
    let snapshot: VaultSnapshot
    do {
        snapshot = try reader.scan(vaultURL: vaultURL)
    } catch {
        print("FAIL  无法读取 fixture：\(error.localizedDescription)")
        print("RESULT: FAIL 0/1")
        return 1
    }

    let counts = PanelCounts.make(from: snapshot.meetings)
    print("meetings=\(counts.totalMeetings) inboxFiles=\(snapshot.inboxFileCount) " +
          "pending=\(counts.pending) reviewing=\(counts.reviewing) awaiting=\(counts.awaiting) " +
          "processed=\(counts.processed) unknown=\(counts.unknown) duplicates=\(counts.duplicateExtras) " +
          "conflicts=\(counts.conflicts) waitingLong=\(counts.waitingLong)")

    check(snapshot.inboxFileCount == 13, "inbox 文件 13 个（含 1 个重复副本）")
    check(counts.totalMeetings == 12, "按内容 SHA 合并后 12 场会议")
    check(counts.pending == 2, "待审 2（普通 + 重复组只计 1）")
    check(counts.reviewing == 1, "审核中 1")
    check(counts.awaiting == 4, "待你决定 4（缺 accepted、冲突、旧回执、仅 followups）")
    check(counts.processed == 3, "已处理 3（全部保留、无候选、带业务跟进）")
    check(counts.unknown == 2, "未知 2（仅备注回执、坏回执）")
    check(counts.duplicateExtras == 1, "重复文件 1 个，不重复计数")
    check(counts.conflicts == 1, "冲突 1")
    check(counts.waitingLong == 1, "审核等待较久 1")

    func named(_ name: String) -> Meeting? {
        snapshot.meetings.first { $0.displayName == name }
    }

    if let waiting = named("待决定-技术评审") {
        check(waiting.status == .awaitingDecision, "缺 accepted 的明确候选进入待你决定")
        check(waiting.candidateCount == 3, "候选数 3")
        check(waiting.retainedCount == nil, "缺 accepted 时保留数为未记录（nil）")
        check((waiting.note ?? "").contains("accepted"), "旧回执缺 accepted 有提示")
    } else {
        check(false, "找到 待决定-技术评审")
    }

    if let reviewing = named("审核中-客户回访") {
        check(reviewing.status == .reviewing, "有 started 无回执为审核中")
        check(reviewing.waitingLong, "started 超过阈值显示等待较久")
    } else {
        check(false, "找到 审核中-客户回访")
    }

    if let processed = named("已处理-季度复盘") {
        check(processed.status == .processed, "accepted 覆盖候选为已处理")
        check(processed.retainedCount == 2, "已保留 2")
    } else {
        check(false, "找到 已处理-季度复盘")
    }

    if let processed = named("无候选") {
        check(processed.status == .processed, "items 为空视为 AI 判断无候选")
        check(processed.candidateCount == 0, "无候选计数为 0")
    } else {
        check(false, "找到 无候选")
    }

    if let processed = named("已处理-带跟进") {
        check(processed.status == .processed, "已处理场次可带业务跟进")
        check((processed.followupCount ?? 0) == 1, "业务跟进 1 项保留展示")
    } else {
        check(false, "找到 已处理-带跟进")
    }

    if let legacy = named("旧回执-仅备注") {
        check(legacy.status == .unknown, "仅备注的旧回执为状态未知")
        check(legacy.candidateCount == nil && legacy.retainedCount == nil, "旧回执缺字段显示未记录而非 0")
        check((legacy.note ?? "").contains("未记录"), "旧回执有未记录提示")
    } else {
        check(false, "找到 旧回执-仅备注")
    }

    if let bad = named("坏回执") {
        check(bad.status == .unknown, "损坏回执不崩溃，状态未知")
        check((bad.note ?? "").contains("无法解析"), "损坏回执有解析失败提示")
    } else {
        check(false, "找到 坏回执")
    }

    if let conflict = named("冲突-设计对齐") {
        check(conflict.status == .awaitingDecision, "两份判断冲突进入待你决定")
        check(conflict.conflict != nil, "冲突信息存在")
        check((conflict.conflict?.primarySummary ?? "").contains("主审"), "展示主审判断")
        check((conflict.conflict?.secondarySummary ?? "").contains("复核"), "展示复核判断")
    } else {
        check(false, "找到 冲突-设计对齐")
    }

    if let duplicate = named("重复-新") {
        check(duplicate.duplicateCount == 1, "同内容重复副本折叠为 1 个重复计数")
        check(duplicate.status == .pending, "重复组状态仍按唯一内容判断")
    } else {
        check(false, "重复组以最新副本命名")
    }

    if let htmlMeeting = named("待决定-技术评审") {
        check(htmlMeeting.htmlURL != nil, "存在详情 HTML 时可打开")
    }

    let model = PanelModel()
    model.apply(snapshot)
    check(model.counts == counts, "模型计数与自测计数一致")
    check(model.nextMeeting?.status == .awaitingDecision, "展开最近一场待你决定")
    check(model.menuTitle == "待审 2 · 待定 4 · 审核中 1", "菜单栏缩略状态含审核中")
    check(model.countsLine == "待审 2 · 审核中 1 · 待你决定 4", "浮窗三主计数")
    check(model.secondaryLine.contains("已处理 3") && model.secondaryLine.contains("未知 2"), "浮窗次计数")
    check(model.statusLine.contains("更新于"), "成功读取显示更新时间")

    // 权限/读取故障：保留旧数字，标记过期，不回落到 0。
    model.applyFailure("模拟权限故障")
    check(model.isStale, "读取故障标记过期")
    check(model.counts == counts, "故障后保留上次成功计数")
    check(model.statusLine.contains("无法读取会议库"), "故障文案明确")
    check(model.statusLine.contains("数字已过期"), "故障文案标记已过期")
    check(model.menuTitle.hasPrefix("⚠︎"), "菜单栏提示过期")

    // 首次读取即失败：显示 —，不显示 0。
    let freshModel = PanelModel()
    freshModel.beginVault()
    freshModel.applyFailure("模拟首次权限故障")
    check(freshModel.counts == nil, "首次失败没有计数")
    check(freshModel.countsLine.contains("—") && !freshModel.countsLine.contains("0"), "首次失败显示未记录")

    // 真实 POSIX 权限故障。
    let fm = FileManager.default
    let root = URL(fileURLWithPath: fm.currentDirectoryPath)
    let denied = root.appendingPathComponent(".build/selftest-denied", isDirectory: true)
    let deniedInbox = denied.appendingPathComponent("inbox", isDirectory: true)
    try? fm.createDirectory(at: deniedInbox, withIntermediateDirectories: true)
    try? "模拟权限测试".write(to: deniedInbox.appendingPathComponent("x.txt"), atomically: true, encoding: .utf8)
    try? fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: deniedInbox.path)
    var permissionThrew = false
    do {
        _ = try VaultReader().scan(vaultURL: denied)
    } catch {
        permissionThrew = true
        print("      权限错误：\(error.localizedDescription)")
    }
    try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: deniedInbox.path)
    check(permissionThrew, "POSIX 000 的 inbox 被识别为读取失败")
    try? fm.removeItem(at: denied)

    // 合法空库应为 0，而不是故障。
    let empty = root.appendingPathComponent(".build/selftest-empty", isDirectory: true)
    try? fm.createDirectory(at: empty.appendingPathComponent("inbox"), withIntermediateDirectories: true)
    try? fm.createDirectory(at: empty.appendingPathComponent(".meeting-review"), withIntermediateDirectories: true)
    do {
        let emptySnapshot = try VaultReader().scan(vaultURL: empty)
        check(emptySnapshot.meetings.isEmpty, "空库合法显示 0 场会议")
        check(PanelCounts.make(from: emptySnapshot.meetings) == PanelCounts(), "空库计数全 0")
    } catch {
        check(false, "空库读取失败：\(error.localizedDescription)")
    }
    try? fm.removeItem(at: empty)

    // 同一份 fixture 再读一次，SHA 应稳定（缓存复用路径也能工作）。
    if let second = try? VaultReader().scan(vaultURL: vaultURL) {
        let firstSHAs = Set(snapshot.meetings.map(\.sha256))
        let secondSHAs = Set(second.meetings.map(\.sha256))
        check(firstSHAs == secondSHAs, "重复读取 SHA 稳定")
    } else {
        check(false, "第二次读取 fixture")
    }

    // 目录事件触发（不含 GUI 渲染）：写新转写后应 ≤5 秒触发补读。
    let watchVault = root.appendingPathComponent(".build/selftest-watch", isDirectory: true)
    try? fm.createDirectory(at: watchVault.appendingPathComponent("inbox"), withIntermediateDirectories: true)
    try? fm.createDirectory(at: watchVault.appendingPathComponent(".meeting-review"), withIntermediateDirectories: true)
    try? "旧转写\n".write(
        to: watchVault.appendingPathComponent("inbox/旧.txt"),
        atomically: true,
        encoding: .utf8
    )
    let watcher = VaultWatcher()
    let fired = DispatchSemaphore(value: 0)
    watcher.onNeedsScan = { fired.signal() }
    watcher.start(vaultURL: watchVault)
    Thread.sleep(forTimeInterval: 0.3)
    let watchStart = Date()
    try? "新转写\n".write(
        to: watchVault.appendingPathComponent("inbox/新.txt"),
        atomically: true,
        encoding: .utf8
    )
    let watchResult = fired.wait(timeout: .now() + 5)
    let latency = Date().timeIntervalSince(watchStart)
    check(watchResult == .success, "目录事件/2.5 秒轮询触发补读")
    check(latency <= 5.0, String(format: "触发耗时 %.3f 秒 ≤ 5 秒（不含 GUI 渲染）", latency))
    watcher.stop()
    try? fm.removeItem(at: watchVault)

    if failures == 0 {
        print("RESULT: PASS \(checks)/\(checks)")
        return 0
    }
    print("RESULT: FAIL \(checks - failures)/\(checks)")
    return 1
}
