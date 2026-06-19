import Cocoa
#if DEBUG
import SwiftUI
#endif

enum TicketAlertLevel: Equatable {
    case none
    case low
    case medium
    case high
    case critical

    static func from(count: Int) -> TicketAlertLevel {
        switch count {
        case 0: return .none
        case 1...3: return .low
        case 4...7: return .medium
        case 8...19: return .high
        default: return .critical
        }
    }

    var fillColor: NSColor {
        switch self {
        case .none: return .clear
        case .low: return NSColor.systemGreen
        case .medium: return NSColor.systemOrange
        case .high: return NSColor(calibratedRed: 0.92, green: 0.45, blue: 0.05, alpha: 1)
        case .critical: return NSColor(calibratedRed: 0.72, green: 0.76, blue: 0.82, alpha: 1)
        }
    }

    var textColor: NSColor {
        switch self {
        case .none: return .labelColor
        case .low, .medium, .high: return .white
        case .critical: return NSColor(calibratedWhite: 0.12, alpha: 1)
        }
    }

    var showsAlertBanner: Bool { self == .critical }
}

enum StatusTone {
    case success
    case warning
    case error
    case neutral
    case muted

    var textColor: NSColor {
        switch self {
        case .success: return .systemGreen
        case .warning: return .systemOrange
        case .error: return .systemRed
        case .neutral: return .labelColor
        case .muted: return .secondaryLabelColor
        }
    }
}

private enum PanelGrid {
    static let unit: CGFloat = 4

    static let hairline = unit / 2 // 2
    static let xxs = unit        // 4
    static let xs  = unit * 2    // 8
    static let sm  = unit * 3    // 12
    static let md  = unit * 4    // 16
    static let lg  = unit * 5    // 20
    static let xl  = unit * 6    // 24
}

private enum PanelDesign {
    /// 18pt content column — panel edges and glass module L/R (lg − 2).
    private static let contentInset = PanelGrid.lg - 2

    /// Horizontal inset for glass section cards inside the modal content area.
    static let sectionCardMargin = PanelGrid.sm

    static let width: CGFloat = 420
    static let outerPadding = NSEdgeInsets(
        top: PanelGrid.lg, left: contentInset+2, bottom: contentInset, right: contentInset+2
    )
    static let sectionSpacing: CGFloat = contentInset
    static let glassModuleSpacing = PanelGrid.lg
    static let soundModuleSpacing = PanelGrid.lg + 2
    static let rowSpacing: CGFloat = 0
    static let innerSpacing = PanelGrid.xs
    static let panelCornerRadius = contentInset
    static let glassCornerRadius = contentInset
    static let toolbarCornerRadius = PanelGrid.sm - 2
    static let buttonCornerRadius = PanelGrid.sm - 2
    static let glassBorderAlpha: CGFloat = 0.14
    static let moduleContentInset: CGFloat = contentInset
    static let moduleInsets = NSEdgeInsets(
        top: PanelGrid.md - 2, left: moduleContentInset, bottom: PanelGrid.md - 2, right: moduleContentInset
    )
    static let sectionRowInsets = moduleInsets
    static let moduleHeaderToBodyGap = PanelGrid.sm - 2
    static let soundHeaderToSliderGap = PanelGrid.sm
    static let filterRowHeight = PanelGrid.xl
    static let watchersModuleVerticalInset: CGFloat = 10
    static let watchersModuleInsets = NSEdgeInsets(
        top: watchersModuleVerticalInset,
        left: sectionRowInsets.left,
        bottom: watchersModuleVerticalInset,
        right: sectionRowInsets.right
    )
    static let watchersHeaderToFilterGap = PanelGrid.hairline
    static let watchersHeaderHeight = PanelGrid.md
    static let toggleControlWidth: CGFloat = 51
    static let toggleControlHeight: CGFloat = 31
    static let filterToolbarSpacing = PanelGrid.unit + 2
    static let actionButtonWidth: CGFloat = 148
    static let actionButtonHeight: CGFloat = 30
    static let actionGridSpacing = PanelGrid.xs
    static let actionSectionPadding = NSEdgeInsets(
        top: PanelGrid.sm, left: moduleContentInset, bottom: PanelGrid.sm, right: moduleContentInset
    )
    static var actionGridWidth: CGFloat { actionButtonWidth * 2 + actionGridSpacing }
    static let accentGreen = NSColor(calibratedRed: 0.20, green: 0.78, blue: 0.35, alpha: 1)
    static let accentBlue = NSColor(calibratedRed: 0.0, green: 0.48, blue: 1.0, alpha: 1)

    static func alertsToggleActiveTint() -> NSColor {
        let preference = UserDefaults.standard.string(forKey: "dxfilters.alertsToggleAccent")
            ?? UserDefaults.standard.string(forKey: "jntc.alertsToggleAccent")
            ?? "blue"
        return preference == "green" ? accentGreen : accentBlue
    }

    static func applyControlTint(_ color: NSColor?, to control: NSControl) {
        guard control.responds(to: Selector(("setContentTintColor:"))) else { return }
        control.setValue(color, forKey: "contentTintColor")
    }

    static func keepControlActiveWhenInactive(_ control: NSControl) {
        control.cell?.setValue(false, forKey: "appearsDisabledWhenInactive")
    }

    static func bindFullWidth(_ view: NSView, in stack: NSStackView) {
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])
    }

    static func bindSectionCard(_ view: NSView, in stack: NSStackView) {
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: sectionCardMargin),
            view.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -sectionCardMargin),
        ])
    }

    static func pinModuleContent(_ content: NSView, in container: NSView, insets: NSEdgeInsets) {
        if content.superview !== container {
            container.addSubview(content)
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: insets.left),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -insets.right),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: insets.top),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -insets.bottom),
        ])
    }
}

private enum PanelTypography {
    static let capsTransform: (String) -> String = { $0.uppercased() }

    static func labelFont(size: CGFloat = 11, weight: NSFont.Weight = .medium) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }

    static func valueFont(size: CGFloat = 11, weight: NSFont.Weight = .semibold, monospaced: Bool = false) -> NSFont {
        if monospaced {
            return .monospacedDigitSystemFont(ofSize: size, weight: weight)
        }
        return .systemFont(ofSize: size, weight: weight)
    }
}

private final class RunningIndicatorView: NSView {
    var isActive = false {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 8, height: 8) }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(ovalIn: rect)
        let color = isActive ? PanelDesign.accentGreen : NSColor.tertiaryLabelColor
        color.setFill()
        path.fill()
        if isActive {
            color.withAlphaComponent(0.35).setStroke()
            path.lineWidth = 2
            path.stroke()
        }
    }
}

