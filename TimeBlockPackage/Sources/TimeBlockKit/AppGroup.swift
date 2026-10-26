import Foundation
import Security

/// The App Group the app and its widget share settings and logs through.
public enum AppGroup {
    /// What unsigned builds name their settings, kept in the app's own container; signed builds bring these over.
    static let unsignedSuite = "group.dev.timeblock"

    /// "<team ID>.dev.timeblock", the prefix coming from the team the build is signed with, or nil for an unsigned
    /// build. Read from the build's entitlements, so the team isn't written into the code. Without the group,
    /// touching its container makes macOS ask the user for access to "other apps' data".
    public static let identifier: String? = {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let groups = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil)
                as? [String]
        else { return nil }
        return groups.first { $0.hasSuffix(".dev.timeblock") }
        #else
        return unsignedSuite
        #endif
    }()

    /// Where settings and timers are kept: in the App Group when the build has one, otherwise in the process's own
    /// container, so an unsigned app still works and its widget shows the standard schedule.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier ?? unsignedSuite) ?? .standard
    }
}
