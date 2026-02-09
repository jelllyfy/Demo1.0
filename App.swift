import SwiftUI
import Combine

@main
struct ClapBrowseApp: App {
    @StateObject private var activityLogger = ActivityLogger()
    @StateObject private var activationManager = ActivationManager()
    
    var body: some Scene {
        WindowGroup {
            Group {
                if activationManager.isActivated {
                    ProtectedBrowser {
                        ContentView()
                            .environmentObject(activityLogger)
                            .environmentObject(activationManager)
                    }
                } else {
                    ActivationView(activationManager: activationManager)
                }
            }
        }
    }
}

struct ProtectedBrowser<Content: View>: View {
    let content: Content
    @StateObject private var screenshotProtector = ScreenshotProtector()
    @State private var isScreenRecording = false
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            content
            Color.clear
                .overlay(
                    SecureTextFieldView()
                        .allowsHitTesting(false)
                )
            
            if isScreenRecording {
                Color.black
                    .edgesIgnoringSafeArea(.all)
                    .overlay(
                        VStack {
                            Image(systemName: "eye.slash")
                                .font(.largeTitle)
                            Text("Screen Recording Detected")
                                .font(.headline)
                            Text("")
                                .font(.subheadline)
                        }
                            .foregroundColor(.white)
                    )
            }
        }
        .onAppear {
            screenshotProtector.startProtection()
            setupScreenRecordingMonitor()
        }
        .onDisappear {
            NotificationCenter.default.removeObserver(self, name: UIScreen.capturedDidChangeNotification, object: nil)
        }
    }
    
    private func setupScreenRecordingMonitor() {
        isScreenRecording = UIScreen.main.isCaptured
        NotificationCenter.default.addObserver(
            forName: UIScreen.capturedDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            isScreenRecording = UIScreen.main.isCaptured
        }
    }
}

struct ActivationView: View {
    @ObservedObject var activationManager: ActivationManager
    @State private var activationCode: String = ""
    @State private var showInvalidCodeAlert = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("ClapBrowse Activation")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Enter activation password to use the browser")
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    SecureField("Enter password", text: $activationCode)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onSubmit {
                            validateActivationCode()
                        }
                }
                .padding(.horizontal, 40)
                
                Button(action: validateActivationCode) {
                    Text("Activate Browser")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.horizontal, 40)
                .disabled(activationCode.isEmpty)
                
                if activationManager.isActivated && activationManager.timeRemaining > 0 {
                    VStack(spacing: 8) {
                        Text("Time remaining:")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(activationManager.formattedTimeRemaining())
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    }
                    .padding(.top, 20)
                }
                
                Spacer()
                
                Text("Activation lasts 48 hours")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.bottom, 20)
            }
            .padding(.top, 60)
            .navigationBarHidden(true)
            .alert("Invalid Password", isPresented: $showInvalidCodeAlert) {
                Button("OK", role: .cancel) {
                    activationCode = ""
                }
            } message: {
                Text("The password you entered is incorrect.")
            }
        }
    }
    
    private func validateActivationCode() {
        if activationManager.validateCode(activationCode) {
            // Activation successful
        } else {
            showInvalidCodeAlert = true
        }
    }
}

class ScreenshotProtector: ObservableObject {
    private var secureTextField: UITextField?
    
    func startProtection() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.setupSecureField()
        }
    }
    
    private func setupSecureField() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return
        }
        
        secureTextField = UITextField()
        secureTextField?.isSecureTextEntry = true
        secureTextField?.isUserInteractionEnabled = false
        
        if let textField = secureTextField {
            window.addSubview(textField)
            textField.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: window.leadingAnchor),
                textField.trailingAnchor.constraint(equalTo: window.trailingAnchor),
                textField.topAnchor.constraint(equalTo: window.topAnchor),
                textField.bottomAnchor.constraint(equalTo: window.bottomAnchor)
            ])
            textField.alpha = 0.0001
        }
    }
}

struct SecureTextFieldView: UIViewRepresentable {
    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.isSecureTextEntry = true
        textField.isUserInteractionEnabled = false
        textField.backgroundColor = .clear
        textField.alpha = 0.0001
        return textField
    }
    
    func updateUIView(_ uiView: UITextField, context: Context) {}
}