private class GlassContainerView: NSVisualEffectView {
    init(cornerRadius: CGFloat = PanelDesign.glassCornerRadius) {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(PanelDesign.glassBorderAlpha).cgColor
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// GlassModuleView — WATCHERS bubble: VStack { HeaderRow, FilterRow }.
private final class WatchersGlassModuleView: GlassContainerView {
    let filterPopup = NSPopUpButton()
    private let sectionIcon = NSImageView()
    private let sectionLabel = NSTextField(labelWithString: "WATCHERS")
    private let sectionTitle = NSStackView()
    private let renameButton = NSButton(frame: .zero)
    private let deleteButton = NSButton(frame: .zero)
    private let addButton = NSButton(frame: .zero)
    private let headerRow = NSStackView()
    private let filterRow = NSStackView()

    init() {
        super.init(cornerRadius: PanelDesign.glassCornerRadius)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(target: AnyObject?, selectAction: Selector, renameAction: Selector, deleteAction: Selector, addAction: Selector) {
        filterPopup.target = target
        filterPopup.action = selectAction
        renameButton.target = target
        renameButton.action = renameAction
        deleteButton.target = target
        deleteButton.action = deleteAction
        addButton.target = target
        addButton.action = addAction
    }

    func setDeleteEnabled(_ enabled: Bool) {
        deleteButton.isEnabled = enabled
    }

    func updateWatcherCount(_ count: Int) {
        let savedCount = max(count, 1)
        let tip = PanelTypography.capsTransform("\(savedCount) saved filter(s)")
        toolTip = tip
        sectionTitle.toolTip = tip
    }

    private func setup() {
        sectionIcon.image = JiraAssets.watchersEyeImage()
        sectionIcon.contentTintColor = .secondaryLabelColor
        sectionIcon.imageScaling = .scaleProportionallyDown
        sectionIcon.translatesAutoresizingMaskIntoConstraints = false

        sectionLabel.font = PanelTypography.labelFont(size: 11, weight: .medium)
        sectionLabel.textColor = .secondaryLabelColor
        sectionLabel.setContentHuggingPriority(.required, for: .horizontal)

        sectionTitle.orientation = .horizontal
        sectionTitle.spacing = PanelGrid.unit
        sectionTitle.alignment = .centerY
        sectionTitle.addArrangedSubview(sectionIcon)
        sectionTitle.addArrangedSubview(sectionLabel)
        sectionTitle.setContentHuggingPriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            sectionIcon.widthAnchor.constraint(equalToConstant: 16),
            sectionIcon.heightAnchor.constraint(equalToConstant: 16),
        ])

        filterPopup.font = PanelTypography.labelFont(size: 11, weight: .semibold)
        filterPopup.controlSize = .small
        filterPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)

        configureFilterActionButton(renameButton, symbol: "pencil", tooltip: "Rename filter")
        configureFilterActionButton(deleteButton, symbol: "trash", tooltip: "Remove filter")
        configureFilterActionButton(addButton, title: "+", tooltip: "Add watcher")

        headerRow.orientation = .horizontal
        headerRow.spacing = PanelGrid.unit
        headerRow.alignment = .centerY
        headerRow.addArrangedSubview(sectionTitle)

        filterRow.orientation = .horizontal
        filterRow.spacing = PanelDesign.filterToolbarSpacing
        filterRow.alignment = .centerY
        filterRow.addArrangedSubview(filterPopup)
        filterRow.addArrangedSubview(renameButton)
        filterRow.addArrangedSubview(deleteButton)
        filterRow.addArrangedSubview(addButton)

        let vStack = NSStackView(views: [headerRow, filterRow])
        vStack.orientation = .vertical
        vStack.spacing = PanelDesign.watchersHeaderToFilterGap
        vStack.alignment = .leading
        vStack.distribution = .fill
        vStack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            headerRow.heightAnchor.constraint(equalToConstant: PanelDesign.watchersHeaderHeight),
            filterRow.heightAnchor.constraint(equalToConstant: PanelDesign.filterRowHeight),
            filterPopup.heightAnchor.constraint(equalToConstant: PanelDesign.filterRowHeight),
            renameButton.widthAnchor.constraint(equalToConstant: PanelDesign.filterRowHeight),
            renameButton.heightAnchor.constraint(equalToConstant: PanelDesign.filterRowHeight),
            deleteButton.widthAnchor.constraint(equalToConstant: PanelDesign.filterRowHeight),
            deleteButton.heightAnchor.constraint(equalToConstant: PanelDesign.filterRowHeight),
            addButton.heightAnchor.constraint(equalToConstant: PanelDesign.filterRowHeight),
        ])
        PanelDesign.pinModuleContent(vStack, in: self, insets: PanelDesign.watchersModuleInsets)
    }

    private func configureFilterActionButton(_ button: NSButton, symbol: String, tooltip: String) {
        button.bezelStyle = .accessoryBarAction
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.isBordered = true
        button.controlSize = .small
        button.toolTip = tooltip
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.cornerCurve = .continuous
    }

    private func configureFilterActionButton(_ button: NSButton, title: String, tooltip: String) {
        button.title = PanelTypography.capsTransform(title)
        button.bezelStyle = .accessoryBarAction
        button.font = PanelTypography.labelFont(size: 10, weight: .semibold)
        button.controlSize = .small
        button.toolTip = tooltip
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.cornerCurve = .continuous
    }
}

/// Centered floating utility controls — width rhythm matches glass sections above.
private final class ActionsUtilitySectionView: GlassContainerView {
    init(
        checkNow: NSButton,
        testAlert: NSButton,
        openFilter: NSButton,
        resetBaseline: NSButton
    ) {
        super.init(cornerRadius: PanelDesign.toolbarCornerRadius)
        setup(checkNow: checkNow, testAlert: testAlert, openFilter: openFilter, resetBaseline: resetBaseline)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup(
        checkNow: NSButton,
        testAlert: NSButton,
        openFilter: NSButton,
        resetBaseline: NSButton
    ) {
        for button in [checkNow, testAlert, openFilter, resetBaseline] {
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: PanelDesign.actionButtonWidth),
                button.heightAnchor.constraint(equalToConstant: PanelDesign.actionButtonHeight),
            ])
        }

        let actionRowTop = NSStackView(views: [checkNow, testAlert])
        actionRowTop.orientation = .horizontal
        actionRowTop.spacing = PanelDesign.actionGridSpacing
        actionRowTop.alignment = .centerY
        actionRowTop.distribution = .fillEqually

        let actionRowBottom = NSStackView(views: [openFilter, resetBaseline])
        actionRowBottom.orientation = .horizontal
        actionRowBottom.spacing = PanelDesign.actionGridSpacing
        actionRowBottom.alignment = .centerY
        actionRowBottom.distribution = .fillEqually

        let actionGrid = NSStackView(views: [actionRowTop, actionRowBottom])
        actionGrid.orientation = .vertical
        actionGrid.spacing = PanelDesign.actionGridSpacing
        actionGrid.alignment = .centerX
        actionGrid.translatesAutoresizingMaskIntoConstraints = false

        let content = NSStackView(views: [actionGrid])
        content.orientation = .vertical
        content.alignment = .centerX
        content.edgeInsets = PanelDesign.actionSectionPadding
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            actionGrid.widthAnchor.constraint(equalToConstant: PanelDesign.actionGridWidth),
            actionRowTop.widthAnchor.constraint(equalTo: actionGrid.widthAnchor),
            actionRowBottom.widthAnchor.constraint(equalTo: actionGrid.widthAnchor),
        ])
    }
}

private final class StatusInfoRowView: NSView {
    let iconView = NSImageView()
    let labelField = NSTextField(labelWithString: "")
    let valueField = NSTextField(labelWithString: "")
    private let separator = NSBox()

    init(symbol: String, label: String, showsSeparator: Bool = true) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        iconView.contentTintColor = .secondaryLabelColor
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        labelField.stringValue = PanelTypography.capsTransform(label)
        labelField.font = PanelTypography.labelFont()
        labelField.textColor = .secondaryLabelColor
        labelField.lineBreakMode = .byTruncatingTail
        labelField.translatesAutoresizingMaskIntoConstraints = false

