import AppKit
import SwiftUI

struct CharacterImportMethodView: View {
    let onChoosePosePNGs: () -> Void
    let onChooseHatchPet: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("添加角色")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("两种格式可以在同一个角色库中混合使用。")
                        .foregroundStyle(PinglyTheme.secondaryText)
                }
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(PinglyTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Rectangle().fill(PinglyTheme.border).frame(height: 1)

            VStack(spacing: 14) {
                methodCard(
                    title: "导入 hatch-pet 动画包",
                    detail: "读取 pet.json 和 spritesheet.webp，使用完整的移动与原地动画。",
                    icon: "square.grid.3x3.fill",
                    badge: "推荐",
                    action: onChooseHatchPet
                )
                methodCard(
                    title: "导入独立 PNG 姿势",
                    detail: "保留原有流程，为移动和其他动作逐张上传透明 PNG。",
                    icon: "photo.on.rectangle.angled",
                    badge: nil,
                    action: onChoosePosePNGs
                )
            }
            .padding(24)
            Spacer()
        }
        .background(PinglyTheme.window)
    }

    private func methodCard(
        title: String,
        detail: String,
        icon: String,
        badge: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(PinglyTheme.green)
                    .frame(width: 52, height: 52)
                    .background(PinglyTheme.greenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(title).font(.headline)
                        if let badge {
                            Text(badge)
                                .font(.caption2)
                                .foregroundStyle(PinglyTheme.green)
                        }
                    }
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(PinglyTheme.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(PinglyTheme.secondaryText)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(PinglyTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(PinglyTheme.border))
            )
            .contentShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
    }
}

struct HatchPetImportView: View {
    @EnvironmentObject private var store: AppStore

    let onCancel: () -> Void
    let onComplete: () -> Void
    private let editingID: UUID?

    @State private var name: String
    @State private var includedInRandomPool: Bool
    @State private var selectedPackageURL: URL?
    @State private var previewImage: NSImage?
    @State private var packageLabel: String?
    @State private var inlineMessage: String?
    @State private var isConfirmingDelete = false

    init(character: CharacterProfile? = nil, onCancel: @escaping () -> Void, onComplete: @escaping () -> Void) {
        self.onCancel = onCancel
        self.onComplete = onComplete
        editingID = character?.id
        _name = State(initialValue: character?.name ?? "")
        _includedInRandomPool = State(initialValue: character?.isIncludedInRandomPool ?? true)
        _previewImage = State(initialValue: character.flatMap(CharacterAnimationLoader.previewImage))
        _packageLabel = State(initialValue: character == nil ? nil : "已导入 hatch-pet 动画包")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(PinglyTheme.border).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("导入 hatch-pet 动画包")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("选择同时包含 pet.json 和 spritesheet.webp 的文件夹。")
                            .foregroundStyle(PinglyTheme.secondaryText)
                    }

                    Button(action: choosePackage) {
                        HStack(spacing: 16) {
                            Group {
                                if let previewImage {
                                    Image(nsImage: previewImage)
                                        .resizable()
                                        .scaledToFit()
                                } else {
                                    Image(systemName: "folder.badge.plus")
                                        .font(.system(size: 30))
                                        .foregroundStyle(PinglyTheme.green)
                                }
                            }
                            .frame(width: 88, height: 88)
                            .background(PinglyTheme.greenSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 14))

                            VStack(alignment: .leading, spacing: 6) {
                                Text(packageLabel ?? "选择 hatch-pet 文件夹")
                                    .fontWeight(.semibold)
                                Text(editingID == nil ? "导入后 Pingly 会保留本地副本。" : "可选择新文件夹替换当前动画包。")
                                    .font(.caption)
                                    .foregroundStyle(PinglyTheme.secondaryText)
                            }
                            Spacer()
                            Text(selectedPackageURL == nil ? "选择" : "更换")
                                .foregroundStyle(PinglyTheme.green)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 15)
                                .fill(PinglyTheme.surface)
                                .overlay(RoundedRectangle(cornerRadius: 15).stroke(PinglyTheme.border))
                        )
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("角色名称").fontWeight(.semibold)
                        TextField("例如：芝麻", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    Toggle("随机选择角色时包含这个角色", isOn: $includedInRandomPool)
                        .toggleStyle(.switch)
                        .tint(PinglyTheme.green)
                        .settingBox()

                    Label(
                        "移动方向严格绑定 hatch-pet：从左向右只播放 running-right，从右向左只播放 running-left；其余状态只在角色原地停留时播放。",
                        systemImage: "sparkles"
                    )
                    .font(.callout)
                    .foregroundStyle(PinglyTheme.primaryText)
                    .padding(13)
                    .background(PinglyTheme.greenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    if let inlineMessage {
                        Label(inlineMessage, systemImage: "exclamationmark.circle")
                            .font(.callout)
                            .foregroundStyle(PinglyTheme.apricot)
                    }
                }
                .padding(24)
            }

            Rectangle().fill(PinglyTheme.border).frame(height: 1)
            footer
        }
        .background(PinglyTheme.window)
        .onChange(of: name) { value in
            if value.count > 12 { name = String(value.prefix(12)) }
        }
    }

    private var header: some View {
        HStack {
            Text(editingID == nil ? "导入动画角色" : "编辑动画角色")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(PinglyTheme.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            Button("取消", action: onCancel)
                .keyboardShortcut(.cancelAction)

            if let editingID {
                Button(isConfirmingDelete ? "再次点击确认删除" : "删除角色") {
                    if isConfirmingDelete {
                        store.deleteCharacter(id: editingID)
                        onComplete()
                    } else {
                        isConfirmingDelete = true
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.red)
            }

            Spacer()
            Button(editingID == nil ? "导入角色" : "保存修改", action: save)
                .buttonStyle(.borderedProminent)
                .tint(PinglyTheme.green)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (editingID == nil && selectedPackageURL == nil))
        }
        .padding(18)
    }

    private func choosePackage() {
        let panel = NSOpenPanel()
        panel.title = "选择 hatch-pet 动画包"
        panel.prompt = "选择"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                selectedPackageURL = url
                loadPackagePreview(from: url)
            }
        }
    }

    private func loadPackagePreview(from packageURL: URL) {
        inlineMessage = nil
        let manifestURL = packageURL.appendingPathComponent("pet.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let displayName = object["displayName"] as? String,
              let spritesheetPath = object["spritesheetPath"] as? String else {
            previewImage = nil
            packageLabel = packageURL.lastPathComponent
            inlineMessage = "这个文件夹中没有可用的 pet.json。"
            return
        }

        let spritesheetURL = packageURL.appendingPathComponent(spritesheetPath)
        previewImage = HatchPetAtlas.previewImage(at: spritesheetURL.path)
        packageLabel = packageURL.lastPathComponent
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = String(displayName.prefix(12))
        }
        if previewImage == nil {
            inlineMessage = "图集无法读取，或不是 1536×1872 的 hatch-pet 最终格式。"
        }
    }

    private func save() {
        do {
            let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let editingID {
                try store.updateHatchPetCharacter(
                    id: editingID,
                    name: cleanName,
                    replacementPackageURL: selectedPackageURL,
                    includedInRandomPool: includedInRandomPool
                )
            } else if let selectedPackageURL {
                try store.addHatchPetCharacter(
                    packageURL: selectedPackageURL,
                    nameOverride: cleanName,
                    includedInRandomPool: includedInRandomPool
                )
            }
            onComplete()
        } catch {
            inlineMessage = "导入失败：\(error.localizedDescription)"
        }
    }
}
