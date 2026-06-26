import Foundation
import CryptoKit

/// PKCE (Proof Key for Code Exchange, RFC 7636) parameters for an OAuth2
/// Authorization-Code flow on a public client (no embedded secret). Generated
/// fresh per authorization attempt; the `verifier` is kept locally and sent at
/// the token-exchange step to prove the same client started the flow.
struct PKCEChallenge: Equatable {
    let verifier: String
    let challenge: String
    let method = "S256"

    init(verifier: String = PKCEChallenge.makeVerifier()) {
        self.verifier = verifier
        self.challenge = PKCEChallenge.challenge(for: verifier)
    }

    /// A high-entropy URL-safe verifier (43–128 chars per spec). We use 64 random
    /// bytes → base64url ≈ 86 chars.
    static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    /// S256 challenge = base64url( SHA256( verifier ) ).
    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(digest))
    }

    /// Base64url without padding (RFC 4648 §5), as required by PKCE.
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
