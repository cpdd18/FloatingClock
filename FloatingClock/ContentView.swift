
import SwiftUI

struct ContentView: View {

    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var pipClock = PiPClockController()

    @Environment(\.scenePhase) private var scenePhase
    private var isDayMode: Bool {
        colorScheme == .light
    }

    private var primaryText: Color {
        isDayMode ? Color.black.opacity(0.88) : .white
    }

    private var secondaryText: Color {
        isDayMode
            ? Color.black.opacity(0.48)
            : Color.white.opacity(0.55)
    }

    // MARK: - 主界面

    var body: some View {

        ZStack {

            backgroundView

            ScrollView(showsIndicators: false) {

                VStack(spacing: 19) {

                    header
                    clockCard
                    floatingControlCard
                    footer

                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 35)
            }
        }

        // 提前初始化画中画
        .background(
            PiPClockSourceHost(
                controller: pipClock
            )
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
        )

        // 自动跟随系统浅色 / 深色模式
        .onChange(of: colorScheme) { _, newScheme in
            pipClock.setDayMode(newScheme == .light)
        }

        // 提前预热 PiP
        .task {

            pipClock.setDayMode(
                colorScheme == .light
            )

            pipClock.prepare()
        }
    }

    // MARK: - 背景

    private var backgroundView: some View {

        LinearGradient(
            colors: isDayMode
                ? [
                    Color(red: 0.94, green: 0.96, blue: 0.99),
                    Color(red: 0.84, green: 0.89, blue: 0.97)
                ]
                : [
                    Color(red: 0.045, green: 0.055, blue: 0.09),
                    Color(red: 0.10, green: 0.12, blue: 0.19),
                    Color(red: 0.035, green: 0.04, blue: 0.07)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: - 顶部标题

    private var header: some View {

        VStack(alignment: .leading, spacing: 7) {

            Text("悬浮时钟")
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(primaryText)

            Text("系统时间 · 画中画")
                .font(.system(size: 12))
                .foregroundStyle(secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
    // MARK: - 时间预览

    private var clockCard: some View {

        glassCard {

            VStack(spacing: 15) {

                HStack {

                    Label(
                        "当前系统时间",
                        systemImage: "clock"
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(secondaryText)

                    Spacer()

                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)

                    Text("实时刷新")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                }

                ClockDisplay(
                    isDayMode: isDayMode,
                    isActive: scenePhase == .active
                )
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - 悬浮时钟

    private var floatingControlCard: some View {

        glassCard {

            VStack(spacing: 15) {

                HStack(spacing: 14) {

                    Image(systemName: "pip")
                        .font(.system(size: 26))
                        .foregroundStyle(.blue)
                        .frame(width: 44)

                    VStack(alignment: .leading, spacing: 5) {

                        Text("悬浮时钟")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(primaryText)

                        Text("在其他应用上方显示时间")
                            .font(.system(size: 11))
                            .foregroundStyle(secondaryText)
                    }

                    Spacer()

                    Toggle("悬浮时钟", isOn: Binding(
                        get: { pipClock.isRequested },
                        set: { enabled in
                            if enabled { pipClock.startPictureInPicture() }
                            else { pipClock.stopPictureInPicture() }
                        }
                    ))
                        .labelsHidden()
                        .disabled(pipClock.isStopping)
                        .tint(.blue)
                }

                Divider()
                    .overlay(secondaryText.opacity(0.15))

                HStack(spacing: 8) {

                    Circle()
                        .fill(
                            pipClock.isPictureInPictureActive
                                ? Color.green
                                : Color.orange
                        )
                        .frame(width: 7, height: 7)

                    Text(pipClock.statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(secondaryText)
                        .lineLimit(2)

                    Spacer()
                }
            }
        }
    }

    // MARK: - 页面底部文字

    private var footer: some View {

        Text("欲买桂花同载酒，终不似少年游")
            .font(.system(size: 13, weight: .regular))
            .tracking(2)
            .foregroundStyle(secondaryText.opacity(0.85))
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.top, 18)
            .padding(.bottom, 8)
    }

    // MARK: - 玻璃卡片

    private func glassCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {

        content()
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(
                        primaryText.opacity(0.08),
                        lineWidth: 1
                    )
            )
    }
}

// MARK: - 主界面时间

struct ClockDisplay: View {

    let isDayMode: Bool
    let isActive: Bool

    @State private var timeFormatter = ClockTimeFormatter()

    var body: some View {

        TimelineView(
            .animation(minimumInterval: 0.1, paused: !isActive)
        ) { context in

            Text(timeFormatter.string(from: context.date))
                .font(
                    .system(
                        size: 43,
                        weight: .semibold,
                        design: .rounded
                    )
                )
                .monospacedDigit()
                .minimumScaleFactor(0.65)
                .lineLimit(1)
                .foregroundStyle(
                    isDayMode ? Color.black : Color.white
                )
                .frame(maxWidth: .infinity)
        }
    }
}