        valueField.font = PanelTypography.valueFont(monospaced: true)
        valueField.textColor = .labelColor
        valueField.alignment = .right
        valueField.translatesAutoresizingMaskIntoConstraints = false

        separator.boxType = .separator
        separator.isHidden = !showsSeparator
        separator.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(labelField)
        addSubview(valueField)
        addSubview(separator)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 36),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PanelDesign.moduleContentInset),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            labelField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: PanelGrid.sm),
            labelField.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -PanelDesign.moduleContentInset),
            valueField.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueField.leadingAnchor.constraint(greaterThanOrEqualTo: labelField.trailingAnchor, constant: PanelGrid.sm),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PanelDesign.moduleContentInset),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -PanelDesign.moduleContentInset),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateValue(_ text: String, tone: StatusTone = .neutral) {
        valueField.stringValue = PanelTypography.capsTransform(text)
        valueField.textColor = tone.textColor
    }
}

struct SavedFilter: Equatable {
    var id: String
    var name: String
    var jiraName: String
    var isRenamed: Bool
    var isActive: Bool
}

/// ponytail: macOS ships these in /System/Library/Sounds — no bundled audio files.
enum NotificationSound: String, CaseIterable {
    case glass
    case tink
    case pop
    case ping
    case purr

    var label: String { rawValue.capitalized }

    var fileURL: URL {
        URL(fileURLWithPath: "/System/Library/Sounds/\(label).aiff")
    }

    static let `default`: NotificationSound = .glass
}

struct MenuPanelState {
    var filterID: String = "12345"
    var filterName: String = "Filter"
    var filterJiraName: String = "Filter"
    var filterIsRenamed: Bool = false
    var issueCount: Int = 0
    var newCount: Int = 0
    var badgeCount: Int = 0
    var lastCheck: String = "—"
    var connection: String = "Starting"
    var connectionOK: Bool = false
    var statusLine: String = "Waiting for first check…"
    var statusDetail: String?
    var errorDetailExpanded: Bool = false
    var filterURL: String?
    var savedFilters: [SavedFilter] = []
    var doNotDisturbActive: Bool = false
    var doNotDisturbSummary: String = "Alerts on"
    var doNotDisturbModeRaw: Int = DoNotDisturbDuration.off.rawValue
    var notificationVolume: Double = 1.0
    var notificationSoundID: String = NotificationSound.default.rawValue
    var soundExpanded: Bool = false
    var jiraBaseURL: String = ""
    var jiraCredentialsConfigured: Bool = false
}

enum DoNotDisturbDuration: Int, CaseIterable {
    case off = 0
    case oneDay = 1
    case threeDays = 3
    case sevenDays = 7
    case untilOff = -1

    var menuTitle: String {
        switch self {
        case .off: return "Alerts on"
        case .oneDay: return "Muted · 1 day"
        case .threeDays: return "Muted · 3 days"
        case .sevenDays: return "Muted · 7 days"
        case .untilOff: return "Muted · until off"
        }
    }
}

protocol MenuPanelDelegate: AnyObject {
    func panelDidRequestCheck()
    func panelDidRequestTestNotification()
    func panelDidRequestOpenFilter()
    func panelDidRequestResetBaseline()
    func panelDidRequestSelectFilter(id: String)
    func panelDidRequestAddFilter()
    func panelDidRequestRenameFilter(id: String, currentName: String, jiraName: String)
    func panelDidRequestDeleteFilter(id: String, name: String)
    func panelDidSetDoNotDisturb(duration: DoNotDisturbDuration)
    func panelDidUpdateNotificationVolume(_ volume: Double)
    func panelDidSelectNotificationSound(_ soundID: String)
    func panelDidRequestPreviewNotificationSound()
    func panelDidRequestOpenSystemNotificationSettings()
    func panelDidRequestConfigureCredentials()
    func panelDidChangeSoundExpanded(_ expanded: Bool)
    func panelDidChangeErrorDetailExpanded(_ expanded: Bool)
    func panelDidRequestQuit()
}

final class MenuPanelView: NSVisualEffectView {
    weak var delegate: MenuPanelDelegate?

    private let headerIcon = NSImageView()
    private let headerTitle = NSTextField(labelWithString: "dxFilters")
    private let headerSubtitle = NSTextField(labelWithString: "")
    private let runningIndicator = RunningIndicatorView()
    private let alertBanner = NSTextField(labelWithString: "")
    private let errorGlass = GlassContainerView()
    private let errorSummaryLabel = NSTextField(labelWithString: "")
    private let errorDetailButton = NSButton(frame: .zero)
    private let errorDetailText = NSTextField(wrappingLabelWithString: "")
    private let filterSection = WatchersGlassModuleView()
    private let alertsToggle = NSSwitch()
    private let issuesRow = StatusInfoRowView(symbol: "tray.fill", label: "Issues in filter")
    private let newRow = StatusInfoRowView(symbol: "sparkles", label: "New since last check")
    private let dndRow = StatusInfoRowView(symbol: "moon.zzz", label: "Do not disturb")
    private let lastCheckRow = StatusInfoRowView(symbol: "clock", label: "Last check")
    private let connectionRow = StatusInfoRowView(symbol: "waveform.path.ecg", label: "Connection", showsSeparator: false)
    private let soundGlass = GlassContainerView()
    private let volumeSlider = NSSlider()
    private let volumeValueLabel = NSTextField(labelWithString: "100%")
    private var soundGalleryButtons: [NSButton] = []
    private let soundButton = NSButton(frame: .zero)
    private let credentialsButton = NSButton(frame: .zero)
    private let notificationSettingsButton = NSButton(frame: .zero)
    private let versionLabel = NSTextField(labelWithString: "")
    private var soundSectionHeightConstraint: NSLayoutConstraint!
    private var errorSectionHeightConstraint: NSLayoutConstraint!

    private var suppressFilterSelection = false
    private var suppressAlertsToggle = false
    private var suppressVolumeSlider = false
    private var currentFilters: [SavedFilter] = []
    private var soundExpanded = false
    private var keyWindowObserver: NSObjectProtocol?
    private var resignKeyObserver: NSObjectProtocol?

    static let panelWidth: CGFloat = PanelDesign.width
    static let collapsedHeight: CGFloat = 581
    static let versionFooterHeight: CGFloat = 12
    static let soundSectionHeight: CGFloat = 132
    static let errorBarHeight: CGFloat = 40
    static let errorDetailHeight: CGFloat = 72

    static var panelSize: NSSize {
        NSSize(width: panelWidth, height: collapsedHeight)
    }

    /// Additional stack spacing when SOUND sits between ALERTS and STATUS (two module gaps vs one).
    private static let soundExpansionModuleGapDelta = PanelGrid.xs
    private static let errorExpansionModuleGapDelta = PanelGrid.xs

