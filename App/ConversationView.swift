import SwiftUI

struct ConversationView: View {
    @ObservedObject var controller: ConversationController
    @GestureState private var pressing = false
    @State private var touchActive = false
    private let accent = Color(red: 0.70, green: 0.91, blue: 0.66)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Circle().fill(accent).frame(width: 5, height: 5)
                    Text("ON THIS IPHONE").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2)
                    Spacer()
                    Text("ENGLISH · PUSH TO TALK").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24).padding(.vertical, 16)

                ScrollViewReader { proxy in
                    ScrollView {
                        if controller.messages.isEmpty {
                            VStack(alignment: .leading, spacing: 20) {
                                Image(systemName: "waveform").font(.system(size: 40, weight: .light)).foregroundStyle(accent)
                                Text("A conversation.\nEntirely yours.")
                                    .font(.system(size: 38, weight: .medium, design: .serif))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Your voice, words, and replies stay on your phone. All three models are included in the app.")
                                    .font(.system(size: 16)).foregroundStyle(.secondary).lineSpacing(5)
                                HStack(spacing: 8) {
                                    modelTag("Moonshine")
                                    Image(systemName: "arrow.right").font(.system(size: 8)).foregroundStyle(.tertiary)
                                    modelTag("Qwen3.5")
                                    Image(systemName: "arrow.right").font(.system(size: 8)).foregroundStyle(.tertiary)
                                    modelTag("Phonon")
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 26).padding(.top, 50)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 28) {
                                ForEach(controller.messages) { message in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(message.role == .user ? "YOU" : "ONDEVICE")
                                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                            .tracking(1.8)
                                            .foregroundStyle(message.role == .user ? .secondary : accent)
                                        Text(message.text)
                                            .font(.system(size: message.role == .user ? 18 : 23,
                                                          weight: .regular,
                                                          design: message.role == .user ? .default : .serif))
                                            .lineSpacing(5).textSelection(.enabled)
                                    }
                                }
                                if !controller.partial.isEmpty {
                                    Text(controller.partial).font(.system(size: 23, design: .serif)).lineSpacing(5)
                                        .foregroundStyle(accent)
                                }
                                Color.clear.frame(height: 1).id("bottom")
                            }
                            .padding(26)
                        }
                    }
                    .onChange(of: controller.messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom") } }
                    .onChange(of: controller.partial) { _, _ in proxy.scrollTo("bottom") }
                }
                Spacer(minLength: 12)
                controls
            }
            .background(Color(red: 0.055, green: 0.065, blue: 0.06))
            .navigationTitle("OnDevice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { controller.showDiagnostics = true } label: { Image(systemName: "chart.bar.xaxis") }
                        .accessibilityLabel("Benchmark measurements")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { controller.clear() } label: { Image(systemName: "square.and.pencil") }
                        .disabled(controller.phase == .loading)
                        .accessibilityLabel("New conversation")
                }
            }
            .tint(accent)
            .sheet(isPresented: $controller.showDiagnostics) { DiagnosticsView(controller: controller) }
        }
    }

    private func modelTag(_ name: String) -> some View {
        Text(name).font(.system(size: 10, weight: .medium, design: .monospaced))
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                if [.loading, .transcribing, .thinking].contains(controller.phase) {
                    ProgressView().controlSize(.small).tint(accent)
                }
                Text(controller.phase.rawValue).font(.system(size: 15, weight: .medium))
            }
            Text(controller.detail)
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(minHeight: 30).padding(.horizontal, 12)
            HStack(spacing: 20) {
                if controller.isBusy {
                    Button { controller.interrupt() } label: {
                        Image(systemName: "stop.fill").frame(width: 44, height: 44)
                            .background(.white.opacity(0.08), in: Circle())
                    }.accessibilityLabel("Stop reply")
                }
                ZStack {
                    Circle().stroke(accent.opacity(pressing ? 0.5 : 0.12), lineWidth: 1)
                        .frame(width: 100, height: 100)
                    Circle().fill(controller.phase == .recording ? accent : accent.opacity(0.16))
                        .frame(width: 80, height: 80)
                    Image(systemName: controller.phase == .recording ? "waveform" : "mic.fill")
                        .font(.system(size: 27, weight: .medium))
                        .foregroundStyle(controller.phase == .recording ? Color.black : accent)
                }
                .contentShape(Circle())
                .opacity(controller.canTalk ? 1 : 0.35)
                .gesture(DragGesture(minimumDistance: 0)
                    .updating($pressing) { _, state, _ in state = true }
                    .onChanged { _ in
                        guard !touchActive, controller.canTalk else { return }
                        touchActive = true
                        controller.beginRecording()
                    }
                    .onEnded { _ in
                        touchActive = false
                        controller.finishRecording()
                    })
                .onChange(of: pressing) { _, active in
                    if !active && touchActive {
                        touchActive = false
                        controller.finishRecording()
                    }
                }
                .accessibilityElement()
                .accessibilityLabel(controller.phase == .recording ? "Send voice message" : "Start voice message")
                .accessibilityHint("Double tap to start recording. Double tap again to send.")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    if controller.phase == .recording { controller.finishRecording() }
                    else { controller.beginRecording() }
                }
            }
            Text("HOLD TO TALK").font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(2).foregroundStyle(.secondary)
            if controller.phase == .failed && !controller.canTalk {
                Button("Retry loading models") { controller.prepare() }.font(.footnote)
            }
        }
        .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 25)
    }
}

