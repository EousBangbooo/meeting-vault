import AppKit

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 鼠标进出时通知控制器，用于收起态悬停显示操作按钮。
final class HoverEffectView: NSVisualEffectView {
    var onHover: ((Bool) -> Void)?
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let newArea = NSTrackingArea(rect: bounds,
                                     options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                     owner: self, userInfo: nil)
        addTrackingArea(newArea)
        area = newArea
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

/// 方向 A：一行状态条。收起只显示状态胶囊，展开从状态条向下长出当前会议。
/// 非激活常驻浮窗：不主动 activate App，不抢当前输入焦点。
final class PanelController: NSObject {
    let panel: FloatingPanel
    private let model: PanelModel
    var onOpenDetail: ((URL) -> Void)?
    var onDidChange: (() -> Void)?

    private let effect = HoverEffectView()
    private let dotLabel = NSTextField(labelWithString: "●")
    private let stripLabel = NSTextField(labelWithString: "")
    private let processedLabel = NSTextField(labelWithString: "")
    private let controlsStack = NSStackView()
    private let pinButton = NSButton()
    private let collapseButton = NSButton()

    private let detailStack = NSStackView()
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let stageLabel = NSTextField(labelWithString: "")
    private let nextCaption = NSTextField(labelWithString: "下一步")
    private let nextStepLabel = NSTextField(wrappingLabelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(wrappingLabelWithString: "")
    private let conflictLabel = NSTextField(wrappingLabelWithString: "")
    private let detailButton = NSButton()
    private let footnoteLabel = NSTextField(labelWithString: "")
    private let rootStack = NSStackView()

    private var isPinned = true
    private var isCollapsed = true
    private var isHovering = false
    private var positioned = false

    static let width: CGFloat = 256
    static let stripHeight: CGFloat = 34

    init(model: PanelModel) {
        self.model = model
        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.stripHeight),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
        buildUI()
        render()
    }

    var isVisible: Bool { panel.isVisible }
    /// 供桌面链路检查读取：保持原有完整计数文案。
    var displayedCounts: String { model.countsLine }
    var displayedSecondary: String { model.secondaryLine }
    var displayedStrip: String { stripLabel.stringValue }

