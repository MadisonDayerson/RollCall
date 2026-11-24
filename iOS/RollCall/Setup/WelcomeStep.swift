import SwiftUI

struct WelcomeStep: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image("Monogram").resizable().scaledToFit().frame(height: 72).accessibilityHidden(true)
                Text("Welcome to RollCall").font(.largeTitle.bold()).multilineTextAlignment(.center)
                Text("RollCall finds motorbike group rides and events near you, from clubs, forums, event sites and your group chats, and puts the ones you're going to in your calendar.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 14) {
                    point("Set your home area so you only see rides nearby", "mappin.and.ellipse")
                    point("Share with RollCall on your Mac, which reads your group chats through Beeper", "bubble.left.and.bubble.right")
                    point("Follow clubs, Meetup groups, forums and your Facebook events", "person.3")
                    point("See road alerts on your routes", "exclamationmark.triangle")
                    point("Put your rides in your calendar", "calendar")
                    point("Be told about new rides", "bell")
                }
                .padding(.vertical, 8)
                Text("No accounts, no tracking, no online AI. RollCall never posts, sends messages or RSVPs for you.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    private func point(_ text: String, _ symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol).frame(width: 36).accessibilityHidden(true)
            Text(text)
        }
    }
}
