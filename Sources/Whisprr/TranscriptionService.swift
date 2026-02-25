import Foundation

final class TranscriptionService {
    private let model = "gemini-3-flash-preview"

    func transcribe(audioFileURL: URL, apiKey: String, completion: @escaping (Result<String, Error>) -> Void) {
        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioFileURL)
        } catch {
            completion(.failure(error))
            return
        }

        let base64Audio = audioData.base64EncodedString()

        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        guard let url = URL(string: endpoint) else {
            completion(.failure(TranscriptionError.invalidURL))
            return
        }

        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    [
                        "inline_data": [
                            "mime_type": "audio/wav",
                            "data": base64Audio,
                        ]
                    ],
                    [
                        "text": "Transcribe this audio exactly as spoken. Output only the transcription, no commentary."
                    ],
                ]
            ]]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(TranscriptionError.serializationFailed))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = jsonData

        let masked = String(apiKey.prefix(10)) + "..." + String(apiKey.suffix(4))
        print("[Whisprr] API key: \(masked) (length=\(apiKey.count))")
        print("[Whisprr] Request body size: \(jsonData.count) bytes")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse {
                print("[Whisprr] HTTP status: \(httpResponse.statusCode)")
            }

            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(TranscriptionError.noData))
                return
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                print("[Whisprr] Error response body: \(body)")

                if httpResponse.statusCode == 429 {
                    completion(.failure(TranscriptionError.quotaExceeded))
                    return
                }
            }

            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(.failure(TranscriptionError.invalidResponse))
                    return
                }

                // Check for API error
                if let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String
                {
                    let code = error["code"] as? Int
                    if code == 429 {
                        completion(.failure(TranscriptionError.quotaExceeded))
                    } else {
                        completion(.failure(TranscriptionError.apiError(message)))
                    }
                    return
                }

                // Extract text: candidates[0].content.parts[0].text
                guard let candidates = json["candidates"] as? [[String: Any]],
                      let first = candidates.first,
                      let content = first["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]],
                      let text = parts.first?["text"] as? String
                else {
                    completion(.failure(TranscriptionError.invalidResponse))
                    return
                }

                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    completion(.failure(TranscriptionError.emptyTranscription))
                } else {
                    completion(.success(trimmed))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}

enum TranscriptionError: LocalizedError {
    case invalidURL
    case serializationFailed
    case noData
    case invalidResponse
    case emptyTranscription
    case apiError(String)
    case quotaExceeded

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL"
        case .serializationFailed: return "Failed to build request"
        case .noData: return "No response data"
        case .invalidResponse: return "Unexpected API response format"
        case .emptyTranscription: return "No speech detected"
        case .apiError(let msg): return "API error: \(msg)"
        case .quotaExceeded: return "Gemini API quota exceeded. Check billing at ai.google.dev or wait for quota reset."
        }
    }
}
