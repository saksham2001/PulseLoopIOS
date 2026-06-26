import Foundation
import CryptoKit

// MARK: - SubAppPackage — export/import a signed SubAppSpec (roadmap F1)
//
// Sharing transfers the *spec* (declarative data), never executable code. A shared
// spec is wrapped in a signed envelope so the importer can detect tampering and the
// origin is attributable. Signing here is an HMAC-SHA256 over the spec's canonical
// JSON. v1 uses a well-known app-shared key (tamper-evidence + format integrity,
// not secrecy); when the backend (E3) lands, the server signs with a private key and
// the client verifies a public-key signature instead — `SubAppPackage` is the seam.

/// A signed, shareable envelope around a `SubAppSpec`.
struct SubAppPackage: Codable, Hashable {
    /// Envelope format version (independent of the spec's schemaVersion).
    var format: Int
    /// Signing algorithm identifier, e.g. "hmac-sha256".
    var algorithm: String
    /// When the package was signed.
    var signedAt: Date
    /// The spec being shared.
    var spec: SubAppSpec
    /// Base64 signature over the canonical encoding of `spec`.
    var signature: String

    static let currentFormat = 1
    static let hmacAlgorithm = "hmac-sha256"
}

/// Errors raised while exporting/importing a `SubAppPackage`.
enum SubAppPackageError: Error, LocalizedError {
    case unsupportedFormat(Int)
    case unknownAlgorithm(String)
    case signatureMismatch
    case invalidSpec(SubAppSpecValidationError)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let v): return "This sub-app file uses an unsupported format (v\(v))."
        case .unknownAlgorithm(let a): return "Unknown signature algorithm '\(a)'."
        case .signatureMismatch: return "This sub-app file has been tampered with or is corrupted."
        case .invalidSpec(let e): return "The sub-app failed validation: \(e.issues.first?.message ?? "invalid")."
        case .decoding(let m): return "Couldn't read the sub-app file: \(m)."
        }
    }
}

/// Exports/imports signed sub-app packages. Pure value logic so it's easy to test.
enum SubAppPackager {
    /// App-shared HMAC key for v1 tamper-evidence. Not a secret-protection mechanism —
    /// it makes casual edits detectable and pins the canonical format. The server
    /// (F2/F3) replaces this with asymmetric signing.
    private static let sharedKey = SymmetricKey(data: Data("pulseloop.subapp.signing.v1".utf8))

    // MARK: Export

    /// Wrap a (validated) spec in a signed package.
    static func makePackage(for spec: SubAppSpec, signedAt: Date = Date()) throws -> SubAppPackage {
        try SubAppSpecValidator.validate(spec)
        let signature = try sign(spec)
        return SubAppPackage(
            format: SubAppPackage.currentFormat,
            algorithm: SubAppPackage.hmacAlgorithm,
            signedAt: signedAt,
            spec: spec,
            signature: signature
        )
    }

    /// Encode a signed package to pretty JSON suitable for a `.pulseapp` file or share sheet.
    static func exportData(for spec: SubAppSpec) throws -> Data {
        let package = try makePackage(for: spec)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(package)
    }

    // MARK: Import

    /// Decode a package, verify its signature, and strictly validate the spec.
    /// Returns the trusted spec on success.
    static func importSpec(from data: Data) throws -> SubAppSpec {
        let package: SubAppPackage
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            package = try decoder.decode(SubAppPackage.self, from: data)
        } catch {
            throw SubAppPackageError.decoding(error.localizedDescription)
        }

        guard package.format <= SubAppPackage.currentFormat else {
            throw SubAppPackageError.unsupportedFormat(package.format)
        }
        guard package.algorithm == SubAppPackage.hmacAlgorithm else {
            throw SubAppPackageError.unknownAlgorithm(package.algorithm)
        }
        guard try verify(package) else {
            throw SubAppPackageError.signatureMismatch
        }
        do {
            try SubAppSpecValidator.validate(package.spec)
        } catch let e as SubAppSpecValidationError {
            throw SubAppPackageError.invalidSpec(e)
        }
        return package.spec
    }

    // MARK: Signing internals

    /// Canonical encoding of a spec: sorted keys, no whitespace, stable dates. Both
    /// signer and verifier must produce byte-identical output, so encoding options
    /// are fixed here.
    private static func canonicalData(_ spec: SubAppSpec) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(spec)
    }

    private static func sign(_ spec: SubAppSpec) throws -> String {
        let data = try canonicalData(spec)
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: sharedKey)
        return Data(mac).base64EncodedString()
    }

    private static func verify(_ package: SubAppPackage) throws -> Bool {
        guard let provided = Data(base64Encoded: package.signature) else { return false }
        let data = try canonicalData(package.spec)
        return HMAC<SHA256>.isValidAuthenticationCode(provided, authenticating: data, using: sharedKey)
    }
}
