import Foundation

/// Local installs can use a distinct display name without forking application code.
enum AppIdentity {
    static var displayName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? "edgelesstype"
    }
}
