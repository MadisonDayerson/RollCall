import SwiftUI

/// The chosen ride's page. It looks the ride up itself: a page opened over the list isn't given the ride again when it
/// changes, so it would keep showing how the ride was when it was opened.
struct RidePage: View {
    @Environment(PhoneModel.self) private var model
    let id: String?
    let close: () -> Void

    var body: some View {
        if let id, let ride = model.state.events[id] {
            RideDetail(ride: ride, close: close).id(id)
        } else {
            EmptyState(text: "Choose a ride to see its details.")
        }
    }
}
