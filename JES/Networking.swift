import Foundation

struct GenerateRequest: Codable {
    let topic: String
}

struct GenerateResponse: Codable {
    let text: String
    let questions: [String]
}

func sendTopic(_ topic: String,
               completion: @escaping (Result<GenerateResponse, Error>) -> Void) {
    guard let url = URL(string: "http://192.168.84.40:8000/generate-test") else {
        return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json; charset=utf-8",
                     forHTTPHeaderField: "Content-Type")

    let body = GenerateRequest(topic: topic)

    do {
        let jsonData = try JSONEncoder().encode(body)
        request.httpBody = jsonData
    } catch {
        completion(.failure(error))
        return
    }

    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
            return
        }

        guard let data = data else {
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "JES",
                                            code: -1,
                                            userInfo: [NSLocalizedDescriptionKey: "No data"])))
            }
            return
        }

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

// MARK: - Multipart Form Data

struct MultipartFormData {
    let boundary: String = "Boundary-\(UUID().uuidString)"
    private var body = Data()

    mutating func addField(name: String, value: String) {
        var field = ""
        field += "--\(boundary)\r\n"
        field += "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
        field += "\(value)\r\n"
        body.append(field.data(using: .utf8)!)
    }

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

    mutating func finalize() {
        let closing = "--\(boundary)--\r\n"
        body.append(closing.data(using: .utf8)!)
    }

    func httpBody() -> Data { body }
}

func submitAnswer(text: String,
                  question: String,
                  handwritingPNGURL: URL,
                  audioWAVURL: URL,
                  completion: @escaping (Result<String, Error>) -> Void) {
    guard let url = URL(string: "http://192.168.84.40:8000/submit-answer") else {
        return
    }

    guard
        let pngData = try? Data(contentsOf: handwritingPNGURL),
        let wavData = try? Data(contentsOf: audioWAVURL)
    else {
        completion(.failure(NSError(domain: "JES",
                                    code: -2,
                                    userInfo: [NSLocalizedDescriptionKey: "Could not read files"])))
        return
    }

    var multipart = MultipartFormData()
    multipart.addField(name: "text", value: text)
    multipart.addField(name: "question", value: question)
    multipart.addFileField(name: "handwriting",
                           filename: "handwriting.png",
                           mimeType: "image/png",
                           fileData: pngData)
    multipart.addFileField(name: "audio",
                           filename: "handwriting.wav",
                           mimeType: "audio/wav",
                           fileData: wavData)
    multipart.finalize()

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("multipart/form-data; boundary=\(multipart.boundary)",
                     forHTTPHeaderField: "Content-Type")
    request.httpBody = multipart.httpBody()

    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        // Collect the feedback from the response
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

        // Optionally inspect status code / response JSON here
        DispatchQueue.main.async { completion(.success(feedback)) }
    }.resume()
}
