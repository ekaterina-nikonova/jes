import SwiftUI
import PencilKit

struct ContentView: View {
    @State private var cannedText: String = "今日は母の誕生日です。誕生日、おめでとうございます。お母さんは四十五歳ぐらいの歳です。家族といるとしあわせです。母が来ました。ただいま。昨日母に電話しました。お母さんから手紙が来ました。けいたいでしゃしんをとります。あたらし いけいたいはおおきいです。けいたいででんわをします。家族と一緒にいます。来週、母の誕生日パーティーがあります。こうがいでさんぽします。こうがいはとおいけど、たのしいです。お母さんが作ったとろとろのオムライスを食べました。おべんとうを一 つください。おべんとう、あたためましょうか。おさけはあまいです。くすりはにがいです。お母さんは何もしませんでした。今日はさいあくの日でした。今日はダメじゃないです。せいせきがいいので、うれしいです。小さいとき、お母さんはしんせつでした 。あたらしいゆびわをあげます。お母さんはうれしそうです。姉はえいごがとくいです。姉が一人います。先週の誕生日に、姉がおごりでケーキを買いました。姉はえをかくのが上手です。えをかくのはたのしいです。七日は私の誕生日です。二十日は友達の誕 生日です。九日は友達の誕生日です。昨日は友達の誕生日でした。お母さんはおいくつですか。四十五歳です。おおみそかは家族と一緒にいます。かいしゃにいくまえに、でんきをあけます。すわります。おこりました。今日は手がベタベタです。じこはきらい です。かわいいみみがあります。うさぎを愛します。しんぷはしんせつなので、みんながすきです。しんぷはしんせつです。あたまがいいです。やっつ の子供がいます。あかちゃんのとき、よくねました。きれいなけっこんしきでした。しょうしょうおまちください。ゆびわをあげます。今日、よやくを入れます。こわれます。へんにちは休みです。お母さんはいつも優しいです。家族みんなでお祝いします。お母さん、ありがとうございます。"

    @State private var cannedGeneratedQuestions: [String] = [
        "今日は**お母さん**の**誕生日**ですか。",
        "お母さん は**何歳**ぐらいですか。",
        "**姉**は何が**とくい**ですか。",
        "**七日**は**誰**の**誕生日**ですか。"
    ]

    @State private var handwritingDrawing = PKDrawing()
    @State private var previewImage: UIImage?
    @State private var topicText: String = ""

    @State private var imageToShareURL: URL?
    @State private var isShowingShareSheet = false

    @StateObject private var audioRecorder = AudioRecorder()

    @State private var audioToShareURL: URL?
    @State private var isShowingAudioShareSheet = false

    // Networking: getting the text and a list of questions
    @State private var generatedText: String = ""
    @State private var generatedQuestions: [String] = []
    @State private var selectedQuestionIndex: Int? = nil
    @State private var isLoadingTopic = false
    @State private var topicErrorMessage: String? = nil

    // Server configuration
    @AppStorage("serverIP") private var savedIP: String = ""
    @AppStorage("serverPort") private var savedPort: String = ""
    @State private var ipField: String = ""
    @State private var portField: String = ""
    @State private var showSavedConfirmation = false

    private var isServerConfigured: Bool {
        !savedIP.isEmpty && !savedPort.isEmpty
    }

    private var serverBaseURL: String {
        "http://\(savedIP):\(savedPort)"
    }

    // Submit answer
    @State private var isSubmittingAnswer = false
    @State private var submitErrorMessage: String? = nil
    @State private var submitSuccessMessage: String? = nil
    @State private var submitFeedback: String? = nil


