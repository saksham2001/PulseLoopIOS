import Foundation
import CryptoKit

/// Minimal AWS Signature Version 4 signer for a single POST request, implemented
/// with CryptoKit so we don't pull in the AWS SDK. Covers exactly what the
/// Bedrock `InvokeModel` call needs: a JSON body, `host`/`x-amz-date` signed
/// headers, and (optionally) a session token.
///
/// Reference: AWS "Signature Version 4 signing process".
enum AWSSigV4Signer {
    struct Credentials: Sendable {
        let accessKeyID: String
        let secretAccessKey: String
        /// Optional STS session token (for temporary credentials). Empty for
        /// long-lived IAM user keys.
        let sessionToken: String?
    }

    /// Signs `request` in place. The request must already have its `url`,
    /// `httpMethod`, and `httpBody` set. Adds `Host`, `X-Amz-Date`,
    /// `X-Amz-Security-Token` (if present), and `Authorization` headers.
    static func sign(
        _ request: inout URLRequest,
        service: String,
        region: String,
        credentials: Credentials,
        date: Date = Date()
    ) {
        guard let url = request.url, let host = url.host else { return }
        let method = request.httpMethod ?? "POST"
        let body = request.httpBody ?? Data()

        let amzDate = Self.amzDateFormatter.string(from: date)        // 20240101T000000Z
        let dateStamp = Self.dateStampFormatter.string(from: date)    // 20240101

        // --- Task 1: canonical request ---
        let canonicalURI = url.path.isEmpty ? "/" : Self.encodeURIPath(url.path)
        let canonicalQuery = Self.canonicalQueryString(url)

        let payloadHash = Self.sha256Hex(body)

        // Signed headers (lowercase, sorted). content-type is included because we
        // always send JSON; host + x-amz-date are required.
        var headers: [(String, String)] = [
            ("content-type", "application/json"),
            ("host", host),
            ("x-amz-date", amzDate),
        ]
        if let token = credentials.sessionToken, !token.isEmpty {
            headers.append(("x-amz-security-token", token))
        }
        headers.sort { $0.0 < $1.0 }

        let canonicalHeaders = headers.map { "\($0.0):\($0.1)\n" }.joined()
        let signedHeaders = headers.map { $0.0 }.joined(separator: ";")

        let canonicalRequest = [
            method,
            canonicalURI,
            canonicalQuery,
            canonicalHeaders,
            signedHeaders,
            payloadHash,
        ].joined(separator: "\n")

        // --- Task 2: string to sign ---
        let algorithm = "AWS4-HMAC-SHA256"
        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            algorithm,
            amzDate,
            credentialScope,
            Self.sha256Hex(Data(canonicalRequest.utf8)),
        ].joined(separator: "\n")

        // --- Task 3: signing key + signature ---
        let signingKey = Self.signingKey(
            secret: credentials.secretAccessKey,
            dateStamp: dateStamp,
            region: region,
            service: service
        )
        let signature = Self.hmacHex(key: signingKey, data: Data(stringToSign.utf8))

        // --- Task 4: assemble Authorization header ---
        let authorization = "\(algorithm) "
            + "Credential=\(credentials.accessKeyID)/\(credentialScope), "
            + "SignedHeaders=\(signedHeaders), "
            + "Signature=\(signature)"

        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(amzDate, forHTTPHeaderField: "X-Amz-Date")
        if let token = credentials.sessionToken, !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-Amz-Security-Token")
        }
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
    }

    // MARK: - Crypto helpers

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func hmac(key: Data, data: Data) -> Data {
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))
        return Data(mac)
    }

    private static func hmacHex(key: Data, data: Data) -> String {
        hmac(key: key, data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func signingKey(secret: String, dateStamp: String, region: String, service: String) -> Data {
        let kDate = hmac(key: Data("AWS4\(secret)".utf8), data: Data(dateStamp.utf8))
        let kRegion = hmac(key: kDate, data: Data(region.utf8))
        let kService = hmac(key: kRegion, data: Data(service.utf8))
        return hmac(key: kService, data: Data("aws4_request".utf8))
    }

    // MARK: - Canonicalization helpers

    /// Percent-encodes a URI path per SigV4 rules (each segment encoded, slashes
    /// preserved). Bedrock model ids contain `:` and `.` which must be encoded.
    private static func encodeURIPath(_ path: String) -> String {
        let segments: [Substring] = path.split(separator: "/", omittingEmptySubsequences: false)
        let encoded: [String] = segments.map { segment in
            encodeURIComponent(String(segment))
        }
        return encoded.joined(separator: "/")
    }

    private static func canonicalQueryString(_ url: URL) -> String {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems, !items.isEmpty else {
            return ""
        }
        var pairs: [(String, String)] = []
        for item in items {
            pairs.append((encodeURIComponent(item.name), encodeURIComponent(item.value ?? "")))
        }
        pairs.sort { lhs, rhs in
            lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
        }
        return pairs.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
    }

    /// RFC 3986 unreserved set: A-Z a-z 0-9 - _ . ~ . Everything else is encoded.
    private static func encodeURIComponent(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    // MARK: - Date formatters

    private static let amzDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f
    }()

    private static let dateStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd"
        return f
    }()
}
