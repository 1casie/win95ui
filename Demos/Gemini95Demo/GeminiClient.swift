import Foundation
import Network

/// A parsed Gemini response: `<status><SP><meta>\r\n<body>`.
struct GeminiResponse: Sendable {
    let status: Int          // two-digit status code
    let meta: String         // everything after the status space
    let body: Data           // empty for non-2x responses
    var mime: String {       // first token of meta, lowercased, sans params
        meta.split(separator: ";").first?
            .trimmingCharacters(in: .whitespaces).lowercased() ?? ""
    }
}

enum GeminiError: LocalizedError {
    case badURL(String)
    case noResponse
    case malformedHeader(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .badURL(let s):        return "Bad URL: \(s)"
        case .noResponse:           return "The server closed the connection without responding."
        case .malformedHeader(let s): return "Malformed response header: \(s)"
        case .transport(let s):     return s
        }
    }
}

/// Minimal Gemini protocol client over Network.framework.
/// TLS is mandatory; certificate verification is disabled because Gemini
/// culture runs on self-signed certs and TOFU — and because it's 1995.
final class GeminiClient: @unchecked Sendable {
    private let queue = DispatchQueue(label: "gemini95.net")

    /// Fetch `url` (must be gemini://). Completion fires on the main queue.
    func fetch(_ url: URL, completion: @escaping @MainActor (Result<GeminiResponse, Error>) -> Void) {
        guard url.scheme?.lowercased() == "gemini",
              let host = url.host, !host.isEmpty else {
            let result: Result<GeminiResponse, Error> = .failure(GeminiError.badURL(url.absoluteString))
            DispatchQueue.main.async { completion(result) }
            return
        }
        let port = UInt16(url.port ?? 1965)

        let tlsOpts = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(tlsOpts.securityProtocolOptions,
                                              { _, _, complete in complete(true) }, queue)
        let params = NWParameters(tls: tlsOpts)
        params.allowLocalEndpointReuse = true

        let conn = NWConnection(host: NWEndpoint.Host(host),
                                port: NWEndpoint.Port(rawValue: port)!,
                                using: params)

        /// Mutable per-request state, confined to `queue`.
        final class State: @unchecked Sendable {
            var received = Data()
            var finished = false
        }
        let state = State()

        let finish: @Sendable (Result<GeminiResponse, Error>) -> Void = { result in
            self.queue.async {
                guard !state.finished else { return }
                state.finished = true
                conn.cancel()
                DispatchQueue.main.async { completion(result) }
            }
        }

        conn.stateUpdateHandler = { connState in
            switch connState {
            case .ready:
                // Request: absolute URL + CRLF, max 1024 bytes per spec.
                var req = url.absoluteString
                if req.utf8.count > 1024 { req = String(req.prefix(1024)) }
                conn.send(content: (req + "\r\n").data(using: .utf8),
                          completion: .contentProcessed { err in
                    if let err { finish(.failure(GeminiError.transport(err.localizedDescription))) }
                })
                receive()
            case .failed(let err):
                finish(.failure(GeminiError.transport(err.localizedDescription)))
            case .cancelled:
                finish(.failure(GeminiError.transport("Connection cancelled.")))
            default:
                break
            }
        }

        @Sendable func receive() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { data, _, complete, err in
                if let data { state.received.append(data) }
                if let err {
                    finish(.failure(GeminiError.transport(err.localizedDescription)))
                    return
                }
                if complete {
                    finish(Self.parse(state.received).mapError { $0 })
                    return
                }
                receive()
            }
        }

        conn.start(queue: queue)
    }

    /// Split header from body at the first CRLF and decode the status line.
    static func parse(_ data: Data) -> Result<GeminiResponse, GeminiError> {
        guard let range = data.range(of: Data([0x0D, 0x0A])) else {
            return .failure(data.isEmpty ? .noResponse
                            : .malformedHeader("no CRLF in \(data.count) bytes"))
        }
        let headerData = data[..<range.lowerBound]
        guard let header = String(data: headerData, encoding: .utf8), header.count >= 2 else {
            return .failure(.malformedHeader("undecodable header"))
        }
        guard let status = Int(header.prefix(2)), (10...69).contains(status) else {
            return .failure(.malformedHeader(header))
        }
        var meta = ""
        if header.count > 3 { meta = String(header.dropFirst(3)) }
        return .success(GeminiResponse(status: status, meta: meta,
                                       body: data[range.upperBound...]))
    }
}
