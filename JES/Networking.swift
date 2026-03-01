import Foundation

// MARK: - Data models for the /generate endpoint

/// The JSON request body sent to the server's `/generate` endpoint.
/// Contains a single `topic` string that the server uses to create a Japanese-language
/// reading exercise (a text passage and comprehension questions).
struct GenerateRequest: Codable {
    let topic: String
}

/// The JSON response returned by the server's `/generate` endpoint.
/// - `text`: A generated Japanese text passage about the requested topic.
/// - `questions`: A list of comprehension questions about the passage that the user
///   must answer by handwriting and speaking.
struct GenerateResponse: Codable {
    let text: String
    let questions: [String]
}

// MARK: - Text Generation Request

/// Sends the user-chosen topic to the server and receives a generated text passage
/// with comprehension questions.
///
/// - Parameters:
///   - topic: The exercise topic string (in Japanese).
///   - baseURL: The scheme + host + port of the local server (e.g. "http://192.168.1.1:8080").
///   - completion: Called on the **main queue** with either the decoded `GenerateResponse`
///     or an `Error` describing what went wrong.
///
/// The request is a simple JSON POST to `<baseURL>/generate`. A 5-minute timeout
/// (`timeoutInterval = 300`) accommodates slow LLM-based generation on the server side.
func sendTopic(_ topic: String,
               baseURL: String,
               completion: @escaping (Result<GenerateResponse, Error>) -> Void) {
    // Build the full endpoint URL
    guard let url = URL(string: "\(baseURL)/generate") else {
        return
    }

    // Configure the HTTP request: POST with JSON body
    var request = URLRequest(url: url)
    request.timeoutInterval = 300
    request.httpMethod = "POST"
    request.setValue("application/json; charset=utf-8",
                     forHTTPHeaderField: "Content-Type")

    // Encode the topic into the JSON request body
    let body = GenerateRequest(topic: topic)

    do {
        let jsonData = try JSONEncoder().encode(body)
        request.httpBody = jsonData
    } catch {
        completion(.failure(error))
        return
    }

    // Fire the network request asynchronously
    URLSession.shared.dataTask(with: request) { data, response, error in
        // Forward any transport-level error (timeout, no connectivity, etc.)
        if let error = error {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
            return
        }

        // Ensure we actually received response data
        guard let data = data else {
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "JES",
                                            code: -1,
                                            userInfo: [NSLocalizedDescriptionKey: "No data"])))
            }
            return
        }

        // Decode the JSON response into our `GenerateResponse` model
        do {
            let decoded = try JSONDecoder().decode(GenerateResponse.self, from: data)
            DispatchQueue.main.async {
                completion(.success(decoded))
            }
        } catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
    }.resume()
}

// MARK: - Multipart form data

/// A helper for building `multipart/form-data` HTTP request bodies.
///
/// Multipart encoding is needed for the `/submit-answer` endpoint because the submission
/// includes both plain-text fields (the generated passage, the selected question) and
/// binary file attachments (the handwriting PNG and the spoken-answer WAV).
///
/// Usage:
/// 1. Call `addField(name:value:)` for each text field.
/// 2. Call `addFileField(name:filename:mimeType:fileData:)` for each file.
/// 3. Call `finalize()` to append the closing boundary.
/// 4. Pass `httpBody()` as the request's body and set the Content-Type header to
///    `multipart/form-data; boundary=<boundary>`.
struct MultipartFormData {
    /// A unique boundary string that separates each part of the multipart body.
    /// Generated once per instance using a UUID to avoid collisions.
    let boundary: String = "Boundary-\(UUID().uuidString)"

    /// The accumulated raw bytes of the multipart body being built.
    private var body = Data()

    /// Appends a plain-text form field to the multipart body.
    /// - Parameters:
    ///   - name: The field name (as expected by the server).
    ///   - value: The field's text value.
    mutating func addField(name: String, value: String) {
        var field = ""
        field += "--\(boundary)\r\n"
        field += "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
        field += "\(value)\r\n"
        body.append(field.data(using: .utf8)!)
    }

