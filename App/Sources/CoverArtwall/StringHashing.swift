import CryptoKit
import Foundation

extension String {
    /// A stable, filesystem-safe identifier for this string, used to name
    /// cached wallpaper files after the artwork URL that produced them.
    var stableFileIdentifier: String {
        let digest = SHA256.hash(data: Data(utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
