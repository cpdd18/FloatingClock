
import SwiftUI
import UIKit
import AVKit
import Combine
import Foundation

// MARK: - PiP 控制器

@MainActor
final class PiPClockController: NSObject,
    ObservableObject,
    AVPictureInPictureControllerDelegate {

    @Published private(set) var isPictureInPictureActive = false
    @Published private(set) var statusText = "正在准备画中画"

    @Published private(set) var isRequested = false
    @Published private(set) var isStopping = false
    private var startTimeout: Task<Void, Never>?

    private weak var sourceView: PiPClockAnchorView?

    private var pipController: AVPictureInPictureController?
    private var pipContentViewController: ClockPiPContentViewController?

    private var possibleObservation: NSKeyValueObservation?

    private var dayMode = false
    private var pendingStart = false

    // MARK: - 提前初始化

    func prepare() {

        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            statusText = "当前设备不支持画中画"
            return
        }

        guard let sourceView,
              sourceView.window != nil else {
            return
        }

        // 只创建一次
        guard pipController == nil else {
            return
        }

        let contentVC = ClockPiPContentViewController()

        contentVC.preferredContentSize = CGSize(width: 580, height: 176)

        contentVC.setDayMode(dayMode)

        // 提前初始化界面，不启动定时器
        contentVC.loadViewIfNeeded()

        let source = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: sourceView,
            contentViewController: contentVC
        )

        let controller = AVPictureInPictureController(
            contentSource: source
        )

        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = false

        pipContentViewController = contentVC
        pipController = controller

        statusText = "画中画已准备好"

        if pendingStart {
            observeAvailability(of: controller)
        }
    }

    // MARK: - 启动

    func startPictureInPicture() {

        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            statusText = "当前设备不支持画中画"
            return
        }

        if isStopping || isRequested || pipController?.isPictureInPictureActive == true {
            return
        }

        isRequested = true
        pendingStart = true
        startTimeout?.cancel()
        startTimeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(10)) }
            catch { return }
            guard let self, self.isRequested, !self.isPictureInPictureActive else { return }
            self.stopPictureInPicture()
            self.statusText = "画中画暂不可用，请检查系统画中画设置后重试"
        }

        prepare()

        guard let controller = pipController else {
            statusText = "正在准备画中画"
            return
        }

        observeAvailability(of: controller)
    }

    // MARK: - 监听系统可用状态

    private func observeAvailability(
        of controller: AVPictureInPictureController
    ) {

        guard pendingStart else {
            return
        }

        // 避免重复监听
        guard possibleObservation == nil else {
            return
        }

        if controller.isPictureInPicturePossible {
            startWhenPossible()
            return
        }

        statusText = "正在等待画中画可用"

        possibleObservation = controller.observe(
            \.isPictureInPicturePossible,
            options: [.initial, .new]
        ) { [weak self] _, change in

            guard change.newValue == true else {
                return
            }

            Task { @MainActor [weak self] in
                self?.startWhenPossible()
            }
        }
    }

    // MARK: - 真正启动

    private func startWhenPossible() {

        guard pendingStart,
              let controller = pipController,
              controller.isPictureInPicturePossible else {
            return
        }

        pendingStart = false

        possibleObservation?.invalidate()
        possibleObservation = nil

        statusText = "正在启动画中画"

        controller.startPictureInPicture()
    }

    // MARK: - 关闭

    func stopPictureInPicture() {

        isRequested = false
        startTimeout?.cancel()
        startTimeout = nil
        pendingStart = false

        possibleObservation?.invalidate()
        possibleObservation = nil

        // 立即停止时钟定时器
        pipContentViewController?.setClockActive(false)

        guard let controller = pipController else {
            statusText = "画中画已关闭"
            return
        }

        if controller.isPictureInPictureActive {
            isStopping = true
            statusText = "正在关闭画中画"
            controller.stopPictureInPicture()
        } else {
            statusText = "画中画已关闭"
        }
    }

    // MARK: - 设置

    func setDayMode(_ enabled: Bool) {

        guard dayMode != enabled else {
            return
        }

        dayMode = enabled

        pipContentViewController?.setDayMode(enabled)
    }

    // MARK: - 锚点视图

    func attachSourceView(_ view: PiPClockAnchorView) {

        sourceView = view

        guard view.window != nil else {
            return
        }

        prepare()

        if pendingStart, let controller = pipController {
            observeAvailability(of: controller)
        }
    }

    // MARK: - PiP 生命周期

    func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {

        startTimeout?.cancel()
        startTimeout = nil
        guard isRequested else {
            isStopping = true
            pictureInPictureController.stopPictureInPicture()
            return
        }
        pendingStart = false
        possibleObservation?.invalidate()
        possibleObservation = nil

        pipContentViewController?.setClockActive(true)

        isPictureInPictureActive = true
        statusText = "画中画运行中"
    }

    func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {

        pipContentViewController?.setClockActive(false)

        isPictureInPictureActive = false
        isStopping = false
        isRequested = false
        startTimeout?.cancel()
        startTimeout = nil
        pendingStart = false

        statusText = "画中画已关闭"
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {

        pendingStart = false

        possibleObservation?.invalidate()
        possibleObservation = nil

        pipContentViewController?.setClockActive(false)

        isPictureInPictureActive = false
        isStopping = false

        isRequested = false
        startTimeout?.cancel()
        startTimeout = nil
        statusText = "启动失败：\(error.localizedDescription)"
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {

        completionHandler(true)
    }
}

// MARK: - PiP 锚点视图

@MainActor
final class PiPClockAnchorView: UIView {

    var onWindowAttached: ((PiPClockAnchorView) -> Void)?

    override func didMoveToWindow() {

        super.didMoveToWindow()

        if window != nil {
            onWindowAttached?(self)
        }
    }
}

// MARK: - SwiftUI 接入

struct PiPClockSourceHost: UIViewRepresentable {

    let controller: PiPClockController
    func makeUIView(context: Context) -> PiPClockAnchorView {
        let view = PiPClockAnchorView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        // Only attach when the source enters a window, not on every SwiftUI update.
        view.onWindowAttached = { [weak controller] attachedView in
            Task { @MainActor [weak attachedView] in
                await Task.yield()
                guard let attachedView else { return }
                controller?.attachSourceView(attachedView)
            }
        }
        return view
    }

    func updateUIView(_ uiView: PiPClockAnchorView, context: Context) {}
}

// MARK: - PiP 内容控制器

@MainActor
final class ClockPiPContentViewController:
    AVPictureInPictureVideoCallViewController {

    private let clockFace = PiPClockFaceView()
    private var clockIsActive = false

    override func viewDidLoad() {

        super.viewDidLoad()

        view.backgroundColor = .clear
        view.isOpaque = false

        clockFace.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(clockFace)

        NSLayoutConstraint.activate([
            clockFace.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            clockFace.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            clockFace.topAnchor.constraint(equalTo: view.topAnchor),
            clockFace.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        clockFace.setClockActive(clockIsActive)
    }

    func setClockActive(_ active: Bool) {

        clockIsActive = active

        if isViewLoaded {
            clockFace.setClockActive(active)
        }
    }

    func setDayMode(_ enabled: Bool) {
        clockFace.setDayMode(enabled)
    }
}

// MARK: - PiP 时钟界面

@MainActor
final class PiPClockFaceView: UIView {

    private let timeLabel = UILabel()
    private let timeFormatter = ClockTimeFormatter()

    private var refreshTimer: Timer?

    private let fixedFontSize: CGFloat = 72

    private var dayMode = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
        refreshClock()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
        refreshClock()
    }

    deinit {
        refreshTimer?.invalidate()
    }

    // MARK: - 初始化

    private func setupView() {

        clipsToBounds = true
        layer.cornerRadius = 18

        timeLabel.font = .monospacedDigitSystemFont(
            ofSize: fixedFontSize,
            weight: .semibold
        )

        timeLabel.textAlignment = .center
        timeLabel.adjustsFontSizeToFitWidth = true
        timeLabel.minimumScaleFactor = 0.2
        timeLabel.numberOfLines = 1

        timeLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(timeLabel)

        NSLayoutConstraint.activate([
            timeLabel.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: 18
            ),
            timeLabel.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -18
            ),
            timeLabel.centerYAnchor.constraint(
                equalTo: centerYAnchor
            )
        ])

        updateAppearance()
    }

    // MARK: - 定时器

    func setClockActive(_ active: Bool) {

        if active {

            guard refreshTimer == nil else {
                refreshClock()
                return
            }

            refreshClock()
            startClockTimer()

        } else {

            stopClockTimer()
            refreshClock()
        }
    }

    private func startClockTimer() {

        guard refreshTimer == nil else {
            return
        }

        let interval: TimeInterval = 0.1
        let units = 10.0

        let now = Date().timeIntervalSince1970
        let nextTick = (floor(now * units) + 1.0) / units

        let timer = Timer(
            fire: Date(timeIntervalSince1970: nextTick),
            interval: interval,
            repeats: true
        ) { [weak self] _ in

            MainActor.assumeIsolated {
                self?.refreshClock()
            }
        }

        timer.tolerance = interval * 0.1

        refreshTimer = timer

        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopClockTimer() {

        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - 时间显示

    private func refreshClock() {

        let text = timeFormatter.string(from: Date())
        if timeLabel.text != text {
            timeLabel.text = text
        }
    }

    // MARK: - 日间 / 夜间外观

    func setDayMode(_ enabled: Bool) {

        guard dayMode != enabled else {
            return
        }

        dayMode = enabled
        updateAppearance()
    }

    private func updateAppearance() {

        // 固定实色背景，不再提供透明模式
        backgroundColor = dayMode
            ? UIColor(white: 0.96, alpha: 1)
            : UIColor.black

        isOpaque = true

        timeLabel.textColor = dayMode
            ? UIColor.black
            : UIColor.white
    }
}
