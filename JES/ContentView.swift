import SwiftUI
import PencilKit

/// The main view of the Japanese Exercise System (JES).
///
/// This view orchestrates the entire exercise workflow:
/// 1. **Server configuration**: the user enters the IP/port of the local JES web server.
/// 2. **Topic entry**: the user types a topic (in Japanese) and sends it to the server.
/// 3. **Reading**: the server-generated Japanese text passage is displayed.
/// 4. **Question selection**: comprehension questions are listed; the user taps one.
/// 5. **Handwriting**: the user writes an answer on a PencilKit canvas and exports it as PNG.
/// 6. **Speaking**: the user records a spoken version of the answer as a WAV file.
/// 7. **Submission**: the handwriting PNG, audio WAV, selected question, and generated text
///    are sent to the server, which returns feedback.
/// 8. **Reset**: clears all state so the user can start a new exercise.
///
struct ContentView: View {

    // MARK: - Handwriting canvas state

    /// The current PencilKit drawing. Reset to an empty `PKDrawing()` on "Clear" or "Reset".
    @State private var handwritingDrawing = PKDrawing()

    /// A snapshot of the handwriting canvas as a `UIImage`, populated when the user taps
    /// "Export as PNG". Used to preview the captured image for debugging.
    @State private var previewImage: UIImage?

    /// The topic the user types into the text field before sending to the server.
    @State private var topicText: String = ""

    // MARK: - Share sheet state for the handwriting PNG

    /// The file URL of the exported handwriting PNG (in the Documents directory).
    /// Also used as the source for the multipart submission.
    @State private var imageToShareURL: URL?

    /// Controls presentation of the system share sheet for the handwriting PNG.
    @State private var isShowingShareSheet = false

    // MARK: - Audio recording

    /// The audio recorder instance, kept alive as a `@StateObject` so it persists across
    /// view re-renders. Provides `isRecording` and `recordedFileURL` properties.
    @StateObject private var audioRecorder = AudioRecorder()

    /// The file URL of the recorded WAV, set when the user taps "Export WAV".
    @State private var audioToShareURL: URL?

    /// Controls presentation of the system share sheet for the audio WAV.
    @State private var isShowingAudioShareSheet = false

    // MARK: - Generated exercise content (from the server)

    /// The Japanese text passage returned by the server's `/generate` endpoint.
    @State private var generatedText: String = ""

    /// The list of comprehension questions returned alongside the generated text.
    @State private var generatedQuestions: [String] = []

    /// The index of the question the user has selected, or `nil` if none is selected yet.
    /// Selecting a question reveals the handwriting canvas and audio recording sections.
    @State private var selectedQuestionIndex: Int? = nil

    /// Whether the app is currently waiting for the server to generate the exercise content.
    /// Controls the visibility of the spinner.
    @State private var isLoadingTopic = false

    /// An error message to display if the `/generate` request fails.
    @State private var topicErrorMessage: String? = nil

    // MARK: - Server configuration (persisted across launches via @AppStorage)

    /// The server IP address, persisted in UserDefaults under the key "serverIP".
    @AppStorage("serverIP") private var savedIP: String = ""

    /// The server port number, persisted in UserDefaults under the key "serverPort".
    @AppStorage("serverPort") private var savedPort: String = ""

    /// Local editing state for the IP text field. Synced from `savedIP` in `onAppear`.
    @State private var ipField: String = ""

    /// Local editing state for the port text field. Synced from `savedPort` in `onAppear`.
    @State private var portField: String = ""

    /// Briefly set to `true` to flash a "Saved" confirmation after the user saves the config.
    @State private var showSavedConfirmation = false

    /// Whether the server configuration `DisclosureGroup` is expanded.
    @State private var isServerConfigExpanded = true

    /// Returns `true` when both IP and port have been saved, indicating the server is configured.
    private var isServerConfigured: Bool {
        !savedIP.isEmpty && !savedPort.isEmpty
    }

    /// Constructs the base URL for server requests from the saved IP and port.
    private var serverBaseURL: String {
        "http://\(savedIP):\(savedPort)"
    }

    // MARK: - Answer submission state

    /// Whether the app is currently waiting for the server to process the submitted answer.
    @State private var isSubmittingAnswer = false

