import Combine
import SwiftUI
import AVFAudio

class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordedFileURL: URL?

    private var audioRecorder: AVAudioRecorder?

    override init() {
        super.init()
        configureSession()
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            print("Audio session error:", error.localizedDescription)
        }
    }

    func requestPermission(completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    func startRecording() {
        requestPermission { [weak self] granted in
            guard let self, granted else {
                print("Microphone access not granted")
                return
            }

            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16000.0,                    // 16 kHz
                AVNumberOfChannelsKey: 1,                    // mono
                AVLinearPCMBitDepthKey: 16,                  // 16-bit
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false
            ]                                             // uncompressed PCM (WAV)

            // Save to Documents as handwriting.wav
            guard let documents = FileManager.default.urls(for: .documentDirectory,
                                                           in: .userDomainMask).first else {
                print("No documents directory")
                return
            }
            let fileURL = documents.appendingPathComponent("handwriting.wav")

            do {
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

    func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
    }
}
