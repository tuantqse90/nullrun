import SwiftUI

// "Nhím Coach" — an in-app health chat focused on running + healthy eating.
// Opened by tapping the mascot. All AI runs server-side (DeepSeek via the
// backend) with the disordered-eating (#4) and medical-advice (#6) guardrails
// baked into the system prompt; the client only renders the conversation.
// Nothing here mints points (economy firewall) — it's guidance, not currency.
struct HealthChatView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppModel

    private struct Bubble: Identifiable {
        let id = UUID()
        let role: String // "user" | "assistant"
        let text: String
        var chips: [String] = []     // AI-suggested follow-up questions
        var action: String? = nil    // whitelisted in-app action key
    }

    @State private var bubbles: [Bubble] = []
    @State private var input = ""
    @State private var sending = false
    @FocusState private var focused: Bool

    private let intro =
        "Chào bạn! Mình là Nhím Coach 🦔 Hỏi mình về chạy bộ hay ăn uống lành mạnh nhé — "
        + "ví dụ nên chạy thế nào tuần này, hay ăn gì trước/sau khi chạy."
    private let suggestions = [
        "Gợi ý chạy cho tuần này",
        "Ăn gì trước khi chạy?",
        "Bữa tối lành mạnh gợi ý",
        "Làm sao giữ chuỗi ngày?",
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.hairline)
            messages
            if bubbles.isEmpty { suggestionRow }
            inputBar
        }
        .background(Theme.bg)
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["DEV_COACH_SEED"] != nil, bubbles.isEmpty {
                send("Tuần này nên chạy thế nào?")
            }
            #endif
        }
    }

    // MARK: header
    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().fill(Theme.purpleBg)
                Mascot(mood: .happy, bobbing: false).frame(width: 30, height: 26)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 1) {
                Text("Huấn luyện sức khoẻ").font(.viet(16, .heavy)).foregroundStyle(Theme.ink)
                Text("Nhím Coach · chạy bộ & ăn uống")
                    .font(.viet(11.5)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted)
                    .frame(width: 36, height: 36).background(Theme.dimBg).clipShape(Circle())
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    // MARK: messages
    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    coachBubble(intro)
                    ForEach(bubbles) { b in
                        if b.role == "user" {
                            userBubble(b.text)
                        } else {
                            // Show the interactive chips/action only on the
                            // latest coach message (quick replies for now).
                            let isLast = b.id == bubbles.last?.id
                            coachBubble(
                                b.text,
                                chips: isLast ? b.chips : [],
                                action: isLast ? b.action : nil
                            )
                        }
                    }
                    if sending { typing }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
            .onChange(of: bubbles.count) { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: sending) { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
        }
    }

    private func coachBubble(_ text: String, chips: [String] = [], action: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                ZStack {
                    Circle().fill(Theme.purpleBg)
                    Mascot(mood: .happy, bobbing: false).frame(width: 20, height: 17)
                }
                .frame(width: 28, height: 28)
                Text(text)
                    .font(.viet(14)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(EdgeInsets(top: 10, leading: 13, bottom: 10, trailing: 13))
                    .background(Theme.sheetBg)
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairline, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Spacer(minLength: 34)
            }
            // Interactive action button (whitelisted → maps to a screen).
            if let action, let meta = Self.actionMeta(action) {
                Button {
                    Haptics.heavy()
                    perform(action)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: meta.icon).font(.system(size: 13, weight: .bold))
                        Text(meta.label).font(.viet(13.5, .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 15).padding(.vertical, 10)
                    .background(Theme.green).clipShape(Capsule())
                    .shadow(color: Theme.green.opacity(0.3), radius: 7, y: 3)
                }
                .buttonStyle(.plain)
                .padding(.leading, 36)
            }
            // AI-suggested follow-up questions — tap to ask.
            if !chips.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(chips, id: \.self) { chip in
                        Button {
                            Haptics.light()
                            send(chip)
                        } label: {
                            HStack(spacing: 6) {
                                Text(chip).font(.viet(12.5, .medium)).foregroundStyle(Theme.purpleDeep)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.purple)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Theme.purpleBg).clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 36)
            }
        }
    }

    /// Whitelisted in-app actions the coach may surface as a button.
    private static func actionMeta(_ key: String) -> (label: String, icon: String)? {
        switch key {
        case "start_run": return ("Bắt đầu chạy", "figure.run")
        case "set_goal": return ("Đặt mục tiêu tuần", "target")
        default: return nil
        }
    }

    private func perform(_ key: String) {
        switch key {
        case "start_run": app.screen = .prerun
        case "set_goal": app.requestGoalEdit = true
        default: break
        }
        dismiss()
    }

    private func userBubble(_ text: String) -> some View {
        HStack {
            Spacer(minLength: 40)
            Text(text)
                .font(.viet(14)).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(EdgeInsets(top: 10, leading: 13, bottom: 10, trailing: 13))
                .background(Theme.green)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var typing: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(Theme.purpleBg)
                Mascot(mood: .happy, bobbing: false).frame(width: 20, height: 17)
            }
            .frame(width: 28, height: 28)
            TypingDots()
                .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
                .background(Theme.sheetBg)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairline, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Spacer()
        }
    }

    // MARK: suggestions
    private var suggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { s in
                    Button {
                        Haptics.light()
                        send(s)
                    } label: {
                        Text(s).font(.viet(12.5, .medium)).foregroundStyle(Theme.purpleDeep)
                            .padding(.horizontal, 13).padding(.vertical, 9)
                            .background(Theme.purpleBg)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
    }

    // MARK: input
    private var inputBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                TextField("Hỏi về chạy bộ, món ăn…", text: $input, axis: .vertical)
                    .font(.viet(14)).lineLimit(1...4)
                    .focused($focused)
                    .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
                    .background(Theme.sheetBg)
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.hairline, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .onSubmit { send(input) }
                Button {
                    send(input)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(canSend ? Theme.green : Theme.faint)
                        .clipShape(Circle())
                }
                .disabled(!canSend)
            }
            Text("Gợi ý chung về lối sống, không thay tư vấn y tế chuyên môn.")
                .font(.viet(10)).foregroundStyle(Theme.faint)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
        .background(Theme.bg)
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending
    }

    // MARK: send
    private func send(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !sending else { return }
        bubbles.append(Bubble(role: "user", text: t))
        input = ""
        focused = false
        sending = true
        // Send only the real turns (the intro greeting stays UI-only).
        let turns = bubbles.map { (role: $0.role, content: $0.text) }
        Task {
            do {
                let reply = try await APIClient.shared.coachChat(turns)
                let act = reply.action == "none" ? nil : reply.action
                bubbles.append(Bubble(
                    role: "assistant", text: reply.reply,
                    chips: reply.chips ?? [], action: act
                ))
            } catch {
                bubbles.append(Bubble(
                    role: "assistant",
                    text: "Xin lỗi, mình đang bận chút xíu. Bạn thử lại sau nhé! 🙏"
                ))
            }
            sending = false
        }
    }
}

/// Three-dot "typing" animation for the coach.
private struct TypingDots: View {
    @State private var phase = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(Theme.faint)
                    .frame(width: 6, height: 6)
                    .opacity(reduceMotion ? 0.6 : 0.35 + 0.5 * abs(sin(phase + Double(i) * 0.7)))
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) { phase = .pi * 2 }
        }
    }
}