class ActivationManager: ObservableObject {
    @Published var isActivated: Bool = false
    @Published var timeRemaining: TimeInterval = 0
    
    private var activationExpiryDate: Date?
    private let correctPassword = "DumbSoBad1"
    private let activationKey = "activationExpiry"
    private var timerCancellable: AnyCancellable?
    
    init() {
        loadActivationStatus()
        startTimer()
    }
    
    private func loadActivationStatus() {
        if let savedDate = UserDefaults.standard.object(forKey: activationKey) as? Date,
           Date() < savedDate {
            activationExpiryDate = savedDate
            isActivated = true
            calculateTimeRemaining()
        }
    }
    
    private func startTimer() {
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.calculateTimeRemaining()
            }
    }
    
    private func calculateTimeRemaining() {
        guard let expiryDate = activationExpiryDate else {
            timeRemaining = 0
            return
        }
        
        let remaining = expiryDate.timeIntervalSince(Date())
        timeRemaining = max(0, remaining)
        
        if remaining <= 0 {
            isActivated = false
        }
    }
    
    func validateCode(_ input: String) -> Bool {
        let normalizedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if normalizedInput == correctPassword {
            activateApp()
            return true
        }
        
        return false
    }
    
    private func activateApp() {
        let expiryDate = Date().addingTimeInterval(48 * 3600)
        activationExpiryDate = expiryDate
        UserDefaults.standard.set(expiryDate, forKey: activationKey)
        isActivated = true
        calculateTimeRemaining()
    }
    
    func formattedTimeRemaining() -> String {
        let hours = Int(timeRemaining) / 3600
        let minutes = (Int(timeRemaining) % 3600) / 60
        let seconds = Int(timeRemaining) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    deinit {
        timerCancellable?.cancel()
    }
}

class ActivityLogger: ObservableObject {
    private let logFileURL: URL
    
    init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        logFileURL = documentsPath.appendingPathComponent("clapbrowse_activity.log")
        logEvent("ClapBrowse Started", details: "App launched at \(Date())")
    }
    
    func logEvent(_ event: String, details: String? = nil) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium)
        var logEntry = "[\(timestamp)] \(event)"
        
        if let details = details, !details.isEmpty {
            logEntry += " | \(details)"
        }
        
        print(logEntry)
        
        if let data = (logEntry + "\n").data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    try? fileHandle.close()
                }
            } else {
                try? data.write(to: logFileURL)
            }
        }
    }
    
    func logButtonPress(_ buttonName: String, location: String = "Toolbar") {
        logEvent("Button Pressed", details: "\(buttonName) in \(location)")
    }
    
    func logNavigation(_ action: String, url: String? = nil) {
        logEvent("Navigation", details: "\(action)\(url != nil ? " to: \(url!)" : "")")
    }
    
    func logTabAction(_ action: String, tabTitle: String? = nil) {
        logEvent("Tab Action", details: "\(action)\(tabTitle != nil ? " - \(tabTitle!)" : "")")
    }
    
    func logConsoleCommand(_ command: String, type: String = "Manual") {
        logEvent("Console Command", details: "\(type): \(command)")
    }
    
    func logSettingsChange(_ setting: String, value: String) {
        logEvent("Settings Change", details: "\(setting) = \(value)")
    }
    
    func logError(_ error: String, context: String = "") {
        let contextString = context.isEmpty ? "" : "\(context) - "
        logEvent("Error", details: "\(contextString)\(error)")
    }
    
    func logSecurityEvent(_ event: String, details: String = "") {
        let detailsString = details.isEmpty ? "" : " - \(details)"
        logEvent("Security Event", details: "\(event)\(detailsString)")
    }
    
    func logDownloadEvent(_ event: String, filename: String) {
        logEvent("Download", details: "\(event): \(filename)")
    }
    
    func getLogContents() -> String {
        do {
            return try String(contentsOf: logFileURL, encoding: .utf8)
        } catch {
            return "No log data available"
        }
    }
    
    func clearLogs() {
        try? FileManager.default.removeItem(at: logFileURL)
        logEvent("Logs Cleared", details: "All activity logs cleared")
    }
}