    static func panelHeight(
        soundExpanded: Bool,
        errorVisible: Bool = false,
        errorExpanded: Bool = false
    ) -> CGFloat {
        var height = collapsedHeight
        if soundExpanded {
            height += soundSectionHeight + soundExpansionModuleGapDelta
        }
        if errorVisible {
            height += errorBarHeight + errorExpansionModuleGapDelta
            if errorExpanded {
                height += errorDetailHeight
            }
        }
        return height
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func update(state: MenuPanelState) {
        refreshBrandIcon()

        let subtitle = Self.headerSubtitleText(
            from: state.statusLine,
            issueCount: state.issueCount,
            hasErrorDetail: state.statusDetail != nil
        )
        headerSubtitle.stringValue = subtitle
        runningIndicator.isActive = state.connectionOK && state.connection == "Running"

        issuesRow.updateValue("\(state.issueCount)", tone: .neutral)
        newRow.updateValue("\(state.newCount)", tone: state.newCount > 0 ? .success : .neutral)

        let dndTone: StatusTone = state.doNotDisturbActive ? .warning : .success
        let dndValue = state.doNotDisturbActive
            ? state.doNotDisturbSummary.replacingOccurrences(of: " · ", with: " • ")
            : "Alerts on"
        dndRow.updateValue(dndValue, tone: dndTone)

        lastCheckRow.updateValue(state.lastCheck, tone: .neutral)

        let connectionTone: StatusTone = {
            if state.connection == "Setup required" { return .warning }
            if !state.connectionOK { return .error }
            if state.connection == "Paused" { return .warning }
            if state.connection == "Running" { return .success }
            return .neutral
        }()
        connectionRow.updateValue(state.connection, tone: connectionTone)

        suppressAlertsToggle = true
        alertsToggle.state = state.doNotDisturbActive ? .off : .on
        suppressAlertsToggle = false
        updateAlertsToggleTint()

        updateAlertBanner(issueCount: state.issueCount)
        updateErrorSection(state)
        filterSection.updateWatcherCount(state.savedFilters.isEmpty ? 1 : state.savedFilters.count)
        updateFilterPicker(state.savedFilters, activeID: state.filterID)

        setSoundExpanded(state.soundExpanded, notifyDelegate: false)

        suppressVolumeSlider = true
        volumeSlider.doubleValue = state.notificationVolume * 100
        volumeValueLabel.stringValue = Self.volumeLabel(for: state.notificationVolume)
        suppressVolumeSlider = false
        updateSoundGallery(selectedID: state.notificationSoundID)

        let configured = state.jiraCredentialsConfigured
        if configured {
            credentialsButton.toolTip = "Jira credentials saved (\(state.jiraBaseURL))"
            PanelDesign.applyControlTint(PanelDesign.accentGreen, to: credentialsButton)
        } else {
            credentialsButton.toolTip = "Set Jira URL and personal access token"
            PanelDesign.applyControlTint(.systemOrange, to: credentialsButton)
        }
    }

    private static func volumeLabel(for volume: Double) -> String {
        "\(Int(round(volume * 100)))%"
    }

    private func setSoundExpanded(_ expanded: Bool, notifyDelegate: Bool) {
        soundExpanded = expanded
        soundGlass.isHidden = !expanded
        soundSectionHeightConstraint.constant = expanded ? Self.soundSectionHeight : 0
        PanelDesign.applyControlTint(expanded ? PanelDesign.accentGreen : nil, to: soundButton)
        needsLayout = true
        layoutSubtreeIfNeeded()
        if notifyDelegate {
            delegate?.panelDidChangeSoundExpanded(expanded)
        }
    }

    func refreshBrandIcon() {
        headerIcon.image = JiraAssets.panelIcon()
    }

    private static func headerSubtitleText(
        from statusLine: String,
        issueCount: Int,
        hasErrorDetail: Bool = false
    ) -> String {
        if hasErrorDetail {
            return PanelTypography.capsTransform("See details below")
        }
        let compact = shortStatus(statusLine)
        if compact.lowercased().contains("credentials required") {
            return PanelTypography.capsTransform("Credentials required")
        }
        if compact.lowercased().contains("baseline") {
            return PanelTypography.capsTransform("Baseline saved • \(issueCount) issues")
        }
        if compact.lowercased().contains("up to date") || compact.lowercased().contains("no new") {
            return PanelTypography.capsTransform("Up to date • \(issueCount) issues")
        }
        return PanelTypography.capsTransform(compact.replacingOccurrences(of: " · ", with: " • "))
    }

    private func updateErrorSection(_ state: MenuPanelState) {
        guard let detail = state.statusDetail, !detail.isEmpty else {
            errorGlass.isHidden = true
            errorSectionHeightConstraint.constant = 0
            errorDetailText.isHidden = true
            return
        }

        errorGlass.isHidden = false
        errorSummaryLabel.stringValue = PanelTypography.capsTransform(Self.shortStatus(state.statusLine))
        errorDetailText.stringValue = detail
        errorDetailText.isHidden = !state.errorDetailExpanded
        errorDetailButton.title = state.errorDetailExpanded ? "Hide" : "Details"
        var height = Self.errorBarHeight
        if state.errorDetailExpanded {
            height += Self.errorDetailHeight
        }
        errorSectionHeightConstraint.constant = height
    }

    private func updateAlertBanner(issueCount: Int) {
        let level = TicketAlertLevel.from(count: issueCount)
        guard level.showsAlertBanner else {
            alertBanner.isHidden = true
            return
        }
        alertBanner.stringValue = PanelTypography.capsTransform("Alert • \(issueCount) tickets in filter")
        alertBanner.isHidden = false
    }

    private func updateFilterPicker(_ filters: [SavedFilter], activeID: String) {
        currentFilters = filters
        let filterPopup = filterSection.filterPopup
        suppressFilterSelection = true
        filterPopup.removeAllItems()

        let entries = filters.isEmpty ? [] : filters
        if entries.isEmpty {
            filterPopup.addItem(withTitle: "NO FILTERS")
        } else {
            for filter in entries {
                let title = Self.filterMenuTitle(for: filter)
                filterPopup.addItem(withTitle: title)
                let index = filterPopup.numberOfItems - 1
                filterPopup.item(at: index)?.representedObject = filter.id
                if filter.isRenamed {
                    filterPopup.item(at: index)?.toolTip = Self.filterPreviewTitle(for: filter)
                } else {
                    filterPopup.item(at: index)?.toolTip = "#\(filter.id)"
                }
                if filter.id == activeID || (filter.isActive && activeID.isEmpty) {
                    filterPopup.selectItem(at: index)
                }
            }
        }

        if filterPopup.indexOfSelectedItem < 0, filterPopup.numberOfItems > 0 {
            filterPopup.selectItem(at: 0)
        }

        if let active = entries.first(where: { $0.id == activeID }) ?? entries.first(where: \.isActive) {
            filterPopup.toolTip = active.isRenamed ? Self.filterPreviewTitle(for: active) : "#\(active.id)"
        } else {
            filterPopup.toolTip = nil
        }

        suppressFilterSelection = false
        filterSection.setDeleteEnabled(filters.count > 1)
    }

    private static func filterMenuTitle(for filter: SavedFilter) -> String {
        PanelTypography.capsTransform("\(filter.name) • #\(filter.id)")
    }

    private static func filterPreviewTitle(for filter: SavedFilter) -> String {
        PanelTypography.capsTransform("\(filter.jiraName) • #\(filter.id)")
    }

    private static func shortStatus(_ text: String) -> String {
        var oneLine = text.replacingOccurrences(of: "\n", with: " ")
        let lower = oneLine.lowercased()
        if lower.contains("jira_pat") || (lower.contains("jira_base_url") && lower.contains("set")) {
            return "Credentials required"
        }
        if oneLine.contains("site-packages") || oneLine.hasPrefix("/") {
            if let range = oneLine.range(of: "Set ") {
                oneLine = String(oneLine[range.lowerBound...])
            } else if let range = oneLine.range(of: "Check failed") {
                oneLine = String(oneLine[range.lowerBound...])
            }
        }
        if oneLine.count <= 72 { return oneLine }
        return String(oneLine.prefix(69)) + "…"
    }

    private func setup() {
        material = .underWindowBackground
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = PanelDesign.panelCornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = false
        layer?.borderWidth = 0.75
        layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.35
        layer?.shadowRadius = 24
        layer?.shadowOffset = NSSize(width: 0, height: -8)

        headerTitle.font = PanelTypography.labelFont(size: 17, weight: .semibold)
        headerTitle.textColor = .labelColor
        headerTitle.toolTip = "dxFilters"

        headerSubtitle.font = PanelTypography.labelFont(size: 10, weight: .medium)
        headerSubtitle.textColor = .tertiaryLabelColor
        headerSubtitle.lineBreakMode = .byTruncatingTail
        headerSubtitle.maximumNumberOfLines = 1

        alertBanner.font = PanelTypography.labelFont(size: 10, weight: .bold)
        alertBanner.textColor = TicketAlertLevel.critical.textColor
        alertBanner.backgroundColor = TicketAlertLevel.critical.fillColor
        alertBanner.drawsBackground = true
        alertBanner.alignment = .center
        alertBanner.isBezeled = false
        alertBanner.isEditable = false
        alertBanner.isBordered = false
        alertBanner.wantsLayer = true
        alertBanner.layer?.cornerRadius = PanelDesign.buttonCornerRadius
        alertBanner.layer?.cornerCurve = .continuous
        alertBanner.layer?.masksToBounds = true
        alertBanner.isHidden = true

        headerIcon.imageScaling = .scaleProportionallyUpOrDown
        headerIcon.image = JiraAssets.panelIcon()

        filterSection.configure(
            target: self,
            selectAction: #selector(filterSelectionChanged),
            renameAction: #selector(renameFilter),
            deleteAction: #selector(deleteFilter),
            addAction: #selector(addFilter)
        )

        alertsToggle.target = self
        alertsToggle.action = #selector(alertsToggleChanged)
        if #available(macOS 11.0, *) {
            alertsToggle.controlSize = .regular
        }
        updateAlertsToggleTint()

        let statusLine = NSStackView(views: [runningIndicator, headerSubtitle])
        statusLine.orientation = .horizontal
        statusLine.spacing = PanelDesign.innerSpacing
        statusLine.alignment = .centerY

        let titleStack = NSStackView(views: [headerTitle, statusLine])
        titleStack.orientation = .vertical
        titleStack.spacing = PanelGrid.xxs
        titleStack.alignment = .leading

        configureHeaderIconButton(
            credentialsButton,
            symbol: "key.fill",
            action: #selector(configureCredentials),
            tooltip: "Set Jira URL and PAT token"
        )
        configureHeaderIconButton(
            soundButton,
            symbol: "speaker.wave.2.fill",
            action: #selector(toggleSoundSection),
            tooltip: "Sound volume"
        )
        configureHeaderIconButton(
            notificationSettingsButton,
            symbol: "gearshape",
            action: #selector(openNotificationSettings),
            tooltip: "Notification Center settings"
        )
        let quitButton = glassIconButton(symbol: "power", action: #selector(quit))
        quitButton.toolTip = "Quit"

        let headerActions = NSStackView(views: [credentialsButton, soundButton, notificationSettingsButton, quitButton])
        headerActions.orientation = .horizontal
        headerActions.spacing = PanelDesign.filterToolbarSpacing
        headerActions.alignment = .centerY

        let headerRow = NSStackView(views: [headerIcon, titleStack, NSView(), headerActions])
        headerRow.orientation = .horizontal
        headerRow.spacing = PanelGrid.sm
        headerRow.alignment = .centerY
        headerIcon.widthAnchor.constraint(equalToConstant: 24).isActive = true
        headerIcon.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let alertsLabel = NSTextField(labelWithString: "ALERTS")
        alertsLabel.font = PanelTypography.labelFont(size: 12, weight: .semibold)
        alertsLabel.textColor = .labelColor

        let alertsSpacer = NSView()
        alertsSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let alertsRowContent = NSStackView(views: [alertsLabel, alertsSpacer, alertsToggle])
        alertsRowContent.orientation = .horizontal
        alertsRowContent.spacing = PanelDesign.innerSpacing
        alertsRowContent.alignment = .centerY
        alertsRowContent.translatesAutoresizingMaskIntoConstraints = false

        let alertsGlass = GlassContainerView()
        PanelDesign.pinModuleContent(alertsRowContent, in: alertsGlass, insets: PanelDesign.sectionRowInsets)

        let statusGlass = GlassContainerView()
        let statusStack = NSStackView(views: [
            issuesRow, newRow, dndRow, lastCheckRow, connectionRow,
        ])
        statusStack.orientation = .vertical
        statusStack.spacing = PanelDesign.rowSpacing
        statusStack.translatesAutoresizingMaskIntoConstraints = false
        statusGlass.addSubview(statusStack)
        NSLayoutConstraint.activate([
            statusStack.leadingAnchor.constraint(equalTo: statusGlass.leadingAnchor),
            statusStack.trailingAnchor.constraint(equalTo: statusGlass.trailingAnchor),
            statusStack.topAnchor.constraint(equalTo: statusGlass.topAnchor, constant: 6),
            statusStack.bottomAnchor.constraint(equalTo: statusGlass.bottomAnchor, constant: -6),
        ])

        let checkNow = glassActionButton(title: "Check Now", icon: "arrow.clockwise", action: #selector(checkNow))
        let testAlert = glassActionButton(title: "Test Alert", icon: "bell.badge", action: #selector(testAlert))
        let openFilter = glassActionButton(title: "Open Filter", icon: "safari", action: #selector(openFilter))
        let resetBaseline = glassActionButton(title: "Reset Baseline", icon: "arrow.counterclockwise", action: #selector(resetBaseline))
        let actionsSection = ActionsUtilitySectionView(
            checkNow: checkNow,
            testAlert: testAlert,
            openFilter: openFilter,
            resetBaseline: resetBaseline
        )

        setupSoundSection()
        setupErrorSection()

        versionLabel.font = PanelTypography.labelFont(size: 9, weight: .regular)
        versionLabel.textColor = .tertiaryLabelColor
        versionLabel.alignment = .center
        versionLabel.stringValue = Self.appVersionText()
        versionLabel.isEditable = false
        versionLabel.isBezeled = false
        versionLabel.drawsBackground = false
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        versionLabel.heightAnchor.constraint(equalToConstant: Self.versionFooterHeight).isActive = true

        let root = NSStackView(views: [
            headerRow,
            alertBanner,
            errorGlass,
            filterSection,
            alertsGlass,
            soundGlass,
            statusGlass,
            actionsSection,
            versionLabel,
        ])
        root.orientation = .vertical
        root.spacing = PanelDesign.sectionSpacing
        root.distribution = .gravityAreas
        root.alignment = .leading
        root.edgeInsets = PanelDesign.outerPadding
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            headerSubtitle.heightAnchor.constraint(equalToConstant: 14),
            alertBanner.heightAnchor.constraint(equalToConstant: 30),
        ])

        for section in [errorGlass, filterSection, alertsGlass, soundGlass, statusGlass, actionsSection] {
            PanelDesign.bindSectionCard(section, in: root)
        }
        PanelDesign.bindFullWidth(versionLabel, in: root)

        root.setCustomSpacing(PanelGrid.lg, after: headerRow)
        root.setCustomSpacing(PanelDesign.glassModuleSpacing, after: errorGlass)
        root.setCustomSpacing(PanelDesign.glassModuleSpacing, after: filterSection)
        root.setCustomSpacing(PanelDesign.soundModuleSpacing, after: alertsGlass)
        root.setCustomSpacing(PanelDesign.soundModuleSpacing, after: soundGlass)
        root.setCustomSpacing(PanelDesign.glassModuleSpacing, after: statusGlass)
        root.setCustomSpacing(PanelGrid.xxs, after: actionsSection)
    }

    private static func appVersionText() -> String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(short) (\(build))"
    }

    private func configureHeaderIconButton(_ button: NSButton, symbol: String, action: Selector, tooltip: String) {
        button.bezelStyle = .accessoryBarAction
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.isBordered = true
        button.target = self
        button.action = action
        button.controlSize = .small
        button.toolTip = tooltip
        button.widthAnchor.constraint(equalToConstant: 30).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.cornerCurve = .continuous
    }

    private func setupSoundSection() {
        soundGlass.isHidden = true
        soundGlass.clipsToBounds = false
        soundGlass.translatesAutoresizingMaskIntoConstraints = false
        soundSectionHeightConstraint = soundGlass.heightAnchor.constraint(equalToConstant: 0)
        soundSectionHeightConstraint.isActive = true

        let soundIcon = NSImageView()
        soundIcon.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: nil)
        soundIcon.contentTintColor = .secondaryLabelColor
        soundIcon.imageScaling = .scaleProportionallyDown
        soundIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            soundIcon.widthAnchor.constraint(equalToConstant: 16),
            soundIcon.heightAnchor.constraint(equalToConstant: 16),
        ])

