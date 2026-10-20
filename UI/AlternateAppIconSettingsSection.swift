import SwiftUI
import PhotosUI
import UIKit

/// Settings section for native, bundled alternate icons and user-selected icon artwork.
/// iOS only permits `setAlternateIconName` to select icons bundled with the app.
struct AlternateAppIconSettingsSection: View {
    private struct BundledIcon: Identifiable {
        let name: String?
        let title: String
        let previewAsset: String

        var id: String { name ?? "default" }
    }

    private let bundledIcons: [BundledIcon] = [
        BundledIcon(name: nil, title: "Original", previewAsset: "AppIconPreview"),
        BundledIcon(name: "ToyakoOceanIcon", title: "Ocean", previewAsset: "ToyakoOceanPreview"),
        BundledIcon(name: "ToyakoVioletIcon", title: "Violet", previewAsset: "ToyakoVioletPreview")
    ]

    @State private var activeIconName = UIApplication.shared.alternateIconName
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var customImage: UIImage?
    @State private var customIconURL: URL?
    @State private var statusMessage: String?
    @State private var isLoadingPhoto = false

    var body: some View {
        Section("App Icon") {
            Text("Choose a built-in Toyako icon, or prepare your own artwork for a Home Screen shortcut.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(bundledIcons) { icon in
                Button {
                    setBundledIcon(icon)
                } label: {
                    HStack(spacing: 12) {
                        Image(icon.previewAsset)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                        Text(icon.title)
                            .foregroundStyle(.primary)

                        Spacer()

                        if activeIconName == icon.name {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(ToyakoDesign.Color.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Divider()

            HStack(spacing: 12) {
                Group {
                    if let customImage {
                        Image(uiImage: customImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "photo.badge.plus")
                            .resizable()
                            .scaledToFit()
                            .padding(12)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 64, height: 64)
                .background(Color.secondary.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Custom Icon")
                        .font(.headline)
                    Text(customImage == nil ? "Choose an image from Photos" : "Custom artwork saved on this device")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                Label(customImage == nil ? "Choose Custom Image" : "Replace Custom Image", systemImage: "photo.on.rectangle.angled")
            }
            .disabled(isLoadingPhoto)
            .onChange(of: selectedPhoto) { _, newItem in
                guard let newItem else { return }
                Task {
                    await loadCustomImage(from: newItem)
                }
            }

            if let customIconURL {
                ShareLink(item: customIconURL) {
                    Label("Export Custom Icon Image", systemImage: "square.and.arrow.up")
                }

                Text("To use this image on the Home Screen, export it and create a shortcut in Apple's Shortcuts app. iOS does not let apps register an arbitrary photo as a native app icon at runtime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Remove Custom Image", role: .destructive) {
                    removeCustomImage()
                }
            }

            if isLoadingPhoto {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading image…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: restoreCustomImage)
    }

    private func setBundledIcon(_ icon: BundledIcon) {
        guard UIApplication.shared.supportsAlternateIcons else {
            statusMessage = "Alternate app icons are not supported in this build."
            return
        }

        UIApplication.shared.setAlternateIconName(icon.name) { error in
            DispatchQueue.main.async {
                if let error {
                    statusMessage = "Couldn't change icon: \(error.localizedDescription)"
                } else {
                    activeIconName = icon.name
                    statusMessage = "App icon updated."
                }
            }
        }
    }

    @MainActor
    private func loadCustomImage(from item: PhotosPickerItem) async {
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let pngData = image.pngData() else {
                statusMessage = "That image couldn't be opened. Please choose another image."
                return
            }

            let url = Self.customIconFileURL()
            try pngData.write(to: url, options: .atomic)
            customImage = image
            customIconURL = url
            statusMessage = "Custom image saved in Toyako. Export it to use it in a Home Screen shortcut."
        } catch {
            statusMessage = "Couldn't save the image: \(error.localizedDescription)"
        }
    }

    private func restoreCustomImage() {
        let url = Self.customIconFileURL()
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return }
        customImage = image
        customIconURL = url
    }

    private func removeCustomImage() {
        if let customIconURL {
            try? FileManager.default.removeItem(at: customIconURL)
        }
        customImage = nil
        customIconURL = nil
        selectedPhoto = nil
        statusMessage = "Custom image removed."
    }

    private static func customIconFileURL() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("ToyakoCustomAppIcon.png", isDirectory: false)
    }
}
