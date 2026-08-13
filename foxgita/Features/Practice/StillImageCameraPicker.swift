import SwiftUI
import UIKit

struct StillImageCameraPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onPicked: (Data) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            DispatchQueue.main.async {
                isPresented = false
                onCancel()
            }
            return picker
        }

        picker.sourceType = .camera
        picker.mediaTypes = ["public.image"]
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: StillImageCameraPicker

        init(_ parent: StillImageCameraPicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
            parent.onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.isPresented = false
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.9)
            else {
                parent.onCancel()
                return
            }
            parent.onPicked(data)
        }
    }
}
