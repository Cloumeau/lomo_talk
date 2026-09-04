import AVFoundation
import Foundation
import Speech

enum Assistant: String {
    case codex, claude
}

enum LomoError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case let .message(text) = self { return text }
        return nil
    }
}

final class VoiceInput {
    private let recognizer = SFSpeechRecognizer(locale: Locale.current)

    func authorize() throws {
        let semaphore = DispatchSemaphore(value: 0)
        var speechStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
        SFSpeechRecognizer.requestAuthorization { status in
            speechStatus = status
            semaphore.signal()
        }
        semaphore.wait()
        guard speechStatus == .authorized else {
            throw LomoError.message("Speech recognition permission was not granted. Enable it in System Settings > Privacy & Security > Speech Recognition.")
        }

        let micSemaphore = DispatchSemaphore(value: 0)
        var microphoneAllowed = false
        AVCaptureDevice.requestAccess(for: .audio) { allowed in
            microphoneAllowed = allowed
            micSemaphore.signal()
        }
        micSemaphore.wait()
        guard microphoneAllowed else {
            throw LomoError.message("Microphone permission was not granted. Enable it in System Settings > Privacy & Security > Microphone.")
        }
    }

    func listen() throws -> String {
        guard let recognizer, recognizer.isAvailable else {
            throw LomoError.message("Speech recognition is currently unavailable.")
        }

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let done = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var transcript = ""
        var lastChange = Date()
        var heardSpeech = false
        var recognitionError: Error?

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        let task = recognizer.recognitionTask(with: request) { result, error in
            lock.lock()
            if let result {
                let next = result.bestTranscription.formattedString
                if next != transcript {
                    transcript = next
                    lastChange = Date()
                    heardSpeech = !next.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                if result.isFinal { done.signal() }
            }
            if let error {
                recognitionError = error
                done.signal()
            }
            lock.unlock()
        }

        engine.prepare()
        try engine.start()
        print("\u{001B}[36mListening...\u{001B}[0m", terminator: " ")
        fflush(stdout)

        let timeout = Date().addingTimeInterval(30)
        while Date() < timeout {
            if done.wait(timeout: .now() + 0.1) == .success { break }
            lock.lock()
            let shouldStop = heardSpeech && Date().timeIntervalSince(lastChange) > 1.4
            lock.unlock()
            if shouldStop { break }
        }

        engine.stop()
        input.removeTap(onBus: 0)
        request.endAudio()
        task.cancel()
        lock.lock()
        let finalText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalError = recognitionError
        lock.unlock()
        print(finalText.isEmpty ? "(nothing heard)" : finalText)
        if finalText.isEmpty, let finalError { throw finalError }
        return finalText
    }
}

func speak(_ text: String) {
    let clean = text
        .replacingOccurrences(of: "```[\\s\\S]*?```", with: " Code block omitted. ", options: .regularExpression)
        .replacingOccurrences(of: "[`*_#>]", with: "", options: .regularExpression)
    let utterance = AVSpeechUtterance(string: String(clean.prefix(4_000)))
    utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
    utterance.rate = 0.49
    let synthesizer = AVSpeechSynthesizer()
    synthesizer.speak(utterance)
    while synthesizer.isSpeaking { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
}

@discardableResult
func run(_ executable: String, _ arguments: [String], output: URL? = nil) throws -> (String, String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [executable] + arguments
    let captureDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("lomo-capture-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: captureDirectory) }
    let stdoutURL = captureDirectory.appendingPathComponent("stdout")
    let stderrURL = captureDirectory.appendingPathComponent("stderr")
    FileManager.default.createFile(atPath: stdoutURL.path, contents: Data())
    FileManager.default.createFile(atPath: stderrURL.path, contents: Data())
    let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
    let stderrHandle = try FileHandle(forWritingTo: stderrURL)
    process.standardOutput = stdoutHandle
    process.standardError = stderrHandle
    try process.run()
    process.waitUntilExit()
    try stdoutHandle.close()
    try stderrHandle.close()
    let out = try String(contentsOf: stdoutURL, encoding: .utf8)
    let err = try String(contentsOf: stderrURL, encoding: .utf8)
    guard process.terminationStatus == 0 else {
        throw LomoError.message(err.isEmpty ? "\(executable) exited with status \(process.terminationStatus)." : err)
    }
    if let output {
        return (try String(contentsOf: output, encoding: .utf8), out)
    }
    return (out, err)
}

func commandExists(_ name: String) -> Bool {
    (try? run("which", [name])) != nil
}

func askAssistant(using voice: VoiceInput) throws -> Assistant {
    let greeting = "Hi, this is Lomo. Do you want to use Claude or Codex?"
    print(greeting)
    speak(greeting)
    while true {
        let answer = try voice.listen().lowercased()
        if answer.contains("claude") { return .claude }
        if answer.contains("codex") || answer.contains("code x") { return .codex }
        speak("Please say Claude or Codex.")
    }
}

func codexReply(prompt: String, sessionID: inout String?) throws -> String {
    let resultFile = FileManager.default.temporaryDirectory.appendingPathComponent("lomo-codex-\(UUID().uuidString).txt")
    defer { try? FileManager.default.removeItem(at: resultFile) }
    var args: [String]
    if let sessionID {
        args = ["exec", "resume", sessionID, "-o", resultFile.path, prompt]
    } else {
        args = ["exec", "--json", "-o", resultFile.path, prompt]
    }
    let (answer, events) = try run("codex", args, output: resultFile)
    if sessionID == nil {
        for line in events.split(separator: "\n") {
            if let data = line.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["type"] as? String == "thread.started",
               let id = json["thread_id"] as? String {
                sessionID = id
                break
            }
        }
    }
    return answer.trimmingCharacters(in: .whitespacesAndNewlines)
}

func claudeReply(prompt: String, sessionID: String) throws -> String {
    let args = ["-p", "--session-id", sessionID, "--output-format", "text", prompt]
    let resumedArgs = ["-p", "--resume", sessionID, "--output-format", "text", prompt]
    let marker = FileManager.default.temporaryDirectory.appendingPathComponent("lomo-claude-\(sessionID)")
    let isFirst = !FileManager.default.fileExists(atPath: marker.path)
    let (answer, _) = try run("claude", isFirst ? args : resumedArgs)
    if isFirst { FileManager.default.createFile(atPath: marker.path, contents: Data()) }
    return answer.trimmingCharacters(in: .whitespacesAndNewlines)
}

do {
    let voice = VoiceInput()
    try voice.authorize()
    var assistant = try askAssistant(using: voice)
    var codexSession: String?
    let claudeSession = UUID().uuidString.lowercased()
    var lastReply = ""

    while true {
        guard commandExists(assistant.rawValue) else {
            throw LomoError.message("\(assistant.rawValue) is not installed or is not on PATH.")
        }
        print("\n\u{001B}[1m\(assistant.rawValue.capitalized) is ready. Speak after the listening prompt.\u{001B}[0m")
        let prompt = try voice.listen()
        if prompt.isEmpty { continue }
        let lower = prompt.lowercased()
        if lower.contains("goodbye") || lower == "exit" || lower == "quit" {
            speak("Goodbye.")
            break
        }
        if lower.contains("switch assistant") || lower.contains("switch to claude") || lower.contains("switch to codex") {
            if lower.contains("claude") { assistant = .claude }
            else if lower.contains("codex") { assistant = .codex }
            else { assistant = assistant == .codex ? .claude : .codex }
            speak("Switching to \(assistant.rawValue).")
            continue
        }
        if lower == "repeat" || lower.contains("repeat that") {
            if !lastReply.isEmpty { speak(lastReply) }
            continue
        }

        print("\u{001B}[33mThinking...\u{001B}[0m")
        let reply = assistant == .codex
            ? try codexReply(prompt: prompt, sessionID: &codexSession)
            : try claudeReply(prompt: prompt, sessionID: claudeSession)
        lastReply = reply
        print("\n\u{001B}[32mLomo (\(assistant.rawValue)):\u{001B}[0m \(reply)\n")
        speak(reply)
    }
} catch {
    let message = "Lomo stopped: \(error.localizedDescription)"
    fputs("\(message)\n", stderr)
    exit(1)
}