struct DiagnosticsView: View {
    @ObservedObject var controller: ConversationController
    @Environment(\.dismiss) private var dismiss
    @State private var exportURL: URL?
    @State private var exportError: String?

    private func seconds(_ value: Double?) -> String { value.map { String(format: "%.2f s", $0) } ?? "Not measured" }

    var body: some View {
        NavigationStack {
            List {
                Section("This session") {
                    LabeledContent("Model preparation", value: seconds(controller.coldLoadSeconds))
                    LabeledContent("Bundled model files", value: ByteCountFormatter.string(fromByteCount: controller.assetBytes, countStyle: .file))
                    LabeledContent("Peak sampled resident memory", value: ByteCountFormatter.string(fromByteCount: Int64(controller.peakRSS), countStyle: .memory))
                    LabeledContent("Thermal state", value: Diagnostics.thermalState())
                    LabeledContent("Recorded turns", value: "\(controller.measurements.count)")
                }
                if let turn = controller.measurements.last {
                    Section("Latest turn") {
                        LabeledContent("STT after release", value: seconds(turn.sttSeconds))
                        LabeledContent("Release to first token", value: seconds(turn.firstTokenAfterRelease))
                        LabeledContent("Release to PCM queued", value: seconds(turn.firstPCMEnqueuedAfterRelease))
                        LabeledContent("Release to playback end", value: seconds(turn.completedAfterRelease))
                        if turn.interrupted { Text("Interrupted") }
                        if let failure = turn.failure { Text(failure).foregroundStyle(.orange) }
                    }
                }
                Section {
                    Text("Software timestamps do not establish last-word-to-first-useful-speech latency. Memory is sampled once per second. Device accuracy, endpointing, installed size and energy tests are still required.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let exportURL { ShareLink("Export benchmark JSON", item: exportURL) }
                    else {
                        Button("Prepare benchmark export") {
                            do { exportURL = try controller.exportReport() }
                            catch { exportError = error.localizedDescription }
                        }
                    }
                    if let exportError { Text(exportError).foregroundStyle(.orange) }
                }
                Section("Inference") {
                    Text("Moonshine Small Streaming · English")
                    Text("Qwen3.5-2B · Q4_K_M · llama.cpp")
                    Text("Phonon 31M · English · Core ML")
                    Text("No network inference or model downloads at runtime").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Measurements").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