        let soundLabel = NSTextField(labelWithString: "SOUND")
        soundLabel.font = PanelTypography.labelFont(size: 12, weight: .semibold)
        soundLabel.textColor = .labelColor

        volumeSlider.minValue = 0
        volumeSlider.maxValue = 100
        volumeSlider.doubleValue = 100
        volumeSlider.target = self
        volumeSlider.action = #selector(volumeSliderChanged)
        volumeSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)

        volumeValueLabel.font = PanelTypography.valueFont(size: 11, weight: .semibold, monospaced: true)
        volumeValueLabel.textColor = .secondaryLabelColor
        volumeValueLabel.alignment = .right
        volumeValueLabel.setContentHuggingPriority(.required, for: .horizontal)
        volumeValueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true

        let previewButton = toggleSizedIconButton(
            symbol: "play.fill",
            action: #selector(previewSound),
            tooltip: "Preview notification sound"
        )

        let soundHeaderSpacer = NSView()
        soundHeaderSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let soundHeaderRow = NSStackView(views: [soundLabel, soundHeaderSpacer, soundIcon, previewButton])
        soundHeaderRow.orientation = .horizontal
        soundHeaderRow.spacing = PanelDesign.innerSpacing
        soundHeaderRow.alignment = .centerY
        soundHeaderRow.translatesAutoresizingMaskIntoConstraints = false

        let sliderSpacer = NSView()
        sliderSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let sliderKnobInset = NSView()
        sliderKnobInset.translatesAutoresizingMaskIntoConstraints = false
        sliderKnobInset.widthAnchor.constraint(equalToConstant: PanelGrid.hairline).isActive = true

        let sliderRow = NSStackView(views: [sliderKnobInset, volumeSlider, sliderSpacer, volumeValueLabel])
        sliderRow.orientation = .horizontal
        sliderRow.spacing = PanelDesign.moduleHeaderToBodyGap
        sliderRow.alignment = .centerY
        sliderRow.translatesAutoresizingMaskIntoConstraints = false
        sliderRow.heightAnchor.constraint(equalToConstant: 22).isActive = true

        soundGalleryButtons = NotificationSound.allCases.map { sound in
            soundChipButton(title: sound.label, soundID: sound.rawValue)
        }
        let galleryRow = NSStackView(views: soundGalleryButtons)
        galleryRow.orientation = .horizontal
        galleryRow.spacing = PanelGrid.xxs
        galleryRow.distribution = .fillEqually
        galleryRow.alignment = .centerY
        galleryRow.translatesAutoresizingMaskIntoConstraints = false
        galleryRow.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let soundRowContent = NSStackView(views: [soundHeaderRow, sliderRow, galleryRow])
        soundRowContent.orientation = .vertical
        soundRowContent.spacing = PanelDesign.soundHeaderToSliderGap
        soundRowContent.alignment = .leading
        soundRowContent.distribution = .fill
        soundRowContent.translatesAutoresizingMaskIntoConstraints = false

        PanelDesign.pinModuleContent(soundRowContent, in: soundGlass, insets: PanelDesign.sectionRowInsets)
    }

    private func soundChipButton(title: String, soundID: String) -> NSButton {
        let button = NSButton(
            title: PanelTypography.capsTransform(title),
            target: self,
            action: #selector(soundGalleryTapped(_:))
        )
        button.identifier = NSUserInterfaceItemIdentifier(soundID)
        button.bezelStyle = .rounded
        button.controlSize = .mini
        button.font = PanelTypography.labelFont(size: 9, weight: .semibold)
        button.setButtonType(.toggle)
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    private func updateSoundGallery(selectedID: String) {
        for button in soundGalleryButtons {
            let selected = button.identifier?.rawValue == selectedID
            PanelDesign.applyControlTint(selected ? PanelDesign.accentGreen : nil, to: button)
            button.state = selected ? .on : .off
        }
    }

    @objc private func soundGalleryTapped(_ sender: NSButton) {
        guard let soundID = sender.identifier?.rawValue else { return }
        delegate?.panelDidSelectNotificationSound(soundID)
    }

    private func setupErrorSection() {
        errorGlass.isHidden = true
        errorGlass.clipsToBounds = true
        errorSectionHeightConstraint = errorGlass.heightAnchor.constraint(equalToConstant: 0)
        errorSectionHeightConstraint.isActive = true

        let errorIcon = NSImageView()
        errorIcon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        errorIcon.contentTintColor = .systemOrange
        errorIcon.imageScaling = .scaleProportionallyDown
        errorIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            errorIcon.widthAnchor.constraint(equalToConstant: 16),
            errorIcon.heightAnchor.constraint(equalToConstant: 16),
        ])

        errorSummaryLabel.font = PanelTypography.labelFont(size: 11, weight: .semibold)
        errorSummaryLabel.textColor = .systemOrange
        errorSummaryLabel.lineBreakMode = .byTruncatingTail
        errorSummaryLabel.maximumNumberOfLines = 1

        errorDetailButton.bezelStyle = .rounded
        errorDetailButton.controlSize = .small
        errorDetailButton.title = "Details"
        errorDetailButton.target = self
        errorDetailButton.action = #selector(toggleErrorDetail)
        errorDetailButton.setContentHuggingPriority(.required, for: .horizontal)

        errorDetailText.font = PanelTypography.labelFont(size: 10, weight: .regular)
        errorDetailText.textColor = .secondaryLabelColor
        errorDetailText.isHidden = true
        errorDetailText.maximumNumberOfLines = 0
        errorDetailText.preferredMaxLayoutWidth = PanelDesign.width - PanelDesign.sectionCardMargin * 2 - PanelDesign.moduleContentInset * 2

        let summarySpacer = NSView()
        summarySpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let summaryRow = NSStackView(views: [errorIcon, errorSummaryLabel, summarySpacer, errorDetailButton])
        summaryRow.orientation = .horizontal
        summaryRow.spacing = PanelDesign.innerSpacing
        summaryRow.alignment = .centerY
        summaryRow.translatesAutoresizingMaskIntoConstraints = false
        summaryRow.heightAnchor.constraint(equalToConstant: 22).isActive = true

        let errorContent = NSStackView(views: [summaryRow, errorDetailText])
        errorContent.orientation = .vertical
        errorContent.spacing = PanelGrid.xs
        errorContent.alignment = .leading
        errorContent.translatesAutoresizingMaskIntoConstraints = false

        PanelDesign.pinModuleContent(errorContent, in: errorGlass, insets: PanelDesign.sectionRowInsets)
    }

    @objc private func toggleErrorDetail() {
        delegate?.panelDidChangeErrorDetailExpanded(!errorDetailText.isHidden)
    }

    @objc private func volumeSliderChanged() {
        guard !suppressVolumeSlider else { return }
        let volume = volumeSlider.doubleValue / 100
        volumeValueLabel.stringValue = Self.volumeLabel(for: volume)
        delegate?.panelDidUpdateNotificationVolume(volume)
    }

    @objc private func previewSound() {
        delegate?.panelDidRequestPreviewNotificationSound()
    }

    @objc private func configureCredentials() { delegate?.panelDidRequestConfigureCredentials() }
    @objc private func toggleSoundSection() {
        setSoundExpanded(!soundExpanded, notifyDelegate: true)
    }

    @objc private func openNotificationSettings() {
        delegate?.panelDidRequestOpenSystemNotificationSettings()
    }

    private func glassIconButton(symbol: String, action: Selector) -> NSButton {
        let button = NSButton(frame: .zero)
        button.bezelStyle = .accessoryBarAction
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.isBordered = true
        button.target = self
        button.action = action
        button.controlSize = .small
        button.widthAnchor.constraint(equalToConstant: 30).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.cornerCurve = .continuous
        return button
    }

    private func toggleSizedIconButton(symbol: String, action: Selector, tooltip: String) -> NSButton {
        let button = NSButton(frame: .zero)
        button.bezelStyle = .rounded
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.target = self
        button.action = action
        button.toolTip = tooltip
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: PanelDesign.toggleControlWidth),
            button.heightAnchor.constraint(equalToConstant: PanelDesign.toggleControlHeight),
        ])
        return button
    }

    private func glassTextButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: PanelTypography.capsTransform(title), target: self, action: action)
        button.bezelStyle = .accessoryBarAction
        button.font = PanelTypography.labelFont(size: 11, weight: .semibold)
        button.controlSize = .regular
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.wantsLayer = true
        button.layer?.cornerRadius = PanelDesign.buttonCornerRadius
        button.layer?.cornerCurve = .continuous
        return button
    }

    private func glassActionButton(title: String, icon: String, action: Selector) -> NSButton {
        let button = NSButton(title: PanelTypography.capsTransform(title), target: self, action: action)
        button.bezelStyle = .accessoryBarAction
        button.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.font = PanelTypography.labelFont(size: 10, weight: .semibold)
        button.controlSize = .small
        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.cornerCurve = .continuous
        return button
    }

    private func activeFilter() -> SavedFilter? {
        guard let id = filterSection.filterPopup.selectedItem?.representedObject as? String else { return nil }
        return currentFilters.first { $0.id == id }
    }

    @objc private func alertsToggleChanged() {
        guard !suppressAlertsToggle else { return }
        updateAlertsToggleTint()
        let alertsOn = alertsToggle.state == .on
        delegate?.panelDidSetDoNotDisturb(duration: alertsOn ? .off : .untilOff)
    }

    private func updateAlertsToggleTint() {
        let alertsOn = alertsToggle.state == .on
        let tint: NSColor? = alertsOn ? PanelDesign.alertsToggleActiveTint() : nil
        PanelDesign.applyControlTint(tint, to: alertsToggle)
        PanelDesign.keepControlActiveWhenInactive(alertsToggle)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            removeKeyWindowObservers()
            return
        }
        updateAlertsToggleTint()
        guard keyWindowObserver == nil else { return }
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in self?.updateAlertsToggleTint() }
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in self?.updateAlertsToggleTint() }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            removeKeyWindowObservers()
        }
    }

    private func removeKeyWindowObservers() {
        if let keyWindowObserver {
            NotificationCenter.default.removeObserver(keyWindowObserver)
            self.keyWindowObserver = nil
        }
        if let resignKeyObserver {
            NotificationCenter.default.removeObserver(resignKeyObserver)
            self.resignKeyObserver = nil
        }
    }

    @objc private func filterSelectionChanged() {
        guard !suppressFilterSelection else { return }
        guard let id = filterSection.filterPopup.selectedItem?.representedObject as? String else { return }
        delegate?.panelDidRequestSelectFilter(id: id)
    }

    @objc private func renameFilter() {
        guard let filter = activeFilter() else { return }
        delegate?.panelDidRequestRenameFilter(
            id: filter.id,
            currentName: filter.name,
            jiraName: filter.jiraName
        )
    }

    @objc private func deleteFilter() {
        guard let filter = activeFilter() else { return }
        delegate?.panelDidRequestDeleteFilter(id: filter.id, name: filter.name)
    }

    @objc private func addFilter() { delegate?.panelDidRequestAddFilter() }
    @objc private func checkNow() { delegate?.panelDidRequestCheck() }
    @objc private func testAlert() { delegate?.panelDidRequestTestNotification() }
    @objc private func openFilter() { delegate?.panelDidRequestOpenFilter() }
    @objc private func resetBaseline() { delegate?.panelDidRequestResetBaseline() }
    @objc private func quit() { delegate?.panelDidRequestQuit() }
}