    var body: some View {
        ScrollView {
            VStack {
                Text("Japanese Language 🇯🇵 Exercise System")
                    .font(.title)

                // Server configuration
                Text("Provide the IP address and the port of the local web server")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                HStack {
                    TextField("IP address", text: $ipField)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)

                    TextField("Port", text: $portField)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .frame(width: 80)

                    if showSavedConfirmation {
                        Text("Saved")
                            .font(.footnote)
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    } else {
                        Button("Save") {
                            savedIP = ipField.trimmingCharacters(in: .whitespacesAndNewlines)
                            savedPort = portField.trimmingCharacters(in: .whitespacesAndNewlines)
                            withAnimation { showSavedConfirmation = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation { showSavedConfirmation = false }
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(
                            ipField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            portField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }
                }
                .padding(.horizontal)

                Text("Type in a topic for the exercise:")
                    .font(.headline)
                    .opacity(isServerConfigured ? 1 : 0.4)

                HStack {
                    TextField("日本語を使ってください。", text: $topicText)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.send)

                    Button("Send") {
                        let trimmed = topicText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }

                        isLoadingTopic = true
                        topicErrorMessage = nil
                        generatedText = ""
                        generatedQuestions = []

                        generatedText = cannedText
                        generatedQuestions = cannedGeneratedQuestions

                        sendTopic(trimmed, baseURL: serverBaseURL) { result in
                            isLoadingTopic = false
                            switch result {
                            case .success(let response):
                                generatedText = response.text
                                generatedQuestions = response.questions
                            case .failure(let error):
                                topicErrorMessage = error.localizedDescription
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isServerConfigured || topicText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoadingTopic)
                }
                .padding(.horizontal)
                .disabled(!isServerConfigured)
                .opacity(isServerConfigured ? 1 : 0.4)

                if isLoadingTopic {
                    ProgressView("Generating exercise...")
                        .padding(.top, 8)
                }

                if let error = topicErrorMessage {
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                        .font(.footnote)
                        .padding(.top, 4)
                }

                if !generatedText.isEmpty {
                    Text("Generated text:")
                        .font(.headline)
                        .padding(.top, 12)

                    ScrollView {
                        // Try to parse Markdown; fall back to plain text if it fails
                        if let attributed = try? AttributedString(markdown: generatedText) {
                            Text(attributed)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        } else {
                            Text(generatedText)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                    }
                    .frame(minHeight: 200, maxHeight: 300) // ~10+ lines visible, then scroll
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }

                if !generatedQuestions.isEmpty {
                    Text("Questions:")
                        .font(.headline)
                        .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(generatedQuestions.enumerated()), id: \.offset) { index, question in
                            Button {
                                selectedQuestionIndex = index
                                print("Selected question:", question)
                                // TODO: bind this to the JES answer flow
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")

                                    // Markdown rendering for the question
                                    if let attributed = try? AttributedString(markdown: question) {
                                        Text(attributed)
                                            .multilineTextAlignment(.leading)
                                    } else {
                                        Text(question)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(
                                    (selectedQuestionIndex == index)
                                    ? Color.blue.opacity(0.15)
                                    : Color.clear
                                )
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                }

                if (selectedQuestionIndex != nil) {
                    Text("Write the answer below:")
                        .font(.headline)

                    HandwritingCanvas(drawing: $handwritingDrawing)
                        .frame(height: 300)
                        .background(Color.white)
                        .cornerRadius(10)
                        .overlay(JapaneseWritingGrid().allowsHitTesting(false))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                        .padding()
                    // Export Button (saves as PNG)
                    Button("Export as PNG") {
                        let bounds = handwritingDrawing.bounds.insetBy(dx: -10, dy: -10)
                        if !handwritingDrawing.strokes.isEmpty {
                            let image = handwritingDrawing.image(from: bounds,
                                                                 scale: UIScreen.main.scale)
                            let fileURL = saveHandwritingImage(image)

                            // Suggest to export the PNG file
                            previewImage = image
                            imageToShareURL = fileURL
                            isShowingShareSheet = true

                            // TODO: Upload image.pngData() to server later
                        } else {
                            print("No strokes to export")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(handwritingDrawing.strokes.isEmpty)

                    // Clear Button
                    Button("Clear") {
                        handwritingDrawing = PKDrawing()
                    }

                    // Audio recording section
                    Text("Record your spoken answer:")
                        .font(.headline)
                        .padding(.top)


                    HStack {
                        Button(audioRecorder.isRecording ? "Stop Recording" : "Start Recording") {
                            if audioRecorder.isRecording {
                                audioRecorder.stopRecording()
                            } else {
                                audioRecorder.startRecording()
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Export WAV") {
                            if let url = audioRecorder.recordedFileURL {
                                audioToShareURL = url
                                isShowingAudioShareSheet = true
                            } else {
                                print("No recording to export")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(audioRecorder.recordedFileURL == nil)
                    }

                    if let selectedIndex = selectedQuestionIndex {
                        Button("Submit Answer") {
                            guard
                                !generatedText.isEmpty,
                                generatedQuestions.indices.contains(selectedIndex),
                                let pngURL = imageToShareURL,            // from Export as PNG
                                let wavURL = audioRecorder.recordedFileURL
                            else {
                                submitErrorMessage = "Missing text, question, PNG, or WAV."
                                return
                            }

                            isSubmittingAnswer = true
                            submitErrorMessage = nil
                            submitSuccessMessage = nil

                            let question = generatedQuestions[selectedIndex]

                            submitAnswer(text: generatedText,
                                         question: question,
                                         handwritingPNGURL: pngURL,
                                         audioWAVURL: wavURL,
                                         baseURL: serverBaseURL) { result in
                                isSubmittingAnswer = false
                                switch result {
                                case .success(let feedbackText):
                                    submitSuccessMessage = "Answer submitted successfully."
                                    submitFeedback = feedbackText // store server feedback
                                case .failure(let error):
                                    submitErrorMessage = error.localizedDescription
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top)
                        .disabled(isSubmittingAnswer || imageToShareURL == nil || audioRecorder.recordedFileURL == nil)

                        if isSubmittingAnswer {
                            ProgressView("Submitting answer…")
                                .padding(.top, 4)
                        }
                        if let msg = submitErrorMessage {
                            Text("Submit error: \(msg)")
                                .foregroundColor(.red)
                                .font(.footnote)
                                .padding(.top, 4)
                        }
                        if let msg = submitSuccessMessage {
                            Text(msg)
                                .foregroundColor(.green)
                                .font(.footnote)
                                .padding(.top, 4)
                        }

                        // Display feedback
                        if let feedback = submitFeedback {
                            Text("Feedback:")
                                .font(.headline)
                                .padding(.top, 8)

                            ScrollView {
                                Text(feedback)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                            }
                            .frame(minHeight: 120, maxHeight: 200)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                    }

                }
            }
            .padding()
            .sheet(isPresented: $isShowingShareSheet) {
                if let url = imageToShareURL {
                    ShareSheet(items: [url])
                }
            }
            .sheet(isPresented: $isShowingAudioShareSheet) {
                if let url = audioToShareURL {
                    ShareSheet(items: [url])   // handwriting.wav
                }
            }
            .onAppear {
                ipField = savedIP
                portField = savedPort
            }
        }
    }
}

#Preview {
    ContentView()
}
