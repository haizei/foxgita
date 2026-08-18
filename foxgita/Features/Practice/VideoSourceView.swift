import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct VideoSourceView: View {
    let taskTitle: String
    var onDismiss: () -> Void
    var onStartCamera: () -> Void
    var onImported: (VideoRecorderService.Clip) -> Void
    var onToast: (String) -> Void

    private enum Mode { case camera, album }

    @State private var mode: Mode = .camera
    @State private var pickerItem: PhotosPickerItem?
    @State private var preview: AlbumPreviewItem?
    @State private var albumDenied = false

    var body: some View {
        ZStack {
            PageBackground()
            VStack(spacing: 0) {
                HStack {
                    Button(String(localized: "返回"), action: onDismiss)
                        .font(.system(size: 14))
                        .foregroundStyle(GitaTheme.textSecondary)
                        .frame(minWidth: 40, alignment: .leading)
                    Text(String(localized: "选择视频来源"))
                        .font(.system(size: 20, weight: .bold))
                        .frame(maxWidth: .infinity)
                    Color.clear.frame(width: 40, height: 1)
                }
                .frame(minHeight: 56)
                .padding(.horizontal, 16)

                Text(taskTitle)
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)

                SegmentedPills(
                    titles: [String(localized: "现场录像"), String(localized: "上传相册")],
                    selection: Binding(
                        get: { mode == .camera ? 0 : 1 },
                        set: { mode = $0 == 0 ? .camera : .album }
                    )
                )
                .padding(.horizontal, 16)
                .padding(.top, 16)

                card
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                Spacer()

                bottomButton
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
        }
        .onAppear { refreshAlbumAuth() }
        .fullScreenCover(item: $preview) { item in
            AlbumPreviewView(
                item: item,
                onBack: { closePreview(discard: true) },
                onReselect: { closePreview(discard: true) },
                onConfirm: { confirm(item) }
            )
        }
        .onDisappear {
            if let url = preview?.url { discardStaged(url) }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await loadPicked(item) }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(mode == .camera ? String(localized: "现场录像") : String(localized: "上传相册"))
                .font(.system(size: 17, weight: .bold))
            Text(
                mode == .camera
                    ? String(localized: "立即拍摄本次练习，完成后进行分段诊断")
                    : String(localized: "选择已有练习视频，完成后进行分段诊断")
            )
            .font(.system(size: 13))
            .foregroundStyle(GitaTheme.textSecondary)
            if mode == .album, albumDenied {
                Button(String(localized: "前往系统设置")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GitaTheme.brand500)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: GitaTheme.shadowCard, radius: 8, y: 4)
    }

    @ViewBuilder
    private var bottomButton: some View {
        if mode == .camera {
            Button(String(localized: "开始录像"), action: onStartCamera)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(GitaTheme.brandOn)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(GitaTheme.brand500)
                .clipShape(Capsule())
        } else if albumDenied {
            Button(String(localized: "前往系统设置")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(GitaTheme.brandOn)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(GitaTheme.brand500)
            .clipShape(Capsule())
        } else {
            PhotosPicker(selection: $pickerItem, matching: .videos) {
                Text(String(localized: "选择视频"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(GitaTheme.brandOn)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(GitaTheme.brand500)
                    .clipShape(Capsule())
            }
        }
    }

    private func refreshAlbumAuth() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        albumDenied = status == .denied || status == .restricted
    }

    private func loadPicked(_ item: PhotosPickerItem) async {
        do {
            guard let movie = try await item.loadTransferable(type: ImportedMovie.self) else {
                onToast(String(localized: "无法读取该视频"))
                return
            }
            let duration = await RecordingStore.loadDuration(of: movie.url)
            let name = movie.displayName
            preview = AlbumPreviewItem(
                url: movie.url,
                displayName: name.isEmpty ? String(localized: "相册视频") : name,
                durationSec: duration
            )
        } catch {
            onToast(String(localized: "无法读取该视频"))
        }
    }

    private func confirm(_ item: AlbumPreviewItem) {
        do {
            let clip = try AlbumVideoImporter.importClip(
                from: item.url,
                label: taskTitle,
                durationSec: item.durationSec
            )
            discardStaged(item.url)
            preview = nil
            onImported(clip)
        } catch {
            onToast(String(localized: "无法保存视频"))
        }
    }

    private func discardStaged(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func closePreview(discard: Bool) {
        if discard, let url = preview?.url {
            discardStaged(url)
        }
        preview = nil
        pickerItem = nil
    }
}

struct ImportedMovie: Transferable {
    let url: URL
    let displayName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        }         importing: { received in
            let staged = try AlbumVideoImporter.stagePreview(from: received.file)
            return Self(url: staged, displayName: received.file.lastPathComponent)
        }
    }
}
