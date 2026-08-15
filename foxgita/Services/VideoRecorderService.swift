import AVFoundation
import SwiftUI
import UIKit

/// Lightweight video capture via the system camera UI.
/// Saves to `Documents/Recordings/` and exposes pending clips like audio.
@Observable
@MainActor
final class VideoRecorderService {
    struct Clip: Identifiable, Equatable {
        let id: String
        let fileName: String
        let bytes: Int
        let durationSec: Int
        let createdAt: Date
        let label: String
    }

    private(set) var pending: [Clip] = []
    private(set) var lastError: String?
    private(set) var isPresenting = false

    func presentCamera() {
        lastError = nil
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            lastError = String(localized: "此设备不支持摄像")
            return
        }
        isPresenting = true
    }

    func dismiss() {
        isPresenting = false
    }

    func ingest(tempURL: URL, label: String = "") {
        let name = RecordingStore.newFileName(extension: "mov")
        let dest = RecordingStore.url(for: name)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: tempURL, to: dest)
            pending.append(
                Clip(
                    id: UUID().uuidString,
                    fileName: name,
                    bytes: RecordingStore.byteSize(of: dest),
                    durationSec: RecordingStore.duration(of: dest),
                    createdAt: Date(),
                    label: label.isEmpty ? String(localized: "视频") : label
                )
            )
        } catch {
            lastError = String(localized: "无法保存视频")
        }
        isPresenting = false
    }

    func discard(_ id: String) {
        guard let idx = pending.firstIndex(where: { $0.id == id }) else { return }
        let clip = pending.remove(at: idx)
        RecordingStore.delete(fileName: clip.fileName)
    }

    func takeAll() -> [Clip] {
        let all = pending
        pending.removeAll()
        return all
    }

    /// Drops the take from `pending` but leaves the file for a persisted `RecordingRef`.
    func detach(_ id: String) {
        pending.removeAll { $0.id == id }
    }
}

struct VideoCameraPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onPicked: (URL) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.movie"]
        picker.cameraCaptureMode = .video
        picker.videoQuality = .typeMedium
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: VideoCameraPicker
        init(_ parent: VideoCameraPicker) { self.parent = parent }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
            parent.onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.isPresented = false
            if let url = info[.mediaURL] as? URL {
                parent.onPicked(url)
            } else {
                parent.onCancel()
            }
        }
    }
}
