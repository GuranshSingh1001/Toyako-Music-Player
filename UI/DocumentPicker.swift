import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct DocumentPicker:
    UIViewControllerRepresentable {

    let onPick:
        ([URL]) -> Void

    func makeUIViewController(
        context:
            Context
    ) -> UIDocumentPickerViewController {

        let supportedTypes:
            [UTType] = [
                .audio,
                .mp3,
                .mpeg4Audio,
                .wav,
                .aiff,
                .flac
            ]

        let picker =
            UIDocumentPickerViewController(
                forOpeningContentTypes:
                    supportedTypes,
                asCopy:
                    true
            )

        picker.allowsMultipleSelection =
            true

        picker.delegate =
            context.coordinator

        return picker
    }

    func updateUIViewController(
        _ uiViewController:
            UIDocumentPickerViewController,
        context:
            Context
    ) {
    }

    func makeCoordinator()
        -> Coordinator {

        Coordinator(
            onPick:
                onPick
        )
    }

    final class Coordinator:
        NSObject,
        UIDocumentPickerDelegate {

        let onPick:
            ([URL]) -> Void

        init(
            onPick:
                @escaping ([URL]) -> Void
        ) {
            self.onPick =
                onPick
        }

        func documentPicker(
            _ controller:
                UIDocumentPickerViewController,
            didPickDocumentsAt urls:
                [URL]
        ) {
            guard !urls.isEmpty
            else {
                return
            }

            onPick(urls)
        }
    }
}