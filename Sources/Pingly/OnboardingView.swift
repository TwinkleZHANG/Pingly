import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore
    @State private var step = 0

    private let steps = [
        OnboardingStep(
            image: "sparkles",
            title: "欢迎使用 Pingly",
            message: "让你喜欢的角色在屏幕上出现，用轻松的方式提醒重要事情。"
        ),
        OnboardingStep(
            image: "photo.on.rectangle.angled",
            title: "准备提醒角色",
            message: "选择动作后，Pingly 会列出所需的透明 PNG，并提供可以复制的中文 AI 提示词。"
        ),
        OnboardingStep(
            image: "bell.badge",
            title: "创建第一条提醒",
            message: "可以按固定间隔提醒，也可以设置具体日期、时间和重复规则。"
        ),
        OnboardingStep(
            image: "play.rectangle",
            title: "先预览，再开始",
            message: "保存前播放一次真实效果，确认角色大小、路线、动作和文字位置。"
        )
    ]

    var body: some View {
        VStack(spacing: 26) {
            Spacer()
            Image(systemName: steps[step].image)
                .font(.system(size: 52, weight: .regular))
                .foregroundStyle(.tint)
            VStack(spacing: 10) {
                Text(steps[step].title)
                    .font(.title)
                    .fontWeight(.semibold)
                Text(steps[step].message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            Spacer()
            HStack {
                if step > 0 {
                    Button("上一步") { step -= 1 }
                } else {
                    Button("跳过") { store.completeOnboarding() }
                }
                Spacer()
                Text("\(step + 1) / \(steps.count)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button(step == steps.count - 1 ? "开始使用" : "继续") {
                    if step == steps.count - 1 {
                        store.completeOnboarding()
                    } else {
                        step += 1
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PinglyTheme.window)
    }
}

private struct OnboardingStep {
    let image: String
    let title: String
    let message: String
}