    func show() {
        if (!positioned || !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) })),
           let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameTopLeftPoint(NSPoint(x: frame.maxX - Self.width - 12, y: frame.maxY - 10))
            positioned = true
        }
        panel.orderFrontRegardless()
        render()
    }

    func hide() {
        panel.orderOut(nil)
        onDidChange?()
    }

    func togglePin() {
        isPinned.toggle()
        panel.level = isPinned ? .floating : .normal
        render()
    }

    func refreshNow() { render() }

    private func configurePanel() {
        panel.title = "Meeting Vault"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
    }

    private func label(_ field: NSTextField, size: CGFloat, weight: NSFont.Weight, color: NSColor, lines: Int = 1) {
        field.font = NSFont.systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.maximumNumberOfLines = lines
        field.lineBreakMode = .byTruncatingTail
        if lines != 1 { field.cell?.wraps = true; field.cell?.truncatesLastVisibleLine = true }
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private func buildUI() {
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.masksToBounds = true
        effect.onHover = { [weak self] inside in
            self?.isHovering = inside
            self?.updateControlsVisibility()
        }
        panel.contentView = effect

        // —— 状态条 ——
        dotLabel.font = NSFont.systemFont(ofSize: 9, weight: .bold)
        dotLabel.setContentHuggingPriority(.required, for: .horizontal)
        stripLabel.maximumNumberOfLines = 1
        stripLabel.lineBreakMode = .byTruncatingTail
        stripLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stripLabel.setAccessibilityLabel("会议状态")
        label(processedLabel, size: 11, weight: .regular, color: .tertiaryLabelColor)
        processedLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        processedLabel.setContentHuggingPriority(.required, for: .horizontal)
        processedLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        configureIconButton(pinButton, title: "📌", tip: "置顶", action: #selector(pinTapped))
        configureIconButton(collapseButton, title: "⌄", tip: "展开", action: #selector(collapseTapped))
        let closeButton = NSButton()
        configureIconButton(closeButton, title: "✕", tip: "关闭（可从菜单栏恢复）", action: #selector(closeTapped))
        controlsStack.orientation = .horizontal
        controlsStack.spacing = 6
        controlsStack.setViews([pinButton, collapseButton, closeButton], in: .leading)
        controlsStack.setContentHuggingPriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let strip = NSStackView(views: [dotLabel, stripLabel, spacer, processedLabel, controlsStack])
        strip.orientation = .horizontal
        strip.alignment = .centerY
        strip.spacing = 6
        strip.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 12)
        strip.heightAnchor.constraint(equalToConstant: Self.stripHeight).isActive = true

        // —— 展开内容 ——
        label(titleLabel, size: 15, weight: .bold, color: .labelColor, lines: 2)
        label(stageLabel, size: 12, weight: .semibold, color: .systemOrange)
        label(nextCaption, size: 10, weight: .regular, color: .tertiaryLabelColor)
        label(nextStepLabel, size: 12, weight: .regular, color: .labelColor, lines: 2)
        label(metaLabel, size: 11, weight: .regular, color: .secondaryLabelColor)
        label(summaryLabel, size: 11, weight: .regular, color: .secondaryLabelColor, lines: 2)
        label(conflictLabel, size: 11, weight: .medium, color: .systemOrange, lines: 3)
        label(footnoteLabel, size: 10, weight: .regular, color: .tertiaryLabelColor)
        footnoteLabel.alignment = .right

        detailButton.title = "查看详情 →"
        detailButton.target = self
        detailButton.action = #selector(detailTapped)
        detailButton.isBordered = false
        detailButton.bezelStyle = .inline
        detailButton.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        detailButton.contentTintColor = .controlAccentColor
        detailButton.setContentHuggingPriority(.required, for: .horizontal)

        let footer = NSStackView(views: [detailButton, footnoteLabel])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.distribution = .fill

        let nextGroup = NSStackView(views: [nextCaption, nextStepLabel])
        nextGroup.orientation = .vertical
        nextGroup.alignment = .leading
        nextGroup.spacing = 1

        let topDivider = NSBox(); topDivider.boxType = .separator
        let bottomDivider = NSBox(); bottomDivider.boxType = .separator

        detailStack.orientation = .vertical
        detailStack.alignment = .leading
        detailStack.spacing = 6
        detailStack.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 12, right: 14)
        detailStack.setViews([topDivider, titleLabel, stageLabel, nextGroup, metaLabel,
                              summaryLabel, conflictLabel, bottomDivider, footer], in: .top)
        detailStack.setCustomSpacing(10, after: topDivider)
        detailStack.setCustomSpacing(2, after: titleLabel)
        detailStack.setCustomSpacing(10, after: stageLabel)
        detailStack.setCustomSpacing(10, after: conflictLabel)
        for view in [topDivider, titleLabel, nextGroup, nextStepLabel, metaLabel, summaryLabel,
                     conflictLabel, bottomDivider, footer] {
            view.widthAnchor.constraint(equalToConstant: Self.width - 28).isActive = true
        }
        for field in [titleLabel, nextStepLabel, summaryLabel, conflictLabel] {
            field.preferredMaxLayoutWidth = Self.width - 28
        }

        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 0
        rootStack.setViews([strip, detailStack], in: .top)
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: effect.topAnchor),
            strip.widthAnchor.constraint(equalToConstant: Self.width),
            detailStack.widthAnchor.constraint(equalToConstant: Self.width)
        ])
    }

    private func configureIconButton(_ button: NSButton, title: String, tip: String, action: Selector) {
        button.title = title
        button.toolTip = tip
        button.setAccessibilityLabel(tip)
        button.target = self
        button.action = action
        button.isBordered = false
        button.bezelStyle = .inline
        button.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        button.contentTintColor = .secondaryLabelColor
        button.setContentHuggingPriority(.required, for: .horizontal)
    }

    @objc private func detailTapped() {
        guard let url = model.nextMeeting?.htmlURL else { return }
        onOpenDetail?(url)
    }

    @objc private func pinTapped() { togglePin() }
    @objc private func closeTapped() { hide() }

    @objc private func collapseTapped() {
        isCollapsed.toggle()
        render()
    }

    private func updateControlsVisibility() {
        // 收起态只在悬停时出现操作；展开态常驻。
        let show = isHovering || !isCollapsed
        controlsStack.isHidden = !show
        processedLabel.isHidden = show && isCollapsed
        let (text, dot, color) = stripText(compact: show)
        stripLabel.attributedStringValue = text
        dotLabel.stringValue = dot
        dotLabel.textColor = color
    }

    // MARK: - 状态条文字

    private func stripText(compact: Bool) -> (NSAttributedString, String, NSColor) {
        let strong: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold), .foregroundColor: NSColor.labelColor]
        let normal: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor]
        let text = NSMutableAttributedString()

        guard model.hasVault else {
            text.append(NSAttributedString(string: "未选择会议库", attributes: normal))
            return (text, "●", .tertiaryLabelColor)
        }
        guard let counts = model.counts else {
            if model.isStale {
                text.append(NSAttributedString(string: "读取失败", attributes: strong))
                text.append(NSAttributedString(string: " · 计数未显示", attributes: normal))
                return (text, "⚠︎", .systemRed)
            }
            text.append(NSAttributedString(string: "正在读取…", attributes: normal))
            return (text, "●", .tertiaryLabelColor)
        }

        var rest: [String] = []
        let dot: String
        let dotColor: NSColor
        if model.isStale {
            text.append(NSAttributedString(string: "过期  ", attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.systemRed]))
        }
        if counts.awaiting > 0 {
            text.append(NSAttributedString(string: "\(compact ? "待定" : "待你决定") \(counts.awaiting)", attributes: strong))
            dot = "●"; dotColor = .systemOrange
        } else {
            dot = "●"; dotColor = counts.reviewing > 0 ? .controlAccentColor : .tertiaryLabelColor
        }
        if counts.pending > 0 || counts.awaiting == 0 { rest.append("待审 \(counts.pending)") }
        if counts.reviewing > 0 || counts.awaiting == 0 {
            rest.append("\(compact ? "在审" : "审核中") \(counts.reviewing)")
        }
        let restText = rest.joined(separator: " · ")
        if !restText.isEmpty {
            text.append(NSAttributedString(string: (text.length > 0 ? "  " : "") + restText, attributes: normal))
        }
        if model.isStale {
            return (text, "⚠︎", .systemRed)
        }
        return (text, dot, dotColor)
    }

    // MARK: - 渲染

    func render() {
        processedLabel.stringValue = model.counts.map { "✓\($0.processed)" } ?? ""
        processedLabel.toolTip = model.counts.map { "已处理 \($0.processed)" }
        stripLabel.toolTip = model.countsLine + "\n" + model.secondaryLine + "\n" + model.statusLine
        stripLabel.setAccessibilityValue(stripLabel.toolTip)

        pinButton.alphaValue = isPinned ? 1 : 0.35
        pinButton.toolTip = isPinned ? "已置顶（点按取消）" : "置顶"
        pinButton.setAccessibilityLabel(pinButton.toolTip)
        collapseButton.title = isCollapsed ? "⌄" : "⌃"
        collapseButton.toolTip = isCollapsed ? "展开" : "收起"
        collapseButton.setAccessibilityLabel(collapseButton.toolTip)

        if let meeting = model.nextMeeting {
            titleLabel.stringValue = meeting.displayName.isEmpty ? "未记录" : meeting.displayName
            let candidates = meeting.candidateCount.map { "\($0) 条候选" } ?? "候选未记录"
            stageLabel.stringValue = "\(meeting.status.label) · \(candidates)"
            stageLabel.textColor = meeting.status == .awaitingDecision ? .systemOrange : .secondaryLabelColor
            nextStepLabel.stringValue = meeting.nextStep
            let retained = meeting.retainedCount.map(String.init) ?? "—"
            let followups = meeting.followupCount.map(String.init) ?? "—"
            metaLabel.stringValue = "已保留 \(retained)   会后更新 \(followups)"
            summaryLabel.stringValue = meeting.summary
            summaryLabel.isHidden = meeting.summary.isEmpty
            if let conflict = meeting.conflict {
                conflictLabel.stringValue = "分歧：\(conflict.primarySummary) / \(conflict.secondarySummary)"
                conflictLabel.toolTip = conflict.detail
                conflictLabel.isHidden = false
            } else if let note = meeting.note {
                conflictLabel.stringValue = note
                conflictLabel.toolTip = nil
                conflictLabel.isHidden = false
            } else {
                conflictLabel.isHidden = true
            }
            detailButton.isEnabled = meeting.htmlURL != nil
            detailButton.alphaValue = meeting.htmlURL != nil ? 1 : 0.4
        } else {
            titleLabel.stringValue = model.isStale ? "会议库读取失败" : (model.hasVault ? "暂无会议" : "未选择会议库")
            stageLabel.stringValue = "—"
            stageLabel.textColor = .secondaryLabelColor
            if model.isStale {
                nextStepLabel.stringValue = "请检查会议库权限，或从菜单栏重新选择会议库"
            } else {
                nextStepLabel.stringValue = model.hasVault ? "在元宝点「复制转写」后会自动入箱" : "从菜单栏「选择会议库…」开始"
            }
            metaLabel.stringValue = ""
            summaryLabel.isHidden = true
            conflictLabel.isHidden = true
            detailButton.isEnabled = false
            detailButton.alphaValue = 0.4
        }
        // 技术信息只放在悬停提示与菜单栏；页脚仅在异常时提示。
        footnoteLabel.stringValue = model.isStale ? "数字已过期" : ""
        footnoteLabel.textColor = .systemRed
        footnoteLabel.toolTip = model.statusLine

        detailStack.isHidden = isCollapsed
        updateControlsVisibility()
        resize()
        onDidChange?()
    }

    private func resize() {
        effect.layer?.cornerRadius = isCollapsed ? Self.stripHeight / 2 : 12
        rootStack.layoutSubtreeIfNeeded()
        let height = isCollapsed ? Self.stripHeight : ceil(rootStack.fittingSize.height)
        let size = NSSize(width: Self.width, height: height)
        guard panel.frame.size != size else { return }
        let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        panel.setContentSize(size)
        if positioned { panel.setFrameTopLeftPoint(topLeft) }
    }
}
