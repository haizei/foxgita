//
//  RecommendSheet.swift
//  foxgita
//

import SwiftData
import SwiftUI

struct RecommendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PracticeStore.self) private var store
    @Query(
        filter: #Predicate<TaskItem> { $0.deletedAt == nil },
        sort: \TaskItem.sortOrder
    )
    private var allTasks: [TaskItem]

    @State private var category: PracticeCategory = .left
    @State private var name = ""
    @State private var duration = 10
    @AppStorage(LLMSettingsKey.baseURL) private var llmBaseURL = ""
    @AppStorage(LLMSettingsKey.model) private var llmModel = ""
    @State private var showPhotoSheet = false
    @State private var showNextSessionSheet = false
    @State private var toast: String?
    private let credentials = LLMCredentialsStore()
    /// Handed back to the presenter, which navigates in `.sheet(onDismiss:)`.
    /// Pushing from inside the sheet races the dismissal animation.
    @Binding var selection: String?

    private var cards: [TaskItem] {
        let templates = allTasks.filter { $0.isTemplate && $0.category == category }
        if !templates.isEmpty { return templates }
        return allTasks.filter { !$0.isTemplate && $0.category == category }
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(GitaTheme.borderSubtle)
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            HStack {
                Text("推荐练习")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Button("关闭") { dismiss() }
                    .font(.system(size: 14))
                    .foregroundStyle(GitaTheme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("创建自己的练习")
                            .font(.system(size: 16, weight: .bold))
                        Text("写下练习名称，设定今天的小目标")
                            .font(.system(size: 12))
                            .foregroundStyle(GitaTheme.textSecondary)
                        HStack(spacing: 8) {
                            TextField("例如：F 和弦转换", text: $name)
                                .padding(.leading, 10)
                            Button {
                                let missing = credentials.missingFieldLabels(
                                    baseURL: llmBaseURL, model: llmModel
                                )
                                if missing.isEmpty {
                                    showPhotoSheet = true
                                } else {
                                    toast = String(
                                        localized: "还缺 \(missing.joined(separator: "、"))，请在设置里填完并点保存"
                                    )
                                    hideToastLater()
                                }
                            } label: {
                                Text("拍摄/照片")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(GitaTheme.brand500)
                                    .padding(.horizontal, 10)
                                    .frame(height: 34)
                                    .background(GitaTheme.brand50)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .disabled(showPhotoSheet || showNextSessionSheet)
                            Button {
                                let missing = credentials.missingFieldLabels(
                                    baseURL: llmBaseURL, model: llmModel
                                )
                                if missing.isEmpty {
                                    showNextSessionSheet = true
                                } else {
                                    toast = String(
                                        localized: "还缺 \(missing.joined(separator: "、"))，请在设置里填完并点保存"
                                    )
                                    hideToastLater()
                                }
                            } label: {
                                Text("安排今日")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(GitaTheme.brand500)
                                    .padding(.horizontal, 10)
                                    .frame(height: 34)
                                    .background(GitaTheme.brand50)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .disabled(showPhotoSheet || showNextSessionSheet)
                            Rectangle()
                                .fill(GitaTheme.borderSubtle)
                                .frame(width: 1, height: 24)
                            HStack(spacing: 8) {
                                Button { duration = max(5, duration - 5) } label: {
                                    Text("－").frame(width: 28, height: 28)
                                }
                                Text("\(duration) 分钟")
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(minWidth: 40)
                                Button { duration = min(60, duration + 5) } label: {
                                    Text("＋").frame(width: 28, height: 28)
                                }
                            }
                            .foregroundStyle(GitaTheme.textSecondary)
                            .padding(.trailing, 6)
                        }
                        .padding(.vertical, 6)
                        .background(GitaTheme.bgSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        Button {
                            selection = store.createCustomTask(
                                name: name, minutes: duration, category: category
                            )
                            dismiss()
                        } label: {
                            Text("创建练习")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(GitaTheme.brandOn)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(GitaTheme.brand500)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                    .background(GitaTheme.bgSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    HStack {
                        Text("推荐分类")
                            .font(.system(size: 18, weight: .bold))
                        Spacer()
                        Text("7 个固定分类")
                            .font(.system(size: 12))
                            .foregroundStyle(GitaTheme.textSecondary)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(PracticeCategory.allCases) { cat in
                                Button {
                                    category = cat
                                } label: {
                                    Text(cat.label)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(category == cat ? GitaTheme.brandOn : GitaTheme.textSecondary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(category == cat ? GitaTheme.brand500 : GitaTheme.bgSubtle)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(cards, id: \.id) { task in
                            Button {
                                selection = store.activateTemplate(task.id)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(task.title)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(GitaTheme.textPrimary)
                                        .lineLimit(1)
                                    Text(task.subtitle)
                                        .font(.system(size: 11))
                                        .foregroundStyle(GitaTheme.textSecondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(GitaTheme.bgSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
        }
        .background(GitaTheme.bgDefault)
        .sheet(isPresented: $showPhotoSheet) {
            PhotoPracticeSheet(
                fallbackCategory: category,
                baseURL: llmBaseURL,
                model: llmModel,
                selection: $selection,
                onFinished: {
                    showPhotoSheet = false
                    dismiss()
                }
            )
        }
        .sheet(isPresented: $showNextSessionSheet) {
            NextSessionSheet(
                initialMinutes: duration,
                fallbackCategory: category,
                baseURL: llmBaseURL,
                model: llmModel,
                selection: $selection,
                onFinished: {
                    showNextSessionSheet = false
                    dismiss()
                }
            )
        }
        .overlay {
            if let toast {
                VStack {
                    Spacer()
                    ToastBanner(text: toast).padding(.bottom, 40)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private func hideToastLater() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { toast = nil }
    }
}
