import Foundation
import Network

/// Tiny localhost-only HTTP server.
///   POST /hook  - Claude Code hook JSON (Stop event) on the body
///   POST /say   - plain text to speak
///   POST /stop  - stop talking
final class HookServer {
    static let defaultPort: UInt16 = 5151
    private let listener: NWListener

    init?(port: UInt16) {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!) else {
            NSLog("TalkingFace: could not listen on port \(port)")
            return nil
        }
        self.listener = listener
    }

    func start() {
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state { NSLog("TalkingFace: listener failed: \(error)") }
        }
        listener.newConnectionHandler = { connection in
            connection.start(queue: .main)
            Self.receive(on: connection, buffer: Data())
        }
        listener.start(queue: .main)
    }

    private static func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { data, _, isComplete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = Request(buffer) {
                let status = MainActor.assumeIsolated { handle(request) }
                let response = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            } else if isComplete || error != nil || buffer.count > 10_000_000 {
                connection.cancel()
            } else {
                receive(on: connection, buffer: buffer)
            }
        }
    }

    @MainActor
    private static func handle(_ request: Request) -> String {
        switch (request.method, request.path) {
        case ("POST", "/say"):
            Speaker.shared.speak(String(decoding: request.body, as: UTF8.self))
        case ("POST", "/stop"):
            Speaker.shared.stop()
        case ("POST", "/hook"):
            guard let json = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] else {
                return "400 Bad Request"
            }
            if let text = ClaudeHook.replyText(from: json) { Speaker.shared.speak(text) }
        default:
            return "404 Not Found"
        }
        return "200 OK"
    }

    private struct Request {
        let method: String
        let path: String
        let body: Data

        /// Returns nil until the full request (headers + Content-Length body) has arrived.
        init?(_ data: Data) {
            guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
            let head = String(decoding: data[..<headerEnd.lowerBound], as: UTF8.self)
            let lines = head.components(separatedBy: "\r\n")
            let parts = lines.first?.split(separator: " ") ?? []
            guard parts.count >= 2 else { return nil }
            var length = 0
            for line in lines.dropFirst() where line.lowercased().hasPrefix("content-length:") {
                length = Int(line.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
            let bodyStart = headerEnd.upperBound
            guard data.count - bodyStart >= length else { return nil }
            method = String(parts[0])
            path = String(parts[1])
            body = data.subdata(in: bodyStart..<(bodyStart + length))
        }
    }
}

enum ClaudeHook {
    /// The final answer text from a Claude Code Stop hook payload.
    static func replyText(from json: [String: Any]) -> String? {
        if let event = json["hook_event_name"] as? String, event != "Stop" { return nil }
        if let text = json["last_assistant_message"] as? String, !text.isEmpty { return text }
        guard let path = json["transcript_path"] as? String else { return nil }
        return lastAssistantText(transcriptPath: path)
    }

    /// Fallback: read the transcript and take the text after the last tool call.
    static func lastAssistantText(transcriptPath: String) -> String? {
        guard let contents = try? String(contentsOfFile: transcriptPath, encoding: .utf8) else { return nil }
        var texts: [String] = []
        for line in contents.split(separator: "\n").reversed() {
            guard let entry = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = entry["type"] as? String else { continue }
            if type == "user" { if texts.isEmpty { continue } else { break } }
            guard type == "assistant",
                  let blocks = (entry["message"] as? [String: Any])?["content"] as? [[String: Any]] else { continue }
            if !texts.isEmpty, blocks.contains(where: { $0["type"] as? String == "tool_use" }) { break }
            for block in blocks.reversed() where block["type"] as? String == "text" {
                if let text = block["text"] as? String { texts.insert(text, at: 0) }
            }
        }
        return texts.isEmpty ? nil : texts.joined(separator: "\n\n")
    }
}
