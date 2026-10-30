import PhotosUI
import SwiftData
import SwiftUI

struct RecommendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PracticeStore.self) private var store
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil })
    private var projects: [Project]

    @State private var name = ""
    @State private var duration = 20
    @State private var selectedProjectId: UUID?
    @State private var showProjectSelection = false
    @State private var showPhotoFlow = false
    @State private var isCameraPresented = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var imageData: [Data] = []
    @State private var isLoadingImage = false
    @State private var isSubmitting = false
    @State private var toast: String?
    @State private var entryGate = PracticeEntryGate()
    @State private var submitToken = PracticeEntryToken()
    @AppStorage(LLMSettingsKey.baseURL) private var llmBaseURL = ""
    @AppStorage(LLMSettingsKey.model) private var llmModel = ""
    private let credentials = LLMCredentialsStore()

    /// The presenter navigates after this sheet has dismissed.
    @Binding var selection: String?

    private var projectName: String {
        guard let selectedProjectId else { return "未选择项目" }
        return projects.first(where: { $0.id == selectedProjectId })?.name ?? "未选择项目"
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(GitaTheme.borderSubtle)
                .frame(width: 40, height: 4)
                .padding(.top, 10)

            HStack {
                Text("创建练习")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Button("关闭") { dismiss() }
                    .font(.system(size: 14))
                    .foregroundStyle(GitaTheme.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            ScrollView {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        TextField("练习名称", text: $name)
                            .font(.system(size: 16, weight: .semibold))
                            .accessibilityIdentifier("practice.create-name")
                        HStack(spacing: 2) {
                            Button { duration = max(5, duration - 5) } label: {
                                Image(systemName: "minus.circle")
                                    .frame(width: 30, height: 34)
                            }
                            Text("\(duration) 分钟")
                                .font(.system(size: 14, weight: .medium))
                                .fixedSize()
                            Button { duration = min(60, duration + 5) } label: {
                                Image(systemName: "plus.circle.fill")
                                    .frame(width: 30, height: 34)
                            }
                        }
                        .foregroundStyle(GitaTheme.brand500)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 60)
                    .background(GitaTheme.bgSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Button { showProjectSelection = true } label: {
                        HStack {
                            Text("归属项目")
                            Spacer()
                            Text(projectName)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(GitaTheme.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(height: 56)
                        .background(GitaTheme.bgSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("practice.select-project")

                    HStack(spacing: 10) {
                        sourceCard(title: "拍照", detail: "立即拍摄纸质内容", icon: "camera.fill", primary: true) {
                            guard checkAIConfiguration() else { return }
                            isCameraPresented = true
                        }

                        PhotosPicker(selection: $pickerItems, maxSelectionCount: 3, matching: .images) {
                            sourceCardContent(title: "从相册选择", detail: "选择截图或已有照片", icon: "photo.on.rectangle", primary: false)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("practice.album")
                        .disabled(isLoadingImage || showPhotoFlow)
                    }
                    .padding(.top, 8)

                    if let toast {
                        Text(toast)
                            .font(.system(size: 13))
                            .foregroundStyle(GitaTheme.brand500)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
            }

            Button(action: createManualPractice) {
                Text("确认并创建练习")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(GitaTheme.brandOn)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(GitaTheme.brand500)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting || isLoadingImage)
            .accessibilityIdentifier("practice.confirm-create")
            .padding(.horizontal, 20)
            .padding(.bottom, 22)
        }
        .background(GitaTheme.bgSurface)
        .sheet(isPresented: $showProjectSelection) {
            PracticeProjectSelectionView(selectedProjectId: $selectedProjectId)
        }
        .sheet(isPresented: $showPhotoFlow, onDismiss: { pickerItems = [] }) {
            PhotoPracticeSheet(
                imageData: imageData,
                requestedTitle: name,
                fallbackCategory: .chord,
                baseURL: llmBaseURL,
                model: llmModel,
                selectedProjectId: $selectedProjectId,
                selection: $selection,
                onReselect: { showPhotoFlow = false },
                onFinished: {
                    showPhotoFlow = false
                    dismiss()
                }
            )
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            StillImageCameraPicker(
                isPresented: $isCameraPresented,
                onPicked: { data in
                    imageData = [data]
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showPhotoFlow = true
                    }
                },
                onCancel: {}
            )
            .ignoresSafeArea()
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            loadPhotos(items)
        }
        .presentationDetents([.height(500)])
        .presentationDragIndicator(.hidden)
    }

    private func sourceCard(title: String, detail: String, icon: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            sourceCardContent(title: title, detail: detail, icon: icon, primary: primary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(primary ? "practice.camera" : "practice.source")
        .disabled(isLoadingImage || showPhotoFlow)
    }

    private func sourceCardContent(title: String, detail: String, icon: String, primary: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .medium))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(GitaTheme.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(primary ? GitaTheme.brand500 : GitaTheme.textPrimary)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 88)
        .background(primary ? GitaTheme.brand50 : GitaTheme.bgSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func checkAIConfiguration() -> Bool {
        let missing = credentials.missingFieldLabels(baseURL: llmBaseURL, model: llmModel)
        guard missing.isEmpty else {
            toast = "还缺 \(missing.joined(separator: "、"))，请在设置里填完并点保存"
            return false
        }
        return true
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        guard checkAIConfiguration() else { pickerItems = []; return }
        isLoadingImage = true
        Task {
            var loaded: [Data] = []
            for item in items.prefix(3) {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    loaded.append(data)
                }
            }
            isLoadingImage = false
            guard !loaded.isEmpty else {
                toast = "图片读取失败，请重新选择"
                pickerItems = []
                return
            }
            imageData = loaded
            showPhotoFlow = true
        }
    }

    private func createManualPractice() {
        guard !isSubmitting else { return }
        isSubmitting = true
        do {
            let item = try entryGate.submit(
                store: store,
                input: PracticeEntry.custom(name: name, category: .chord, targetMin: duration, projectId: selectedProjectId),
                token: submitToken,
                now: Date(),
                calendar: .current
            )
            selection = item.id.uuidString
            dismiss()
        } catch {
            isSubmitting = false
            toast = "创建练习失败，请重试"
        }
    }
}
