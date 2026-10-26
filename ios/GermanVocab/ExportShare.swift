import SwiftUI
import UIKit

struct ExportShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// UIKit share sheet for a temporary export file.
struct ActivityShareView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
