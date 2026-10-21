import AppKit
import NeXTsoundCore
import SwiftUI
import UniformTypeIdentifiers

/// Shows the driver's image, with an affordance to add or replace it. The 3D model (if any)
/// lives in its own window, opened from the form's toolbar; this header never shows it inline.
/// Resizable in height via a drag handle, persisted.
struct DriverPreviewHeader: View {
    static let minimumHeight: CGFloat = 120
    static let maximumHeight: CGFloat = 600

    @Binding var draft: DriverRecord
    @AppStorage("driverForm.previewHeight") private var height = 200.0
    @State private var dragStartHeight: CGFloat?
    @State private var isImporting = false
    @State private var importError: String?

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                imageOrPlaceholder
                Button("Add Image", systemImage: "photo.badge.plus") {
                    isImporting = true
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .padding(8)
                .help(draft.imageAssetName == nil ? "Add an image" : "Replace the image")
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()
            ResizeHandle(height: $height, dragStartHeight: $dragStartHeight)
        }
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.image], onCompletion: handleImport)
        .alert("The image could not be imported", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }
}

private struct ResizeHandle: View {
    @Binding var height: Double
    @Binding var dragStartHeight: CGFloat?

    var body: some View {
        Capsule()
            .fill(.secondary)
            .frame(width: 36, height: 5)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartHeight == nil {
                            dragStartHeight = height
                        }
                        let proposed = (dragStartHeight ?? height) + value.translation.height
                        height = min(max(proposed, DriverPreviewHeader.minimumHeight), DriverPreviewHeader.maximumHeight)
                    }
                    .onEnded { _ in
                        dragStartHeight = nil
                    }
            )
            .help("Drag to resize the preview")
    }
}

private extension DriverPreviewHeader {
    @ViewBuilder var imageOrPlaceholder: some View {
        let nsImage = draft.imageAssetName
            .flatMap { DriverAssetStore.standard().url(forAsset: $0) }
            .flatMap { NSImage(contentsOf: $0) }
        if let nsImage {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(16)
        } else {
            ContentUnavailableView("No image yet", systemImage: "photo", description: Text("Add an image to show it here."))
        }
    }

    var errorIsPresented: Binding<Bool> {
        Binding(get: { importError != nil }, set: {
            if !$0 {
                importError = nil
            }
        })
    }

    func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            do {
                let name = try DriverAssetStore.standard().importFile(at: url, forDriver: draft.id, role: "image")
                draft.imageAssetName = name
            } catch {
                importError = error.localizedDescription
            }
        case let .failure(error):
            importError = error.localizedDescription
        }
    }
}
