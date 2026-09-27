import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void

    func makeUIViewController(
        context: Context
    ) -> UIDocumentPickerViewController {

        // .audio is intentionally used instead of individual
        // types such as UTType.flac. This accepts audio files
        // supported by the system without causing the
        // UTType.flac compiler error.
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.audio],
            asCopy: true
        )

        picker.allowsMultipleSelection = true
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator

        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void

        init(
            onPick: @escaping ([URL]) -> Void
        ) {
            self.onPick = onPick
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            guard !urls.isEmpty else {
                return
            }

            onPick(urls)
        }

        func documentPickerWasCancelled(
            _ controller: UIDocumentPickerViewController
        ) {
        }
    }
}
