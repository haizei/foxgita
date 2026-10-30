import SwiftData
import SwiftUI

struct PracticeProjectSelectionView: View {
    @Binding var selectedProjectId: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(PracticeStore.self) private var store
    @Query(filter: #Predicate<LocalProfile> { $0.isActive == true })
    private var profiles: [LocalProfile]
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil })
    private var allProjects: [Project]

    @State private var projectName = ""
    @State private var completionStandard = ""
    @State private var errorMessage: String?
    @State private var isCreating = false

    private var projects: [Project] {
        guard let profileId = profiles.first.flatMap({ UUID(uuidString: $0.id) }) else { return [] }
        return allProjects
            .filter { $0.profileId == profileId && $0.status == .active }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("返回")
                Spacer()
                Text("选择项目")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(GitaTheme.textPrimary)
                Spacer()
                Color.clear.frame(width: 36, height: 36)
            }
            .foregroundStyle(GitaTheme.textPrimary)
            .padding(.horizontal, 20)
            .padding(.top, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("现有项目")
                        .font(.system(size: 18, weight: .bold))
                        .padding(.bottom, 4)

                    projectRow(title: "不归项目", isSelected: selectedProjectId == nil) {
                        selectedProjectId = nil
                        dismiss()
                    }
                    ForEach(projects, id: \.id) { project in
                        projectRow(title: project.name, isSelected: selectedProjectId == project.id) {
                            selectedProjectId = project.id
                            dismiss()
                        }
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Label("新建项目", systemImage: "plus")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(GitaTheme.brand500)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("项目名称 *")
                                .font(.system(size: 15, weight: .semibold))
                            TextField("例如：吉他基础练习", text: $projectName)
                                .accessibilityIdentifier("practice.project-name")
                                .textInputAutocapitalization(.never)
                                .padding(14)
                                .background(GitaTheme.bgSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        TextField("添加完成标准（选填）", text: $completionStandard, axis: .vertical)
                            .lineLimit(1...3)
                            .padding(14)
                            .background(GitaTheme.bgSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13))
                                .foregroundStyle(GitaTheme.brand500)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GitaTheme.brand50)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.top, 16)
                }
                .padding(.horizontal, 20)
                .padding(.top, 52)
                .padding(.bottom, 24)
            }

            Button(action: createProject) {
                Text("创建并选择项目")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(GitaTheme.brandOn)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(GitaTheme.brand500)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .disabled(isCreating || ProjectSetupRules.trimmed(projectName).isEmpty)
            .opacity(isCreating || ProjectSetupRules.trimmed(projectName).isEmpty ? 0.5 : 1)
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(GitaTheme.bgDefault)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private func projectRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                Spacer()
                Image(systemName: isSelected ? "checkmark" : "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? GitaTheme.brand500 : GitaTheme.textSecondary)
            }
            .foregroundStyle(GitaTheme.textPrimary)
            .padding(.horizontal, 16)
            .frame(height: 62)
            .background(GitaTheme.bgSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func createProject() {
        switch ProjectSetupRules.prepare(name: projectName, goal: completionStandard) {
        case .failure(let error):
            errorMessage = error.fieldName == "name" ? "请填写 1–40 字的项目名称" : "完成标准最多 120 字"
        case .success(let fields):
            isCreating = true
            do {
                let project = try store.createProject(name: fields.name, goal: fields.goal, now: Date())
                selectedProjectId = project.id
                dismiss()
            } catch {
                errorMessage = "创建项目失败，请重试"
                isCreating = false
            }
        }
    }
}
