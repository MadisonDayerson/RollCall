import AppKit
import SwiftUI

extension AppDelegate {
    // MARK: - Formatting

    static let dayTimeFmt: DateFormatter = fmt("EEE d MMM, h:mma")
    static let dayFmt: DateFormatter = fmt("EEE d MMM")
    static let longFmt: DateFormatter = fmt("EEEE d MMMM, h:mm a")
    static let longDayFmt: DateFormatter = fmt("EEEE d MMMM '(all day)'")
    static let timeFmt: DateFormatter = fmt("h:mm a")
    static let monthFmt: DateFormatter = fmt("yyyy-MM")
    static let relative: RelativeDateTimeFormatter = {
        let r = RelativeDateTimeFormatter()
        r.unitsStyle = .full
        return r
    }()

    static func fmt(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_AU")
        f.dateFormat = pattern
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return f
    }
}