/// Menubar status content hosted inside `NSStatusBarButton` — never use `button.title`.
/// Layout: `[ pill ] > NSStackView [ NSImageView 18×18 | NSTextField badge ]`.
final class MenuBarStatusItemView: NSView {
    static let barHeight: CGFloat = 22
    static let iconSize: CGFloat = 18
    static let iconBadgeSpacing: CGFloat = 5
    static let stackLayoutInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
    static let badgeFontSize: CGFloat = 10.5

    private let pillBackground = NSView()
    private let contentStack = NSStackView()
    private let iconView = NSImageView()
    private let badgeLabel = NSTextField(labelWithString: "")
    private var stackLeadingConstraint: NSLayoutConstraint!
    private var stackTrailingConstraint: NSLayoutConstraint!
    private var widthConstraint: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override var intrinsicContentSize: NSSize {
        let badgeHidden = badgeLabel.isHidden
        let iconWidth = Self.iconSize
        guard !badgeHidden else {
            return NSSize(width: iconWidth, height: Self.barHeight)
        }
        let textWidth = badgeLabel.attributedStringValue.size().width
        let insets = Self.stackLayoutInsets
        let width = insets.left
            + iconWidth
            + Self.iconBadgeSpacing
            + ceil(textWidth)
            + insets.right
        return NSSize(width: width, height: Self.barHeight)
    }

