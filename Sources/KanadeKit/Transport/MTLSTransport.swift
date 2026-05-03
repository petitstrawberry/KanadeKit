import Foundation
import Network
@preconcurrency import Starscream

final class MTLSTransport: Transport, @unchecked Sendable {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.kanade.mtls.transport", attributes: [])
    private weak var delegate: TransportEventClient?
    private var isRunning = false
    private let configuration: TLSConfiguration

    var usingTLS: Bool { true }

    init(configuration: TLSConfiguration) {
        self.configuration = configuration
    }

    func register(delegate: TransportEventClient) {
        self.delegate = delegate
    }

    func connect(url: URL, timeout: Double, certificatePinning: CertificatePinning?) {
        guard let host = url.host else {
            delegate?.connectionChanged(state: .failed(KanadeError.tlsError("Invalid URL: no host")))
            return
        }

        let port = url.port ?? 443

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.connectionTimeout = Int(timeout.rounded(.up))

        let tlsOptions = NWProtocolTLS.Options()
        configureTLS(tlsOptions: tlsOptions, host: host, certificatePinning: certificatePinning)

        let parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            delegate?.connectionChanged(state: .failed(KanadeError.tlsError("Invalid port: \(port)")))
            return
        }

        let conn = NWConnection(
            host: NWEndpoint.Host.name(host, nil),
            port: nwPort,
            using: parameters
        )
        connection = conn
        start()
    }

    func disconnect() {
        isRunning = false
        connection?.cancel()
        connection = nil
    }

    func write(data: Data, completion: @escaping ((Error?) -> ())) {
        connection?.send(content: data, completion: .contentProcessed { error in
            completion(error)
        })
    }

    private func configureTLS(
        tlsOptions: NWProtocolTLS.Options,
        host: String,
        certificatePinning: CertificatePinning?
    ) {
        let config = configuration

        if let identity = config.clientIdentity {
            if let secIdentity = sec_identity_create(identity) {
                sec_protocol_options_set_local_identity(
                    tlsOptions.securityProtocolOptions,
                    secIdentity
                )
            }
        }

        let trustedCerts = config.trustedCACertificates
        let allowSelfSigned = config.allowSelfSignedServer

        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, sec_trust, verify_complete in
                let trust = sec_trust_copy_ref(sec_trust).takeRetainedValue()

                if let trustedCerts, !trustedCerts.isEmpty {
                    SecTrustSetAnchorCertificates(trust, trustedCerts as CFArray)
                    SecTrustSetAnchorCertificatesOnly(trust, true)
                } else if allowSelfSigned {
                    verify_complete(false)
                    return
                }

                if let pinner = certificatePinning {
                    pinner.evaluateTrust(trust: trust, domain: host) { state in
                        switch state {
                        case .success:
                            verify_complete(true)
                        case .failed:
                            verify_complete(false)
                        }
                    }
                    return
                }

                var error: CFError?
                let result = SecTrustEvaluateWithError(trust, &error)
                verify_complete(result)
            },
            queue
        )
    }

    private func start() {
        guard let conn = connection else { return }

        conn.stateUpdateHandler = { [weak self] newState in
            switch newState {
            case .ready:
                self?.delegate?.connectionChanged(state: .connected)
            case .waiting:
                self?.delegate?.connectionChanged(state: .waiting)
            case .cancelled:
                self?.delegate?.connectionChanged(state: .cancelled)
            case .failed(let error):
                self?.delegate?.connectionChanged(state: .failed(error))
            case .setup, .preparing:
                break
            @unknown default:
                break
            }
        }

        conn.viabilityUpdateHandler = { [weak self] isViable in
            self?.delegate?.connectionChanged(state: .viability(isViable))
        }

        conn.betterPathUpdateHandler = { [weak self] isBetter in
            self?.delegate?.connectionChanged(state: .shouldReconnect(isBetter))
        }

        conn.start(queue: queue)
        isRunning = true
        readLoop()
    }

    private func readLoop() {
        guard isRunning else { return }
        connection?.receive(minimumIncompleteLength: 2, maximumLength: 4096) { [weak self] data, context, isComplete, error in
            guard let self else { return }
            if let data {
                self.delegate?.connectionChanged(state: .receive(data))
            }

            if let context, context.isFinal, isComplete {
                if let delegate = self.delegate {
                    delegate.connectionChanged(state: .peerClosed)
                } else {
                    self.disconnect()
                }
                return
            }

            if error == nil {
                self.readLoop()
            }
        }
    }
}