    /// Appends a binary file attachment to the multipart body.
    /// - Parameters:
    ///   - name: The form field name the server expects for this file.
    ///   - filename: The filename to include in the Content-Disposition header.
    ///   - mimeType: The MIME type of the file (e.g. "image/png", "audio/wav").
    ///   - fileData: The raw bytes of the file to attach.
    mutating func addFileField(name: String,
                               filename: String,
                               mimeType: String,
                               fileData: Data) {
        var field = ""
        field += "--\(boundary)\r\n"
        field += "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
        field += "Content-Type: \(mimeType)\r\n\r\n"
        body.append(field.data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
    }

    /// Appends the closing boundary marker (`--<boundary>--`), signaling the end of the
    /// multipart body. Must be called after all fields and files have been added.
    mutating func finalize() {
        let closing = "--\(boundary)--\r\n"
        body.append(closing.data(using: .utf8)!)
    }

    /// Returns the fully assembled multipart body data, ready to be set as `request.httpBody`.
    func httpBody() -> Data { body }
}

// MARK: - Answer submission

/// Submits the user's answer to the server for grading.
///
/// The submission is sent as a `multipart/form-data` POST to `<baseURL>/submit-answer`
/// and includes four parts:
/// 1. `text` — the generated Japanese passage (so the server has context).
/// 2. `selected_question` — the comprehension question the user chose to answer.
/// 3. `handwritten` — a PNG image of the user's handwritten answer from the canvas.
/// 4. `spoken` — a WAV audio recording of the user reading their answer aloud.
///
/// - Parameters:
///   - text: The generated text passage the exercise is based on.
///   - question: The specific comprehension question being answered.
///   - handwritingPNGURL: Local file URL of the exported handwriting PNG.
///   - audioWAVURL: Local file URL of the recorded WAV audio.
///   - baseURL: The scheme + host + port of the local server.
///   - completion: Called on the **main queue** with either the server's feedback string
///     or an `Error`.
func submitAnswer(text: String,
                  question: String,
                  handwritingPNGURL: URL,
                  audioWAVURL: URL,
                  baseURL: String,
                  completion: @escaping (Result<String, Error>) -> Void) {
    // Build the full endpoint URL
    guard let url = URL(string: "\(baseURL)/submit-answer") else {
        return
    }

    // Read the handwriting PNG and audio WAV files into memory
    guard
        let pngData = try? Data(contentsOf: handwritingPNGURL),
        let wavData = try? Data(contentsOf: audioWAVURL)
    else {
        completion(.failure(NSError(domain: "JES",
                                    code: -2,
                                    userInfo: [NSLocalizedDescriptionKey: "Could not read files"])))
        return
    }

    // Assemble the multipart body with two text fields and two file attachments
    var multipart = MultipartFormData()
    multipart.addField(name: "text", value: text)
    multipart.addField(name: "selected_question", value: question)
    multipart.addFileField(name: "handwritten",
                           filename: "handwriting.png",
                           mimeType: "image/png",
                           fileData: pngData)
    multipart.addFileField(name: "spoken",
                           filename: "handwriting.wav",
                           mimeType: "audio/wav",
                           fileData: wavData)
    multipart.finalize()

    // Configure the HTTP request with the multipart content type and body
    var request = URLRequest(url: url)
    request.timeoutInterval = 300
    request.httpMethod = "POST"
    request.setValue("multipart/form-data; boundary=\(multipart.boundary)",
                     forHTTPHeaderField: "Content-Type")
    request.httpBody = multipart.httpBody()

    // Fire the network request and handle the server's feedback response
    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        // The server returns plain-text feedback about the user's answer
        guard let data = data,
              let feedback = String(data: data, encoding: .utf8) else {
            DispatchQueue.main.async {
                completion(.failure(
                    NSError(domain: "JES",
                            code: -3,
                            userInfo: [NSLocalizedDescriptionKey: "No feedback text"])
                ))
            }
            return
        }

        // Deliver the feedback string to the caller on the main queue for UI updates
        DispatchQueue.main.async { completion(.success(feedback)) }
    }.resume()
}