    func apply(count: Int, severityCount: Int, pulse: CGFloat, animated: Bool) {
        let showBadge = count > 0
        let label = count > 99 ? "99+" : "\(count)"
        badgeLabel.stringValue = label
        badgeLabel.textColor = NSColor.white.withAlphaComponent(0.95 * pulse)
        _ = severityCount

        let updateVisibility = {
            self.badgeLabel.isHidden = !showBadge
            self.pillBackground.isHidden = !showBadge
            let insets = showBadge ? Self.stackLayoutInsets : .init()
            self.stackLeadingConstraint.constant = insets.left
            self.stackTrailingConstraint.constant = -insets.right
            self.widthConstraint.constant = self.intrinsicContentSize.width
            self.invalidateIntrinsicContentSize()
            self.superview?.needsLayout = true
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.22, 0.64, 1)
                context.allowsImplicitAnimation = true
                updateVisibility()
                self.layoutSubtreeIfNeeded()
            }
        } else {
            updateVisibility()
        }
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        widthConstraint = widthAnchor.constraint(equalToConstant: Self.iconSize)
        widthConstraint.isActive = true
        heightAnchor.constraint(equalToConstant: Self.barHeight).isActive = true

        pillBackground.wantsLayer = true
        pillBackground.layer?.cornerRadius = Self.barHeight / 2
        pillBackground.layer?.cornerCurve = .continuous
        pillBackground.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        pillBackground.layer?.borderWidth = 0.5
        pillBackground.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        pillBackground.translatesAutoresizingMaskIntoConstraints = false
        pillBackground.isHidden = true

        iconView.image = JiraAssets.menuBarLogoImage(pointSize: Self.iconSize)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.imageAlignment = .alignCenter
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: Self.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Self.iconSize),
        ])
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        badgeLabel.font = NSFont.menuBarFont(ofSize: Self.badgeFontSize)
        badgeLabel.textColor = .white
        badgeLabel.alignment = .left
        badgeLabel.isBezeled = false
        badgeLabel.isEditable = false
        badgeLabel.isBordered = false
        badgeLabel.isSelectable = false
        badgeLabel.drawsBackground = false
        badgeLabel.isHidden = true
        badgeLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        badgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        contentStack.orientation = .horizontal
        contentStack.spacing = Self.iconBadgeSpacing
        contentStack.alignment = .centerY
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(iconView)
        contentStack.addArrangedSubview(badgeLabel)

        addSubview(pillBackground)
        addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            {
                let c = contentStack.leadingAnchor.constraint(equalTo: leadingAnchor)
                stackLeadingConstraint = c
                return c
            }(),
            {
                let c = contentStack.trailingAnchor.constraint(equalTo: trailingAnchor)
                stackTrailingConstraint = c
                return c
            }(),
            pillBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            pillBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            pillBackground.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            pillBackground.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])
    }
}