    /// An error message to display if the `/submit-answer` request fails.
    @State private var submitErrorMessage: String? = nil

    /// A success message shown after the answer is submitted successfully.
    @State private var submitSuccessMessage: String? = nil

    /// The feedback text returned by the server after assessing the user's answer.
    @State private var submitFeedback: String? = nil


    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack {
                // ── App header with icon and title ──
                HStack(spacing: 12) {
                    Image("HeaderIcon")
                        .resizable()
                        .frame(width: 48, height: 48)
                        .cornerRadius(8)
                    Text("Japanese Language Exercise System")
                        .font(.system(size: 36, weight: .bold))
                }

                // ── Server configuration section ──
                // A collapsible section where the user enters the IP and port of the
                // local JES web server. The label shows the current config or a warning
                // if not yet configured.
                DisclosureGroup(isExpanded: $isServerConfigExpanded) {
                    Text("Provide the IP address and the port of the local web server")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)

                    HStack {
                        // IP address text field (decimal pad keyboard for digits and dots)
                        TextField("IP address", text: $ipField)
                            .font(.system(size: 22))
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)

                        // Port text field (numeric keyboard, fixed width)
                        TextField("Port", text: $portField)
                            .font(.system(size: 22))
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                            .frame(width: 100)

                        // After saving, briefly show "Saved" in green, then revert to the button
                        if showSavedConfirmation {
                            Text("Saved")
                                .font(.system(size: 18))
                                .foregroundStyle(.green)
                                .transition(.opacity)
                        } else {
                            // Save button: persists IP/port to @AppStorage (UserDefaults)
                            Button("Save") {
                                savedIP = ipField.trimmingCharacters(in: .whitespacesAndNewlines)
                                savedPort = portField.trimmingCharacters(in: .whitespacesAndNewlines)
                                // Animate a brief "Saved" confirmation that auto-dismisses
                                withAnimation { showSavedConfirmation = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    withAnimation { showSavedConfirmation = false }
                                }
                            }
                            .font(.system(size: 22))
                            .buttonStyle(.bordered)
                            .disabled(
                                ipField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                portField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            )
                        }
                    }
                } label: {
                    // Disclosure group label shows the current server address or a red warning
                    if isServerConfigured {
                        Text("Server: \(savedIP):\(savedPort)")
                            .font(.system(size: 20))
                    } else {
                        Text("Server: not configured")
                            .font(.system(size: 20))
                            .foregroundStyle(.red)
                    }
                }
                .font(.system(size: 20))
                .padding(.horizontal)

                // ── Topic entry section ──
                // The user types a topic (ideally in Japanese; the Japanese keyboard layout is required)
                // and taps "Send" to request  exercise content from the server.
                // Disabled until the server is configured.
                Text("Type in a topic for the exercise:")
                    .font(.system(size: 26, weight: .semibold))
                    .opacity(isServerConfigured ? 1 : 0.4)

                HStack {
                    // Topic text field with Japanese placeholder text ("Please use Japanese.")
                    TextField("日本語を使ってください。", text: $topicText)
                        .font(.system(size: 22))
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.send)

                    // Send button: fires the /generate request to the server
                    Button("Send") {
                        let trimmed = topicText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }

                        // Reset UI state before starting the request
                        isLoadingTopic = true
                        topicErrorMessage = nil
                        generatedText = ""
                        generatedQuestions = []

                        // Call the networking function to POST the topic to the server
                        sendTopic(trimmed, baseURL: serverBaseURL) { result in
                            isLoadingTopic = false
                            switch result {
                            case .success(let response):
                                generatedText = response.text
                                generatedQuestions = response.questions
                            // Show the error message if the request fails.
                            case .failure(let error):
                                topicErrorMessage = error.localizedDescription
                            }
                        }
                    }
                    .font(.system(size: 22))
                    .buttonStyle(.borderedProminent)
                    .disabled(!isServerConfigured || topicText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoadingTopic)
                }
                .padding(.horizontal)
                .disabled(!isServerConfigured)
                .opacity(isServerConfigured ? 1 : 0.4)

                // Show a spinner while waiting for the server to generate the exercise
                if isLoadingTopic {
                    ProgressView("Generating exercise...")
                        .padding(.top, 8)
                }

                // Display any error from the /generate request
                if let error = topicErrorMessage {
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                        .font(.system(size: 18))
                        .padding(.top, 4)
                }

                // ── Generated text passage ──
                // Once the server responds, display the Japanese text passage in a
                // scrollable container. Markdown formatting is attempted first for
                // rich text (bold, furigana hints, etc.), with plain text as a fallback.
                if !generatedText.isEmpty {
                    Text("Generated text:")
                        .font(.system(size: 26, weight: .semibold))
                        .padding(.top, 12)

                    ScrollView {
                        // Try to parse Markdown; fall back to plain text if it fails
                        if let attributed = try? AttributedString(markdown: generatedText) {
                            Text(attributed)
                                .font(.system(size: 24))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        } else {
                            Text(generatedText)
                                .font(.system(size: 24))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                    }
                    .frame(minHeight: 200, maxHeight: 300) // about 10 top lines visible, then scroll
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }

                // ── Comprehension questions ──
                // Each question is rendered as a tappable button. Tapping a question
                // highlights it with a blue background and sets `selectedQuestionIndex`,
                // which reveals the handwriting and audio recording sections below.
                if !generatedQuestions.isEmpty {
                    Text("Questions:")
                        .font(.system(size: 26, weight: .semibold))
                        .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(generatedQuestions.enumerated()), id: \.offset) { index, question in
                            Button {
                                // Mark this question as the one the user will answer
                                selectedQuestionIndex = index
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")  // bullet
                                        .font(.system(size: 24))

                                    // Render the question with Markdown if possible
                                    if let attributed = try? AttributedString(markdown: question) {
                                        Text(attributed)
                                            .font(.system(size: 24))
                                            .multilineTextAlignment(.leading)
                                    } else {
                                        Text(question)
                                            .font(.system(size: 24))
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                // Highlight the currently selected question
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

                // ── Answer section ──
                // (shown only after a question is selected)
                if (selectedQuestionIndex != nil) {

                    // ── Handwriting canvas ──
                    // The PencilKit canvas with a writing grid overlay lets the
                    // user write the answer by hand using Apple Pencil.
                    Text("Write the answer below:")
                        .font(.system(size: 26, weight: .semibold))

                    HandwritingCanvas(drawing: $handwritingDrawing)
                        .frame(height: 300)
                        .background(Color.white)
                        .cornerRadius(10)
                        // Overlay the writing grid; hit testing disabled so pencil
                        // strokes pass through to the canvas underneath.
                        .overlay(JapaneseWritingGrid().allowsHitTesting(false))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                        .padding()

                    // Export button: renders the drawing as a PNG image, saves it to
                    // the Documents directory, and presents the share sheet.
                    Button("Export as PNG") {
                        // Add a small margin around the drawing bounds for the export
                        let bounds = handwritingDrawing.bounds.insetBy(dx: -10, dy: -10)
                        if !handwritingDrawing.strokes.isEmpty {
                            let image = handwritingDrawing.image(from: bounds,
                                                                 scale: UIScreen.main.scale)
                            let fileURL = saveHandwritingImage(image)

                            // Store references for the share sheet and later submission
                            previewImage = image
                            imageToShareURL = fileURL
                            isShowingShareSheet = true
                        } else {
                            print("No strokes to export")
                        }
                    }
                    .font(.system(size: 22))
                    .buttonStyle(.borderedProminent)
                    .disabled(handwritingDrawing.strokes.isEmpty)

                    // Clear button: resets the canvas to a blank state
                    Button("Clear") {
                        handwritingDrawing = PKDrawing()
                    }
                    .font(.system(size: 22))

                    // ── Audio recording section ──
                    // The user records the audio of reading the answer aloud.
                    // The recording is saved as a WAV file for submission.
                    Text("Record your spoken answer:")
                        .font(.system(size: 26, weight: .semibold))
                        .padding(.top)


                    HStack {
                        // Toggle recording on/off; button label updates based on state
                        Button(audioRecorder.isRecording ? "Stop Recording" : "Start Recording") {
                            if audioRecorder.isRecording {
                                audioRecorder.stopRecording()
                            } else {
                                audioRecorder.startRecording()
                            }
                        }
                        .font(.system(size: 22))
                        .buttonStyle(.borderedProminent)

                        // Export button: presents a share sheet for the recorded WAV file
                        Button("Export WAV") {
                            if let url = audioRecorder.recordedFileURL {
                                audioToShareURL = url
                                isShowingAudioShareSheet = true
                            } else {
                                print("No recording to export")
                            }
                        }
                        .font(.system(size: 22))
                        .buttonStyle(.bordered)
                        .disabled(audioRecorder.recordedFileURL == nil)
                    }

                    // ── Submit answer section ──
                    // Only shown when a question is selected. Sends the generated text,
                    // selected question, handwriting PNG, and audio WAV to the server
                    // for grading via the /submit-answer endpoint.
                    if let selectedIndex = selectedQuestionIndex {
                        Button("Submit Answer") {
                            // Validate that all required pieces are present
                            guard
                                !generatedText.isEmpty,
                                generatedQuestions.indices.contains(selectedIndex),
                                let pngURL = imageToShareURL,            // from Export as PNG
                                let wavURL = audioRecorder.recordedFileURL
                            else {
                                submitErrorMessage = "Missing text, question, PNG, or WAV."
                                return
                            }

                            // Reset submission state and start the request
                            isSubmittingAnswer = true
                            submitErrorMessage = nil
                            submitSuccessMessage = nil

                            // Get hold of the content of the selected question
                            let question = generatedQuestions[selectedIndex]

                            // Send all four pieces to the server as a multipart form POST
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
                        .font(.system(size: 22))
                        .buttonStyle(.borderedProminent)
                        .padding(.top)
                        // Disabled until both the PNG and WAV are ready, or while submitting
                        .disabled(isSubmittingAnswer || imageToShareURL == nil || audioRecorder.recordedFileURL == nil)

                        // Show a spinner while the answer is being submitted
                        if isSubmittingAnswer {
                            ProgressView("Submitting answer…")
                                .padding(.top, 4)
                        }
                        // Display any submission error in red
                        if let msg = submitErrorMessage {
                            Text("Submit error: \(msg)")
                                .foregroundColor(.red)
                                .font(.system(size: 18))
                                .padding(.top, 4)
                        }
                        // Display submission success in green
                        if let msg = submitSuccessMessage {
                            Text(msg)
                                .foregroundColor(.green)
                                .font(.system(size: 18))
                                .padding(.top, 4)
                        }

                        // ── Server feedback display ──
                        // After the server assesses the answer, the feedback text is shown
                        // in a scrollable gray box.
                        if let feedback = submitFeedback {
                            Text("Feedback:")
                                .font(.system(size: 26, weight: .semibold))
                                .padding(.top, 8)

                            ScrollView {
                                Text(feedback)
                                    .font(.system(size: 24))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                            }
                            .frame(minHeight: 150, maxHeight: 250)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                    }

                }

                // ── Reset button ──
                // Clears all state (drawing, text, questions, recordings, errors, feedback),
                // so the user can start an entirely new exercise from scratch.
                Button("Reset") {
                    handwritingDrawing = PKDrawing()
                    previewImage = nil
                    topicText = ""
                    imageToShareURL = nil
                    isShowingShareSheet = false
                    audioToShareURL = nil
                    isShowingAudioShareSheet = false
                    generatedText = ""
                    generatedQuestions = []
                    selectedQuestionIndex = nil
                    isLoadingTopic = false
                    topicErrorMessage = nil
                    isSubmittingAnswer = false
                    submitErrorMessage = nil
                    submitSuccessMessage = nil
                    submitFeedback = nil
                    audioRecorder.stopRecording()
                    audioRecorder.recordedFileURL = nil
                }
                .font(.system(size: 22))
                .buttonStyle(.bordered)
                .foregroundStyle(.red)
                .padding(.top, 24)
            }
            .padding()
            // Share sheet for exporting the handwriting PNG via the system share dialog
            .sheet(isPresented: $isShowingShareSheet) {
                if let url = imageToShareURL {
                    ShareSheet(items: [url])
                }
            }
            // Share sheet for exporting the recorded audio WAV via the system share dialog
            .sheet(isPresented: $isShowingAudioShareSheet) {
                if let url = audioToShareURL {
                    ShareSheet(items: [url])   // handwriting.wav
                }
            }
            // When the view first appears, populate the text fields with any
            // previously saved server configuration from UserDefaults.
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
