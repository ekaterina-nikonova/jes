import Combine
import SwiftUI
import AVFAudio

/// Manages audio recording for the spoken-answer portion of an exercise.
///
/// This class wraps `AVAudioRecorder` and exposes two `@Published` properties so that
/// SwiftUI views can reactively update when recording starts/stops or when a file becomes
/// available. Audio is captured as uncompressed 16-bit mono PCM at 16 kHz (WAV format),
/// which is suitable for speech-recognition back-ends that typically expect this sample rate.
///
class AudioRecorder: NSObject, ObservableObject {
    /// Whether the recorder is currently capturing audio. Drives UI state (e.g. button labels).
    @Published var isRecording = false

    /// The file URL of the most recent recording, or `nil` if nothing has been recorded yet.
    /// This URL is used later to attach the WAV file to the answer submission.
    @Published var recordedFileURL: URL?

    /// The underlying AVFoundation recorder instance.
    private var audioRecorder: AVAudioRecorder?

    /// On initialization, immediately configures the shared audio session so that recording
    /// is possible as soon as the user taps "Record".
    override init() {
        super.init()
        configureSession()
    }

    /// Configures the app's audio session with the `.playAndRecord` category.
    /// The `.defaultToSpeaker` option routes playback through the main speaker rather than
    /// the earpiece, which is more appropriate for reviewing recordings on an iPad.
    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            print("Audio session error:", error.localizedDescription)
        }
    }

    /// Asks the user for microphone permission. The `completion` handler is dispatched
    /// on the main queue so callers can safely update UI state from the callback.
    func requestPermission(completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    /// Begins recording audio after first requesting microphone permission.
    ///
    /// Recording settings:
    /// - Format: Linear PCM (uncompressed WAV)
    /// - Sample rate: 16 kHz — the standard for many speech-to-text models
    /// - Channels: 1 (mono)
    /// - Bit depth: 16-bit, little-endian, integer samples
    ///
    /// The output file is saved to the app's Documents directory as "handwriting.wav",
    /// requesting to overwrite any previous recording.
    func startRecording() {
        requestPermission { [weak self] granted in
            guard let self, granted else {
                print("Microphone access not granted")
                return
            }

            // Audio format: 16 kHz, mono, 16-bit linear PCM (WAV)
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16000.0,                    // 16 kHz
                AVNumberOfChannelsKey: 1,                    // mono
                AVLinearPCMBitDepthKey: 16,                  // 16-bit
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false
            ]

            // Resolve the app's Documents directory to save the WAV file
            guard let documents = FileManager.default.urls(for: .documentDirectory,
                                                           in: .userDomainMask).first else {
                print("No documents directory")
                return
            }
            let fileURL = documents.appendingPathComponent("handwriting.wav")

            do {
                // Create the recorder, pre-allocate buffers, and start capturing audio
                audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
                audioRecorder?.prepareToRecord()
                audioRecorder?.record()
                recordedFileURL = fileURL
                isRecording = true
                print("Recording to:", fileURL.path)
            } catch {
                print("Failed to start recording:", error.localizedDescription)
            }
        }
    }

    /// Stops the current recording session. The recorded file remains at `recordedFileURL`
    /// and can be exported or submitted.
    func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
    }
}
