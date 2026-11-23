import SwiftUI

/// Chooses the RollCall folder in iCloud Drive and starts sharing with RollCall on the Mac through it.
struct MacFolderButton: View {
    @Environment(PhoneModel.self) private var model
    let title: String
    @State private var choosing = false

    var body: some View {
        Button(title) { choosing = true }
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let folder): model.shareWithMac(in: folder)
                case .failure(let error): model.shareProblem = error.localizedDescription
                }
            }
    }
}
