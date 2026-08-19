import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        if store.isPaused {
            Button("继续提醒") { store.resume() }
        } else {
            Menu("快速暂停") {
                Button("30 分钟") { store.pause(for: 30 * 60) }
                Button("1 小时") { store.pause(for: 60 * 60) }
                Button("今天剩余时间") { store.pauseForRestOfToday() }
                Divider()
                Button("自定义…") {}
            }
        }

        if let nextReminder = store.nextReminder {
            Text("下一条：\(nextReminder.title)")
        } else {
            Text("暂无即将到来的提醒")
        }

        Divider()
        Button("打开主窗口") {
            PinglyWindowCoordinator.shared.showMainWindow()
        }
        Divider()
        Button("退出 Pingly") { NSApp.terminate(nil) }
    }
}
