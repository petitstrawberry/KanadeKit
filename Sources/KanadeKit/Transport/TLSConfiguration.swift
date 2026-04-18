import Foundation

public struct TLSConfiguration: @unchecked Sendable {
    public let clientIdentity: SecIdentity?
    public let trustedCACertificates: [SecCertificate]?
    public let allowSelfSignedServer: Bool

    public init(
        clientIdentity: SecIdentity? = nil,
        trustedCACertificates: [SecCertificate]? = nil,
        allowSelfSignedServer: Bool = false
    ) {
        self.clientIdentity = clientIdentity
        self.trustedCACertificates = trustedCACertificates
        self.allowSelfSignedServer = allowSelfSignedServer
    }

    public var hasClientIdentity: Bool { clientIdentity != nil }
}

extension TLSConfiguration {
    public static func identityFromPKCS12(data: Data, password: String) throws -> SecIdentity {
        let passphrase = password.isEmpty ? "" : password
        var items: CFArray?
        let status = SecPKCS12Import(data as CFData, [kSecImportExportPassphrase as String: passphrase] as CFDictionary, &items)
        guard status == errSecSuccess, let items = items as? [[String: Any]] else {
            throw KanadeError.tlsError("Failed to import PKCS12: status=\(status)")
        }
        guard let rawIdentity = items.first?[kSecImportItemIdentity as String] else {
            throw KanadeError.tlsError("No identity found in PKCS12")
        }
        return rawIdentity as! SecIdentity
    }

    public static func certificatesFromPEM(_ pemString: String) -> [SecCertificate] {
        let markers = pemString.components(separatedBy: "-----BEGIN CERTIFICATE-----")
        var certificates: [SecCertificate] = []
        for marker in markers.dropFirst() {
            let lines = marker.components(separatedBy: "-----END CERTIFICATE-----")
            guard let b64 = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) else { continue }
            if let cert = SecCertificateCreateWithData(nil, data as CFData) {
                certificates.append(cert)
            }
        }
        return certificates
    }

    public static func certificatesFromDER(_ derData: Data) -> [SecCertificate] {
        guard let cert = SecCertificateCreateWithData(nil, derData as CFData) else { return [] }
        return [cert]
    }
}
