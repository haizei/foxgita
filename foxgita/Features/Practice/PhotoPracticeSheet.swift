import Combine
import PhotosUI
import SwiftUI

struct PhotoPracticeSheet: View {
    private enum Phase {
        case source
        case generating
    }

    var fallbackCategory: PracticeCategory
    var baseURL: String
    var model: String
    @Binding var selection: String?
    var onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(PracticeStore.self) private var store
    @State private var phase: Phase = .source
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isCameraPresented = false
    @State private var isGenerating = false
    @State private var generateTask: Task<Void, Never>?
    @State private var generationStartedAt = Date()
    @State private var elapsed: TimeInterval = 0
    @State private var completed = false
    @State private var toast: String?

    private let generator = ImageStepGenerator(client: VisionPracticeClient())
    private let progressTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(GitaTheme.borderSubtle)
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            HStack {
                Text(phase == .source ? "从图片生成练习" : "正在生成练习")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Button("关闭", action: close)
                    .font(.system(size: 14))
                    .foregroundStyle(GitaTheme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)

            Group {
                switch phase {
                case .source:
                    sourceContent
                case .generating:
                    generatingContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(GitaTheme.bgDefault)
        .overlay {
            if let toast {
                VStack {
                    Spacer()
                    ToastBanner(text: toast)
                        .padding(.bottom, 40)
                }
            }
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            StillImageCameraPicker(
                isPresented: $isCameraPresented,
                onPicked: { beginGeneration(blobs: [$0]) },
                onCancel: {}
            )
            .ignoresSafeArea()
        }
        .onReceive(progressTimer) { _ in
            guard isGenerating else { return }
            elapsed = Date().timeIntervalSince(generationStartedAt)
        }
        .onDisappear {
            generateTask?.cancel()
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private var sourceContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("选择一张乐谱、和弦图或练习笔记")
                    .font(.system(size: 17, weight: .bold))
                Text("AI 会识别图片内容，并整理成可以直接开始的练习步骤。")
                    .font(.system(size: 13))
                    .foregroundStyle(GitaTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                sourceCard(
                    title: String(localized: "拍照"),
                    subtitle: String(localized: "拍摄一张图片"),
                    systemImage: "camera.fill",
                    background: GitaTheme.brand50,
                    titleColor: GitaTheme.brand500
                ) {
                    isCameraPresented = true
                }

                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: 3,
                    matching: .images
                ) {
                    sourceCardLabel(
                        title: String(localized: "相册"),
                        subtitle: String(localized: "最多选择 3 张"),
                        systemImage: "photo.on.rectangle",
                        background: GitaTheme.bgSubtle,
                        titleColor: GitaTheme.textPrimary
                    )
                }
                .buttonStyle(.plain)
                .onChange(of: pickerItems) { _, items in
                    guard !items.isEmpty else { return }
                    beginGeneration(items: items)
                }
            }

            Text("识别完成后会直接生成练习页，你仍可修改内容")
                .font(.system(size: 12))
                .foregroundStyle(GitaTheme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 28)
    }

    private var generatingContent: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(GitaTheme.brand500)
                .frame(width: 64, height: 64)
                .background(GitaTheme.brand50)
                .clipShape(Circle())

            Text("正在识别图片内容")
                .font(.system(size: 18, weight: .bold))

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(GitaTheme.bgSubtle)
                    Capsule()
                        .fill(GitaTheme.brand500)
                        .frame(
                            width: proxy.size.width * CGFloat(
                                PhotoGenerationProgress.fraction(
                                    elapsed: elapsed,
                                    completed: completed
                                )
                            )
                        )
                }
            }
            .frame(height: 8)
            .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(PhotoGenerationProgress.captions.enumerated()), id: \.offset) { index, caption in
                    HStack(spacing: 10) {
                        Image(
                            systemName: index <= activeProgressIndex
                                ? "checkmark.circle.fill"
                                : "circle"
                        )
                        .foregroundStyle(
                            index <= activeProgressIndex
                                ? GitaTheme.brand500
                                : GitaTheme.borderSubtle
                        )
                        Text(caption)
                            .font(.system(size: 13, weight: index == activeProgressIndex ? .semibold : .regular))
                            .foregroundStyle(
                                index <= activeProgressIndex
                                    ? GitaTheme.textSecondary
                                    : GitaTheme.textTertiary
                            )
                    }
                }
            }

            Spacer()

            Text("完成后将自动进入生成的练习页")
                .font(.system(size: 12))
                .foregroundStyle(GitaTheme.textTertiary)
                .padding(.bottom, 28)
        }
        .padding(.horizontal, 16)
    }

    private var activeProgressIndex: Int {
        PhotoGenerationProgress.activeIndex(elapsed: elapsed, completed: completed)
    }

    private func sourceCard(
        title: String,
        subtitle: String,
        systemImage: String,
        background: Color,
        titleColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            sourceCardLabel(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage,
                background: background,
                titleColor: titleColor
            )
        }
        .buttonStyle(.plain)
    }

    private func sourceCardLabel(
        title: String,
        subtitle: String,
        systemImage: String,
        background: Color,
        titleColor: Color
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(titleColor)
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(titleColor)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(GitaTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 142)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(GitaTheme.borderSubtle, lineWidth: 1)
        }
    }

    private func beginGeneration(items: [PhotosPickerItem]) {
        prepareGeneration()
        generateTask = Task {
            do {
                var blobs: [Data] = []
                for item in items.prefix(3) {
                    try Task.checkCancellation()
                    if let data = try await item.loadTransferable(type: Data.self) {
                        blobs.append(data)
                    }
                }
                try await generate(blobs: blobs)
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                fail(with: error)
            }
        }
    }

    private func beginGeneration(blobs: [Data]) {
        prepareGeneration()
        generateTask = Task {
            do {
                try await generate(blobs: blobs)
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                fail(with: error)
            }
        }
    }

    private func prepareGeneration() {
        phase = .generating
        isGenerating = true
        completed = false
        elapsed = 0
        generationStartedAt = Date()
        toast = nil
    }

    private func generate(blobs: [Data]) async throws {
        let draft = try await generator.generate(
            imageData: blobs,
            baseURL: baseURL,
            model: model,
            fallbackCategory: fallbackCategory
        )
        try Task.checkCancellation()
        guard let id = store.createFromAIDraft(draft) else {
            throw PhotoPracticeSheetError.storeFailed
        }
        completed = true
        isGenerating = false
        selection = id
        onFinished()
    }

    private func fail(with error: Error) {
        isGenerating = false
        phase = .source
        pickerItems = []
        generateTask = nil
        if let error = error as? ImageStepGeneratorError {
            toast = error.userMessage
        } else {
            toast = String(localized: "生成失败，请稍后重试")
        }
        hideToastLater()
    }

    private func close() {
        if phase == .generating {
            generateTask?.cancel()
            generateTask = nil
            pickerItems = []
            isGenerating = false
            completed = false
            elapsed = 0
            phase = .source
        } else {
            dismiss()
        }
    }

    private func hideToastLater() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            toast = nil
        }
    }
}

private enum PhotoPracticeSheetError: Error {
    case storeFailed
}