enum JiraAssets {
    static func resourceURL(name: String, ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        let bundleResources = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/\(name).\(ext)")
        if FileManager.default.fileExists(atPath: bundleResources.path) {
            return bundleResources
        }
        return nil
    }

    private static var backingScale: CGFloat {
        NSScreen.main?.backingScaleFactor ?? 2.0
    }

    static func applyMenuBarIcon(
        to button: NSStatusBarButton,
        badgeCount: Int,
        severityCount: Int,
        badgePulse: CGFloat = 1
    ) {
        guard let image = menuBarIcon(badgeCount: badgeCount, severityCount: severityCount, badgePulse: badgePulse) else { return }
        image.isTemplate = false
        button.image = image
        button.title = ""
    }

    static func menuBarLogoImage(pointSize: CGFloat = 18) -> NSImage? {
        loadIcon(baseName: "jntc-logo", pointSize: pointSize)
    }

    static func menuBarIcon(badgeCount: Int = 0, severityCount: Int = 0, badgePulse: CGFloat = 1) -> NSImage? {
        menuBarLogoImage(pointSize: MenuBarStatusItemView.iconSize)
    }

    static func watchersEyeImage(pointSize: CGFloat = 16) -> NSImage? {
        guard let image = loadIcon(baseName: "watchers-eye", pointSize: pointSize) else { return nil }
        image.isTemplate = true
        return image
    }

    static func panelIcon() -> NSImage? {
        if backingScale >= 2, let image = loadIcon(baseName: "jntc-logo-panel", pointSize: 24) {
            return image
        }
        return loadIcon(baseName: "jntc-logo", pointSize: 24)
    }

    private static func loadIcon(baseName: String, pointSize: CGFloat) -> NSImage? {
        let names = backingScale >= 2
            ? ["\(baseName)@2x", baseName]
            : [baseName, "\(baseName)@2x"]

        for name in names {
            guard let url = resourceURL(name: name, ext: "png"),
                  let data = try? Data(contentsOf: url),
                  let rep = NSBitmapImageRep(data: data) else {
                continue
            }
            rep.size = NSSize(width: pointSize, height: pointSize)
            let image = NSImage(size: NSSize(width: pointSize, height: pointSize))
            image.addRepresentation(rep)
            image.isTemplate = false
            return image
        }
        return NSImage(systemSymbolName: "ticket", accessibilityDescription: "Jira")
    }
}

#if DEBUG
extension MenuPanelView {
    /// Re-run AppKit layout when SwiftUI Canvas refreshes after spacing tweaks.
    func refreshPreviewLayout() {
        needsLayout = true
        layoutSubtreeIfNeeded()
    }
}

@available(macOS 10.15, *)
private enum MenuPanelPreviewSupport {
    static func mockState(soundExpanded: Bool = false) -> MenuPanelState {
        MenuPanelState(
            filterID: "12345",
            filterName: "Support Filter",
            filterJiraName: "Support Filter",
            filterIsRenamed: false,
            issueCount: 1,
            newCount: 0,
            badgeCount: 0,
            lastCheck: "16:20",
            connection: "Running",
            connectionOK: true,
            statusLine: "Up to date · 1 issues",
            filterURL: nil,
            savedFilters: [
                SavedFilter(id: "12345", name: "Support Filter", jiraName: "Support Filter", isRenamed: false, isActive: true),
            ],
            doNotDisturbActive: false,
            doNotDisturbSummary: "Alerts on",
            notificationVolume: 0.42,
            notificationSoundID: NotificationSound.tink.rawValue,
            soundExpanded: soundExpanded
        )
    }

        static func panel(soundExpanded: Bool = false) -> MenuPanelView {
        let view = MenuPanelView(frame: NSRect(
            x: 0, y: 0,
            width: MenuPanelView.panelWidth,
            height: MenuPanelView.panelHeight(soundExpanded: soundExpanded)
        ))
        view.update(state: mockState(soundExpanded: soundExpanded))
        return view
    }
}

@available(macOS 10.15, *)
struct MenuPanelView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NSViewPreview { MenuPanelPreviewSupport.panel(soundExpanded: false) }
                .previewDisplayName("Collapsed")
            NSViewPreview { MenuPanelPreviewSupport.panel(soundExpanded: true) }
                .previewDisplayName("Sound expanded")
        }
        .padding()
        .frame(width: 420, height: 640)
        .previewLayout(.sizeThatFits)
    }
}

@available(macOS 10.15, *)
struct NSViewPreview<View: NSView>: NSViewRepresentable {
    let viewBuilder: () -> View

    init(_ viewBuilder: @escaping () -> View) {
        self.viewBuilder = viewBuilder
    }

    func makeNSView(context: Context) -> View {
        let view = viewBuilder()
        (view as? MenuPanelView)?.refreshPreviewLayout()
        return view
    }

    func updateNSView(_ nsView: View, context: Context) {
        (nsView as? MenuPanelView)?.refreshPreviewLayout()
    }
}
#endif
