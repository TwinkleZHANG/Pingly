import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CharacterImportView: View {
    @EnvironmentObject private var store: AppStore

    let onCancel: () -> Void
    let onComplete: () -> Void
    private let editingID: UUID?

    @State private var step = 0
    @State private var name = ""
    @State private var selectedActions: Set<CharacterAction> = [.movement]
    @State private var imageData: [String: Data] = [:]
    @State private var includedInRandomPool = true
    @State private var inlineMessage: String?
    @State private var isConfirmingDelete = false

    private let stepTitles = ["角色与动作", "导入姿势图", "确认"]

    init(character: CharacterProfile? = nil, onCancel: @escaping () -> Void, onComplete: @escaping () -> Void) {
        self.onCancel = onCancel
        self.onComplete = onComplete
        editingID = character?.id
        _name = State(initialValue: character?.name ?? "")
        _selectedActions = State(initialValue: Set(character?.enabledActions ?? [.movement]).union([.movement]))
        _includedInRandomPool = State(initialValue: character?.isIncludedInRandomPool ?? true)

        var loadedImages: [String: Data] = [:]
        for (poseID, path) in character?.assetPaths ?? [:] {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                loadedImages[poseID] = data
            }
        }
        _imageData = State(initialValue: loadedImages)
    }

    private var requiredPoses: [(action: CharacterAction, pose: CharacterPoseRequirement)] {
        CharacterAction.allCases
            .filter(selectedActions.contains)
            .flatMap { action in action.poses.map { (action, $0) } }
    }

    private var hasAllImages: Bool {
        requiredPoses.allSatisfy { imageData[$0.pose.id] != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(PinglyTheme.border).frame(height: 1)

            ScrollView {
                Group {
                    switch step {
                    case 0: actionStep
                    case 1: uploadStep
                    default: reviewStep
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }

            Rectangle().fill(PinglyTheme.border).frame(height: 1)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PinglyTheme.window)
        .onChange(of: name) { value in
            if value.count > 12 { name = String(value.prefix(12)) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(editingID == nil ? "导入角色" : "编辑角色")
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

            HStack(spacing: 8) {
                ForEach(stepTitles.indices, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? PinglyTheme.green : PinglyTheme.border)
                        .frame(height: 4)
                }
            }

            Text("第 \(step + 1) 步，共 3 步 · \(stepTitles[step])")
                .font(.caption)
                .foregroundStyle(PinglyTheme.secondaryText)
        }
        .padding(20)
    }

    private var actionStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle("这是谁？", detail: "角色可以是宠物、原创形象或你有权使用的动漫角色。")

            VStack(alignment: .leading, spacing: 6) {
                TextField("角色名称，例如：芝麻", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                HStack {
                    Text("名称只用于角色库，不会显示在提醒文字里。")
                    Spacer()
                    Text("\(name.count)/12")
                }
                .font(.caption)
                .foregroundStyle(PinglyTheme.secondaryText)
            }

            sectionTitle("需要哪些动作？", detail: "移动是必需动作；其他动作只有选中后才需要上传图片。")

            Toggle(
                "全选所有动作",
                isOn: Binding(
                    get: { selectedActions.count == CharacterAction.allCases.count },
                    set: { shouldSelectAll in
                        if shouldSelectAll {
                            selectedActions = Set(CharacterAction.allCases)
                        } else {
                            selectedActions = [.movement]
                            let movementPoseIDs = Set(CharacterAction.movement.poses.map(\.id))
                            imageData = imageData.filter { movementPoseIDs.contains($0.key) }
                        }
                    }
                )
            )
            .toggleStyle(.switch)
            .tint(PinglyTheme.green)
            .settingBox()

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
                ForEach(CharacterAction.allCases) { action in
                    actionCard(action)
                }
            }
        }
    }

    private var uploadStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                sectionTitle(
                    "拖入每个姿势的 PNG",
                    detail: "透明背景，推荐 1024×1024；所有图片保持相同画布、比例、卡通画风和光线。"
                )
                Spacer()
                Button("复制 AI 生成说明") { copyPrompt() }
                    .buttonStyle(.bordered)
                    .tint(PinglyTheme.green)
            }

            if let inlineMessage {
                Label(inlineMessage, systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(PinglyTheme.green)
            }

            Label(
                "如果需要 AI 生成，请先向 AI 上传同一角色清晰的正面和侧面参考照片，再使用我们的生成说明。参考照片只提供给你选择的 AI 工具，不需要导入 Pingly。",
                systemImage: "person.crop.rectangle.stack"
            )
            .font(.callout)
            .foregroundStyle(PinglyTheme.primaryText)
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(PinglyTheme.greenSoft)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(PinglyTheme.green.opacity(0.35)))
            )

            ForEach(CharacterAction.allCases.filter(selectedActions.contains)) { action in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(action.title).fontWeight(.semibold)
                        Text("\(action.poses.count) 张")
                            .font(.caption)
                            .foregroundStyle(PinglyTheme.secondaryText)
                        Spacer()
                    }
                    Text(action.detail)
                        .font(.caption)
                        .foregroundStyle(PinglyTheme.secondaryText)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                        ForEach(action.poses) { pose in
                            poseDropZone(pose)
                        }
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(PinglyTheme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(PinglyTheme.border))
                )
            }
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle("角色已经准备好了", detail: "保存后，Pingly 会在本机保留统一尺寸的工作副本。")

            HStack(spacing: 18) {
                if let first = requiredPoses.first,
                   let data = imageData[first.pose.id],
                   let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .background(PinglyTheme.greenSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(name).font(.title2).fontWeight(.semibold)
                    Text("\(selectedActions.count) 个动作 · \(requiredPoses.count) 张姿势图")
                        .foregroundStyle(PinglyTheme.secondaryText)
                    Text(selectedActions.map(\.title).joined(separator: "、"))
                        .font(.callout)
                        .foregroundStyle(PinglyTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Toggle("随机选择角色时包含这个角色", isOn: $includedInRandomPool)
                .toggleStyle(.switch)
                .tint(PinglyTheme.green)
                .settingBox()

            if let inlineMessage {
                Label(inlineMessage, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(PinglyTheme.apricot)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(step == 0 ? "取消" : "上一步") {
                if step == 0 { onCancel() } else { step -= 1 }
            }
            .keyboardShortcut(.cancelAction)

            if editingID != nil && step == 0 {
                Button(isConfirmingDelete ? "再次点击确认删除" : "删除角色") {
                    if isConfirmingDelete {
                        if let editingID { store.deleteCharacter(id: editingID) }
                        onComplete()
                    } else {
                        isConfirmingDelete = true
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.red)
            }

            Spacer()
            Text(step == 1 ? "已导入 \(imageData.count)/\(requiredPoses.count)" : "")
                .font(.caption)
                .foregroundStyle(PinglyTheme.secondaryText)
            Spacer()

            if step < 2 {
                Button("继续") { step += 1; inlineMessage = nil }
                    .buttonStyle(.borderedProminent)
                    .tint(PinglyTheme.green)
                    .disabled(step == 0
                        ? name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        : !hasAllImages)
            } else {
                Button(editingID == nil ? "保存角色" : "保存修改") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(PinglyTheme.green)
            }
        }
        .padding(18)
    }

    private func actionCard(_ action: CharacterAction) -> some View {
        let isRequired = action == .movement
        let isSelected = selectedActions.contains(action)

        return Button {
            guard !isRequired else { return }
            if isSelected {
                selectedActions.remove(action)
                for pose in action.poses { imageData.removeValue(forKey: pose.id) }
            } else {
                selectedActions.insert(action)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? PinglyTheme.green : PinglyTheme.secondaryText)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(action.title).fontWeight(.semibold)
                        if isRequired {
                            Text("必需").font(.caption2).foregroundStyle(PinglyTheme.green)
                        }
                    }
                    Text("需要 \(action.poses.count) 张")
                        .font(.caption)
                        .foregroundStyle(PinglyTheme.secondaryText)
                }
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(isSelected ? PinglyTheme.greenSoft : PinglyTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(isSelected ? PinglyTheme.green : PinglyTheme.border))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func poseDropZone(_ pose: CharacterPoseRequirement) -> some View {
        Button {
            choosePNG(for: pose.id)
        } label: {
            VStack(spacing: 8) {
                if let data = imageData[pose.id], let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 92)
                } else {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 28))
                        .foregroundStyle(PinglyTheme.green)
                        .frame(height: 92)
                }

                Text(pose.title).fontWeight(.semibold)
                Text(pose.instruction)
                    .font(.caption)
                    .foregroundStyle(PinglyTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(minHeight: 44)
                Text(imageData[pose.id] == nil ? "点击选择，或把 PNG 拖到这里" : "已导入 · 点击或拖入替换")
                    .font(.caption2)
                    .foregroundStyle(imageData[pose.id] == nil ? PinglyTheme.green : PinglyTheme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(PinglyTheme.window)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(PinglyTheme.green.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [5]))
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onDrop(of: [UTType.png.identifier, UTType.fileURL.identifier], isTargeted: nil) { providers in
            receivePNG(from: providers, poseID: pose.id)
        }
    }

    private func choosePNG(for poseID: String) {
        let panel = NSOpenPanel()
        panel.title = "选择透明背景 PNG"
        panel.prompt = "选择"
        panel.allowedContentTypes = [.png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        panel.begin { response in
            guard response == .OK,
                  let url = panel.url,
                  let data = try? Data(contentsOf: url),
                  NSImage(data: data) != nil else { return }
            Task { @MainActor in
                imageData[poseID] = data
                inlineMessage = nil
            }
        }
    }

    private func receivePNG(from providers: [NSItemProvider], poseID: String) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.hasItemConformingToTypeIdentifier(UTType.png.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.png.identifier) { data, _ in
                guard let data, NSImage(data: data) != nil else { return }
                Task { @MainActor in
                    imageData[poseID] = data
                    inlineMessage = nil
                }
            }
            return true
        }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
            guard let data,
                  let url = URL(dataRepresentation: data, relativeTo: nil),
                  url.pathExtension.lowercased() == "png",
                  let pngData = try? Data(contentsOf: url),
                  NSImage(data: pngData) != nil else { return }
            Task { @MainActor in
                imageData[poseID] = pngData
                inlineMessage = nil
            }
        }
        return true
    }

    private func copyPrompt() {
        let poseLines = requiredPoses.map { "- \($0.action.title) / \($0.pose.title)：\($0.pose.instruction)" }.joined(separator: "\n")
        let prompt = """
        请根据我上传的同一角色正面和侧面参考照片，为角色“\(name)”生成一组二维卡通风格的动作关键姿势图。整体风格要可爱、柔和、轮廓清晰，保留原角色可辨认的毛色、花纹、五官、体型和其他特征；不要生成写实照片、3D 渲染或像素画。

        每张必须是独立的透明背景 PNG，推荐 1024×1024 正方形画布。所有图片保持角色造型、比例、颜色、描边粗细、卡通画风、视角基准、光线和画布位置一致。完整保留角色全身和尾巴，不要裁切，不要添加文字、边框、地面、场景或投影，不要用拉伸或压缩改变外形。移动动作使用面向移动方向的侧面图；固定动作可使用正面、侧面或四分之三视角，但同一个动作内部视角必须一致。

        需要生成：
        \(poseLines)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        inlineMessage = "AI 生成说明已复制，可以粘贴到你使用的 AI 工具中。"
    }

    private func save() {
        do {
            let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let actions = CharacterAction.allCases.filter(selectedActions.contains)
            if let editingID {
                try store.updateCharacter(
                    id: editingID,
                    name: cleanName,
                    actions: actions,
                    sourceData: imageData,
                    includedInRandomPool: includedInRandomPool
                )
            } else {
                try store.addCharacter(
                    name: cleanName,
                    actions: actions,
                    sourceData: imageData,
                    includedInRandomPool: includedInRandomPool
                )
            }
            onComplete()
        } catch {
            inlineMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    private func sectionTitle(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title2).fontWeight(.semibold)
            Text(detail).foregroundStyle(PinglyTheme.secondaryText)
        }
    }
}
