import Foundation
import Security

/// Checks that an app bundle still matches its own code signature, its sealed resources included.
///
/// macOS checks a running app's executable but not its resources, so a replaced `picotool` or firmware image inside the
/// bundle would go unnoticed until something asks. `ProcessPicotoolRunner` asks before every start of `picotool`. Changing
/// the executable instead takes a new signature, which changes the app's identity and with it its system audio capture
/// permission.
enum BundleSeal {
    /// Throws unless the bundle at `bundleURL` is signed and every file its signature seals is unchanged.
    ///
    /// - Parameter bundleURL: The app bundle to check, the running app's own in production.
    /// - Throws: `FlashError.bundleSealBroken` when the bundle is unsigned or a sealed file was changed, added, or
    ///   removed.
    static func verify(_ bundleURL: URL) throws {
        var code: SecStaticCode?
        guard
            SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &code) == errSecSuccess,
            let code
        else {
            throw FlashError.bundleSealBroken
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        guard SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess else {
            throw FlashError.bundleSealBroken
        }
    }
}
