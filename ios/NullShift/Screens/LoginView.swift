import SwiftUI

/// Brand mark from the design's login screen (s02): green rounded square
/// with a run-path stroke and an orange dot.
struct BrandMark: View {
    var size: CGFloat = 88

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(Theme.green)
            .frame(width: size, height: size)
            .overlay {
                RunPathIcon()
                    .stroke(.white, style: StrokeStyle(lineWidth: size * 0.045, lineCap: .round))
                    .padding(size * 0.2)
                    .overlay(alignment: .topTrailing) {
                        Circle()
                            .fill(Theme.orangeSoft)
                            .frame(width: size * 0.1, height: size * 0.1)
                            .padding(size * 0.18)
                    }
            }
            .shadow(color: Theme.green.opacity(0.25), radius: 9, y: 6)
    }
}

struct RunPathIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: .init(x: 0, y: h * 0.78))
        p.addCurve(
            to: .init(x: w * 0.5, y: h * 0.22),
            control1: .init(x: w * 0.22, y: h * 0.55),
            control2: .init(x: w * 0.3, y: h * 0.22)
        )
        p.addCurve(
            to: .init(x: w, y: h * 0.86),
            control1: .init(x: w * 0.75, y: h * 0.22),
            control2: .init(x: w * 0.68, y: h * 0.86)
        )
        return p
    }
}

/// Login per s02: Zalo visual-first + Apple (both "sắp ra mắt" until OAuth
/// lands), phone/OTP is the working path — same visual grammar.
struct LoginView: View {
    @EnvironmentObject private var auth: AuthStore

    enum Step { case landing, phone, code }
    enum Field { case phone, code }
    @State private var step: Step = .landing
    @State private var phone = ""
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?
    @State private var comingSoon = false
    @FocusState private var focus: Field?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 14) {
                    BrandMark()
                    Text("null-run").font(.viet(30, .heavy))
                    Text("Vận động thật. Điểm thật. Quà thật.")
                        .font(.viet(16)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: 290)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 80)
                .padding(.bottom, 56)

                switch step {
                case .landing: landingButtons
                case .phone: phoneEntry
                case .code: codeEntry
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.bg)
        .contentShape(Rectangle())
        .onTapGesture { focus = nil }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Xong") { focus = nil }
                    .font(.viet(16, .semibold))
            }
        }
        .overlay(alignment: .top) {
            if comingSoon {
                HStack(spacing: 10) {
                    Image(systemName: "hourglass").font(.system(size: 13)).foregroundStyle(Theme.greenBright)
                    Text("Sắp ra mắt — dùng số điện thoại trước nhé")
                        .font(.viet(13)).foregroundStyle(Theme.darkInk)
                }
                .padding(EdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16))
                .background(Theme.ink)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.top, 64)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: comingSoon)
    }

    private var landingButtons: some View {
        VStack(spacing: 12) {
            Button { showComingSoon() } label: {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white)
                        .frame(width: 30, height: 30)
                        .overlay {
                            Text("Zalo").font(.system(size: 11, weight: .heavy)).foregroundStyle(Color(hex: 0x0068FF))
                        }
                    Text("Tiếp tục với Zalo").font(.viet(17, .bold)).foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(Color(hex: 0x0068FF))
                .clipShape(Capsule())
            }
            .buttonStyle(PressScale())

            Button { showComingSoon() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "apple.logo").font(.system(size: 19)).foregroundStyle(.white)
                    Text("Đăng nhập bằng Apple").font(.viet(17, .bold)).foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(Theme.ink)
                .clipShape(Capsule())
            }
            .buttonStyle(PressScale())

            Button {
                withAnimation(.easeOut(duration: 0.25)) { step = .phone }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "phone.fill").font(.system(size: 15))
                    Text("Dùng số điện thoại").font(.viet(17, .bold))
                }
                .foregroundStyle(Theme.greenDeep)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(Theme.greenBgSoft)
                .clipShape(Capsule())
            }
            .buttonStyle(PressScale())

            Text("Chúng tôi không đăng gì lên Zalo của bạn. Dữ liệu vận động ở lại trên máy.")
                .font(.viet(12.5)).foregroundStyle(Theme.faint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.top, 6)
        }
        .padding(.bottom, 24)
    }

    private var phoneEntry: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Số điện thoại").font(.viet(13.5)).foregroundStyle(Theme.muted)
                TextField("09xx xxx xxx", text: $phone)
                    .font(.mono(22))
                    .foregroundStyle(Theme.ink)
                    .tint(Theme.green)
                    .keyboardType(.phonePad)
                    .focused($focus, equals: .phone)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18))
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: Theme.cardShadow, radius: 5, y: 2)
            .onAppear { focus = .phone }

            if let error {
                Text(error).font(.viet(13)).foregroundStyle(Theme.danger)
            }

            PrimaryButton(title: busy ? "Đang gửi mã…" : "Nhận mã OTP", height: 60) {
                Task { await sendOTP() }
            }
            .disabled(busy || phone.count < 9)
            .opacity(phone.count < 9 ? 0.55 : 1)

            Button("Quay lại") { withAnimation { step = .landing } }
                .font(.viet(15, .semibold)).foregroundStyle(Theme.muted)
                .padding(.top, 4)
        }
        .padding(.bottom, 24)
    }

    private var codeEntry: some View {
        VStack(spacing: 12) {
            Text("Mã đã gửi tới \(phone)")
                .font(.viet(13)).foregroundStyle(Theme.muted)
            VStack(alignment: .leading, spacing: 4) {
                Text("Mã OTP").font(.viet(13.5)).foregroundStyle(Theme.muted)
                TextField("6 số", text: $code)
                    .font(.mono(26))
                    .foregroundStyle(Theme.ink)
                    .tint(Theme.green)
                    .kerning(4)
                    .keyboardType(.numberPad)
                    .focused($focus, equals: .code)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18))
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: Theme.cardShadow, radius: 5, y: 2)
            .onAppear { focus = .code }
            #if DEBUG
            Text("Bản dev: mã luôn là 123456")
                .font(.viet(12.5)).foregroundStyle(Theme.faint)
            #endif

            if let error {
                Text(error).font(.viet(13)).foregroundStyle(Theme.danger)
            }

            PrimaryButton(title: busy ? "Đang xác nhận…" : "Xác nhận", height: 60) {
                Task { await verify() }
            }
            .disabled(busy || code.count != 6)
            .opacity(code.count != 6 ? 0.55 : 1)

            Button("Đổi số điện thoại") {
                code = ""
                withAnimation { step = .phone }
            }
            .font(.viet(15, .semibold)).foregroundStyle(Theme.muted)
            .padding(.top, 4)
        }
        .padding(.bottom, 24)
    }

    private func showComingSoon() {
        comingSoon = true
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            comingSoon = false
        }
    }

    private func sendOTP() async {
        busy = true
        error = nil
        do {
            try await auth.requestOTP(phone: phone)
            withAnimation { step = .code }
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }

    private func verify() async {
        busy = true
        error = nil
        do {
            try await auth.verifyOTP(phone: phone, code: code)
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }
}

/// Cold-launch splash: the brand block on cream, pulse, then fade.
struct SplashView: View {
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 14) {
            BrandMark(size: 96)
                .scaleEffect(pulse ? 1.05 : 1)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            Text("null-run").font(.viet(28, .heavy))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .onAppear { pulse = true }
    }
}
