import SwiftUI
@preconcurrency import WebKit
import Combine

enum SearchEngine: String, CaseIterable {
    case google = "Google"
    case bing = "Bing"
    case duckduckgo = "DuckDuckGo"
    case yahoo = "Yahoo"
    case startpage = "StartPage"
    
    var searchURL: String {
        switch self {
        case .google: return "https://www.google.com/search?q="
        case .bing: return "https://www.bing.com/search?q="
        case .duckduckgo: return "https://duckduckgo.com/?q="
        case .yahoo: return "https://swisscows.com/web?query="
        case .startpage: return ""
        }
    }
    
    func searchURL(with query: String) -> String {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        switch self {
        case .startpage:
            return "\(searchURL)?query=\(encodedQuery)"
        default:
            return "\(searchURL)\(encodedQuery)"
        }
    }
}

struct HistoryItem: Identifiable, Codable {
    let id: UUID
    let url: String
    let title: String
    let timestamp: Date
    
    init(url: String, title: String, timestamp: Date = Date()) {
        self.id = UUID()
        self.url = url
        self.title = title
        self.timestamp = timestamp
    }
}

struct Bookmark: Identifiable, Codable {
    let id: UUID
    let url: String
    let title: String
    let dateAdded: Date
    
    init(url: String, title: String, dateAdded: Date = Date()) {
        self.id = UUID()
        self.url = url
        self.title = title
        self.dateAdded = dateAdded
    }
}

struct BrowserTab: Identifiable, Codable {
    let id: UUID
    var title: String
    var url: String
    var isActive: Bool
    
    init(title: String = "New Tab", url: String = "about:blank", isActive: Bool = false) {
        self.id = UUID()
        self.title = title
        self.url = url
        self.isActive = isActive
    }
}

struct CustomCommand: Identifiable, Codable {
    let id: UUID
    var name: String
    var command: String
    var icon: String
    
    init(name: String, command: String, icon: String = "terminal") {
        self.id = UUID()
        self.name = name
        self.command = command
        self.icon = icon
    }
}

struct DownloadItem: Identifiable {
    let id: UUID
    let url: URL
    let filename: String
    var progress: Double
    var isDownloading: Bool
    var isCompleted: Bool
    
    init(url: URL, filename: String) {
        self.id = UUID()
        self.url = url
        self.filename = filename
        self.progress = 0.0
        self.isDownloading = true
        self.isCompleted = false
    }
}

class BrowserModel: NSObject, ObservableObject {
    @Published var currentURL: String = ""
    @Published var isLoading: Bool = false
    @Published var loadProgress: Double = 0.0
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var showErrorAlert: Bool = false
    @Published var errorMessage: String = ""
    @Published var selectedSearchEngine: SearchEngine = .google
    @Published var history: [HistoryItem] = []
    @Published var bookmarks: [Bookmark] = []
    @Published var isDarkMode: Bool = false
    @Published var showDevConsole: Bool = false
    @Published var consoleMessages: [String] = []
    @Published var consoleInput: String = ""
    @Published var tabs: [BrowserTab] = [BrowserTab(title: "Welcome", url: "about:blank", isActive: true)]
    @Published var activeTabIndex: Int = 0
    @Published var showTabView: Bool = false
    @Published var customCommands: [CustomCommand] = [
        CustomCommand(name: "Alert", command: "alert('Hello from ClapBrowse!')", icon: "globe"),
        CustomCommand(name: "Title", command: "document.title", icon: "text.bubble"),
        CustomCommand(name: "URL", command: "window.location.href", icon: "link"),
        CustomCommand(name: "Elements", command: "console.log('Elements:', document.querySelectorAll('*').length)", icon: "square.grid.2x2")
    ]
    @Published var showingCommandEditor: Bool = false
    @Published var newCommandName: String = ""
    @Published var newCommandCode: String = ""
    @Published var newCommandIcon: String = "globe"
    @Published var downloads: [DownloadItem] = []
    @Published var showingDownloads: Bool = false
    @Published var showingBookmarkAlert: Bool = false
    @Published var bookmarkAlertMessage: String = ""
    
    let logger = ActivityLogger()
    var webView: WKWebView?
    private var webViews: [UUID: WKWebView] = [:]
    private let userDefaults = UserDefaults.standard
    private let historyKey = "browserHistory"
    private let bookmarksKey = "browserBookmarks"
    private let settingsKey = "browserSettings"
    private let tabsKey = "browserTabs"
    private let commandsKey = "customCommands"
    
    override init() {
        super.init()
        loadSettings()
        loadHistory()
        loadBookmarks()
        loadTabs()
        loadCustomCommands()
        setupWebView()
    }
    
    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        self.webView = webView
        
        if tabs.isEmpty {
            tabs = [BrowserTab(title: "Welcome", url: "about:blank", isActive: true)]
        }
        
        if let activeTab = tabs.first(where: { $0.isActive }) ?? tabs.first {
            webViews[activeTab.id] = webView
            activeTabIndex = tabs.firstIndex(where: { $0.id == activeTab.id }) ?? 0
            
            if activeTab.url != "about:blank" && !activeTab.url.isEmpty {
                loadSavedTabURL(activeTab.url)
            } else {
                loadWelcomePage()
            }
        } else {
            loadWelcomePage()
        }
    }
    
    private func loadSavedTabURL(_ url: String) {
        guard let urlObj = URL(string: url) else {
            loadWelcomePage()
            return
        }
        
        let request = URLRequest(url: urlObj)
        webView?.load(request)
        currentURL = url
        logger.logNavigation("Restored saved tab", url: url)
    }
    
    private func loadWelcomePage() {
        let welcomeHTML = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
        body {
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
        padding: 40px 20px;
        background: #ffffff;
        color: #333333;
        text-align: center;
        min-height: 100vh;
        display: flex;
        flex-direction: column;
        justify-content: center;
        align-items: center;
        }
        .container {
        max-width: 500px;
        background: #f8f9fa;
        padding: 40px;
        border-radius: 12px;
        border: 1px solid #e9ecef;
        }
        h1 {
        font-size: 2.2em;
        margin-bottom: 20px;
        font-weight: 600;
        color: #1a1a1a;
        }
        p {
        font-size: 1.1em;
        line-height: 1.6;
        margin-bottom: 15px;
        color: #666666;
        }
        .download-link {
        display: inline-block;
        margin: 10px;
        padding: 10px 20px;
        background: #007AFF;
        color: white;
        text-decoration: none;
        border-radius: 6px;
        }
        </style>
        </head>
        <body>
        <div class="container">
        <h1>DEMO</h1>
        <p></p>
        <p></p>
        <p><a class="download-link" href="https://github.com/search?q=Blooket%20gui%20cheat&type=repositories" download="swift-readme.md">Test Download</a></p>
        </div>
        </body>
        </html>
        """
        
        webView?.loadHTMLString(welcomeHTML, baseURL: nil)
        currentURL = "ClapBrowse"
        updateActiveTabURL("ClapBrowse", title: "Welcome")
        logger.logNavigation("Loaded welcome page")
    }
    
    func createNewTab() {
        let newTab = BrowserTab(title: "New Tab", url: "about:blank", isActive: true)
        tabs.forEach { tab in
            if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
                tabs[index].isActive = false
            }
        }
        tabs.append(newTab)
        activeTabIndex = tabs.count - 1
        
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        let newWebView = WKWebView(frame: .zero, configuration: config)
        newWebView.navigationDelegate = self
        newWebView.uiDelegate = self
        newWebView.allowsBackForwardNavigationGestures = true
        webViews[newTab.id] = newWebView
        webView = newWebView
        
        logger.logTabAction("Created new tab", tabTitle: "New Tab")
        loadWelcomePage()
        saveTabs()
    }
    
    func switchToTab(_ tabId: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        
        tabs.indices.forEach { i in
            tabs[i].isActive = (tabs[i].id == tabId)
        }
        
        activeTabIndex = index
        webView = webViews[tabId]
        currentURL = tabs[index].url
        
        if let webView = webView {
            canGoBack = webView.canGoBack
            canGoForward = webView.canGoForward
        }
        
        logger.logTabAction("Switched to tab", tabTitle: tabs[index].title)
        saveTabs()
    }
    
    func closeTab(_ tabId: UUID) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        
        let tabTitle = tabs[index].title
        webViews.removeValue(forKey: tabId)
        tabs.remove(at: index)
        
        if activeTabIndex >= tabs.count {
            activeTabIndex = tabs.count - 1
        }
        
        if !tabs.isEmpty {
            switchToTab(tabs[activeTabIndex].id)
        }
        
        logger.logTabAction("Closed tab", tabTitle: tabTitle)
        saveTabs()
    }
    
    func updateActiveTabURL(_ url: String, title: String? = nil) {
        guard activeTabIndex < tabs.count else { return }
        tabs[activeTabIndex].url = url
        if let title = title {
            tabs[activeTabIndex].title = title
        }
        saveTabs()
    }
    
    var activeTab: BrowserTab? {
        guard activeTabIndex < tabs.count else { return nil }
        return tabs[activeTabIndex]
    }
    
    func loadURL() {
        guard !currentURL.isEmpty else { return }
        logger.logButtonPress("Load URL", location: "URL Bar")
        logger.logNavigation("Loading URL", url: currentURL)
        
        var urlString = currentURL.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let isSearchQuery = !urlString.contains(".") || urlString.contains(" ") || urlString.hasPrefix("?")
        
        if isSearchQuery {
            urlString = formatSearchQuery(urlString)
            logger.logNavigation("Converted to search query", url: urlString)
        } else if !urlString.hasPrefix("http") {
            urlString = "https://\(urlString)"
        }
        
        guard let url = URL(string: urlString) else {
            handleError(NSError(domain: "Invalid URL", code: 400, userInfo: [NSLocalizedDescriptionKey: "Could not create URL from: \(urlString)"]))
            return
        }
        
        let request = URLRequest(url: url)
        webView?.load(request)
        updateActiveTabURL(urlString)
    }
    
    func loadHomepage() {
        logger.logButtonPress("Home", location: "Toolbar")
        loadWelcomePage()
    }
    
    func reload() {
        logger.logButtonPress("Reload", location: "Toolbar")
        webView?.reload()
    }
    
    func goBack() {
        logger.logButtonPress("Back", location: "Toolbar")
        webView?.goBack()
    }
    
    func goForward() {
        logger.logButtonPress("Forward", location: "Toolbar")
        webView?.goForward()
    }
    
    func toggleDarkMode() {
        logger.logButtonPress("Dark Mode Toggle", location: "Toolbar")
        logger.logSettingsChange("Dark Mode", value: "\(!isDarkMode)")
        isDarkMode.toggle()
        saveSettings()
    }
    
    func toggleDevConsole() {
        logger.logButtonPress("Developer Console", location: "Toolbar")
        showDevConsole.toggle()
    }
    
    func toggleTabView() {
        logger.logButtonPress("Tab View", location: "Header")
        showTabView.toggle()
    }
    
    func toggleDownloads() {
        logger.logButtonPress("Downloads", location: "Toolbar")
        showingDownloads.toggle()
    }
    
    func executeConsoleCommand() {
        let command = consoleInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        
        consoleInput = ""
        addConsoleMessage("> \(command)")
        logger.logConsoleCommand(command, type: "Manual")
        
        webView?.evaluateJavaScript(command) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    let errorMsg = "Error: \(error.localizedDescription)"
                    self?.addConsoleMessage(errorMsg)
                    self?.logger.logError(errorMsg, context: "Console Command")
                } else if let result = result {
                    self?.addConsoleMessage("â \(String(describing: result))")
                } else {
                    self?.addConsoleMessage("â undefined")
                }
            }
        }
    }
    
    func executeQuickCommand(_ command: String) {
        addConsoleMessage("ð \(command)")
        logger.logConsoleCommand(command, type: "Quick Button")
        
        webView?.evaluateJavaScript(command) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    let errorMsg = "Error: \(error.localizedDescription)"
                    self?.addConsoleMessage(errorMsg)
                    self?.logger.logError(errorMsg, context: "Quick Command")
                } else if let result = result {
                    self?.addConsoleMessage("â \(String(describing: result))")
                }
            }
        }
    }
    
    func executeCustomCommand(_ command: CustomCommand) {
        logger.logButtonPress("Custom Command: \(command.name)", location: "Console")
        executeQuickCommand(command.command)
    }
    
    func addCustomCommand() {
        guard !newCommandName.isEmpty && !newCommandCode.isEmpty else { return }
        let newCommand = CustomCommand(name: newCommandName, command: newCommandCode, icon: newCommandIcon)
        customCommands.append(newCommand)
        logger.logEvent("Custom Command Added", details: "\(newCommandName): \(newCommandCode)")
        newCommandName = ""
        newCommandCode = ""
        newCommandIcon = "terminal"
        showingCommandEditor = false
        saveCustomCommands()
    }
    
    func deleteCustomCommand(_ command: CustomCommand) {
        if let index = customCommands.firstIndex(where: { $0.id == command.id }) {
            customCommands.remove(at: index)
            saveCustomCommands()
        }
    }
    
    func clearConsole() {
        consoleMessages.removeAll()
        logger.logButtonPress("Clear Console", location: "Console")
    }
    
    private func addConsoleMessage(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let formattedMessage = "[\(timestamp)] \(message)"
        consoleMessages.append(formattedMessage)
        if consoleMessages.count > 100 {
            consoleMessages.removeFirst()
        }
    }
    
    private func formatSearchQuery(_ query: String) -> String {
        selectedSearchEngine.searchURL(with: query)
    }
    
    func addToHistory(url: String, title: String) {
        let newItem = HistoryItem(url: url, title: title)
        history.append(newItem)
        logger.logEvent("Added to History", details: "\(title) - \(url)")
        saveHistory()
    }
    
    func deleteHistoryItems(at offsets: IndexSet) {
        offsets.map { history.count - 1 - $0 }
            .sorted(by: >)
            .forEach { index in
                if history.indices.contains(index) {
                    history.remove(at: index)
                }
            }
        saveHistory()
    }
    
    func clearHistory() {
        history.removeAll()
        logger.logButtonPress("Clear All History", location: "Settings")
        saveHistory()
    }
    
    func addBookmark() {
        guard let webView = webView, 
                let url = webView.url?.absoluteString, 
                !url.isEmpty, 
                url != "about:blank" else {
            bookmarkAlertMessage = "Cannot bookmark this page"
            showingBookmarkAlert = true
            return
        }
        
        let title = webView.title ?? "Untitled"
        
        if bookmarks.contains(where: { $0.url == url }) {
            bookmarkAlertMessage = "Already bookmarked!"
            showingBookmarkAlert = true
            return
        }
        
        let newBookmark = Bookmark(url: url, title: title)
        bookmarks.append(newBookmark)
        logger.logButtonPress("Add Bookmark", location: "Toolbar")
        saveBookmarks()
        
        bookmarkAlertMessage = "Bookmark added!"
        showingBookmarkAlert = true
    }
    
    func removeBookmark(_ bookmark: Bookmark) {
        if let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            bookmarks.remove(at: index)
            saveBookmarks()
        }
    }
    
    func clearBookmarks() {
        bookmarks.removeAll()
        logger.logButtonPress("Clear All Bookmarks", location: "Settings")
        saveBookmarks()
    }
    
    func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
        showErrorAlert = true
        logger.logError(error.localizedDescription)
    }
    
    private func loadSettings() {
        if let settings = userDefaults.dictionary(forKey: settingsKey) {
            if let engineString = settings["searchEngine"] as? String,
               let engine = SearchEngine(rawValue: engineString) {
                selectedSearchEngine = engine
            }
            isDarkMode = settings["isDarkMode"] as? Bool ?? false
        }
    }
    
    func saveSettings() {
        let settings: [String: Any] = [
            "searchEngine": selectedSearchEngine.rawValue,
            "isDarkMode": isDarkMode
        ]
        userDefaults.set(settings, forKey: settingsKey)
    }
    
    private func loadHistory() {
        if let historyData = userDefaults.data(forKey: historyKey),
           let decodedHistory = try? JSONDecoder().decode([HistoryItem].self, from: historyData) {
            history = decodedHistory
        }
    }
    
    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(history) {
            userDefaults.set(encoded, forKey: historyKey)
        }
    }
    
    private func loadBookmarks() {
        if let bookmarksData = userDefaults.data(forKey: bookmarksKey),
           let decodedBookmarks = try? JSONDecoder().decode([Bookmark].self, from: bookmarksData) {
            bookmarks = decodedBookmarks
        }
    }
    
    private func saveBookmarks() {
        if let encoded = try? JSONEncoder().encode(bookmarks) {
            userDefaults.set(encoded, forKey: bookmarksKey)
        }
    }
    
    private func loadTabs() {
        if let tabsData = userDefaults.data(forKey: tabsKey),
           let decodedTabs = try? JSONDecoder().decode([BrowserTab].self, from: tabsData) {
            tabs = decodedTabs
        }
    }
    
    private func saveTabs() {
        if let encoded = try? JSONEncoder().encode(tabs) {
            userDefaults.set(encoded, forKey: tabsKey)
        }
    }
    
    private func loadCustomCommands() {
        if let commandsData = userDefaults.data(forKey: commandsKey),
           let decodedCommands = try? JSONDecoder().decode([CustomCommand].self, from: commandsData) {
            customCommands = decodedCommands
        }
    }
    
    private func saveCustomCommands() {
        if let encoded = try? JSONEncoder().encode(customCommands) {
            userDefaults.set(encoded, forKey: commandsKey)
        }
    }
    
    // Download functionality
    func startDownload(from url: URL) {
        let downloadItem = DownloadItem(url: url, filename: url.lastPathComponent)
        downloads.append(downloadItem)
        
        let task = URLSession.shared.downloadTask(with: url) { [weak self] tempURL, _, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.handleError(error)
                    self?.downloads.removeAll { $0.url == url }
                    return
                }
                
                guard let tempURL = tempURL else { return }
                
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let destinationURL = documentsPath.appendingPathComponent(url.lastPathComponent)
                
                do {
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    
                    try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                    
                    if let index = self?.downloads.firstIndex(where: { $0.url == url }) {
                        self?.downloads[index].isDownloading = false
                        self?.downloads[index].isCompleted = true
                        self?.downloads[index].progress = 1.0
                    }
                    
                    self?.logger.logEvent("Download Completed", details: "\(url.lastPathComponent)")
                } catch {
                    self?.handleError(error)
                }
            }
        }
        
        task.resume()
        simulateDownloadProgress(for: downloadItem.id)
        logger.logEvent("Download Started", details: "\(url.lastPathComponent)")
    }
    
    private func simulateDownloadProgress(for downloadId: UUID) {
        DispatchQueue.global().async { [weak self] in
            for progress in stride(from: 0.0, through: 0.9, by: 0.1) {
                Thread.sleep(forTimeInterval: 0.5)
                
                DispatchQueue.main.async {
                    if let index = self?.downloads.firstIndex(where: { $0.id == downloadId }) {
                        self?.downloads[index].progress = progress
                    }
                }
            }
        }
    }
    
    func clearDownloads() {
        downloads.removeAll()
        logger.logButtonPress("Clear Downloads", location: "Downloads")
    }
    
    func openDownloadsFolder() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if UIApplication.shared.canOpenURL(documentsPath) {
            UIApplication.shared.open(documentsPath)
        }
    }
}

extension BrowserModel: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        loadProgress = 0.1
        logger.logNavigation("Started loading", url: webView.url?.absoluteString)
    }
    
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        loadProgress = 0.5
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        loadProgress = 1.0
        
        if let url = webView.url?.absoluteString {
            currentURL = url
            canGoBack = webView.canGoBack
            canGoForward = webView.canGoForward
            let title = webView.title ?? "Untitled"
            
            logger.logNavigation("Page loaded successfully", url: "\(title) - \(url)")
            addToHistory(url: url, title: title)
            updateActiveTabURL(url, title: title)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.loadProgress = 0.0
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        loadProgress = 0.0
        logger.logError(error.localizedDescription, context: "Page Load")
        handleError(error)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        loadProgress = 0.0
        logger.logError(error.localizedDescription, context: "Provisional Navigation")
        handleError(error)
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url?.absoluteString {
            logger.logNavigation("Navigation request", url: url)
            
            if url.contains("startpage.com/sp/search") {
                currentURL = url
                updateActiveTabURL(url)
            }
            
            if let urlObj = navigationAction.request.url, shouldDownloadFile(from: urlObj) {
                decisionHandler(.cancel)
                startDownload(from: urlObj)
                return
            }
        }
        
        decisionHandler(.allow)
    }
    
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        if let url = webView.url?.absoluteString {
            logger.logNavigation("Received server redirect", url: url)
            currentURL = url
            updateActiveTabURL(url)
        }
    }
    
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            currentURL = url.absoluteString
            loadURL()
        }
        return nil
    }
    
    private func shouldDownloadFile(from url: URL) -> Bool {
        let downloadExtensions: Set<String> = [
            "pdf", "zip", "rar", "7z", "tar", "gz", "dmg", "pkg",
            "doc", "docx", "xls", "xlsx", "ppt", "pptx",
            "mp3", "mp4", "mov", "avi", "wmv", "flv", "mkv",
            "jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp",
            "txt", "rtf", "csv", "json", "xml", "html", "htm",
            "epub", "mobi", "azw", "exe", "apk", "ipa", "deb"
        ]
        
        return downloadExtensions.contains(url.pathExtension.lowercased())
    }
}

struct ContentView: View {
    @StateObject private var browserModel = BrowserModel()
    @State private var showingSettings = false
    @State private var showingHistory = false
    @State private var showingBookmarks = false
    @State private var showingActivityLog = false
    
    var body: some View {
        ZStack {
            Color(browserModel.isDarkMode ? .systemBackground : .white)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                headerView
                
                if browserModel.showTabView {
                    TabGridView(browserModel: browserModel)
                } else if browserModel.showingDownloads {
                    DownloadsView(browserModel: browserModel)
                } else {
                    WebView(browserModel: browserModel)
                        .overlay(
                            Group {
                                if browserModel.isLoading {
                                    LoadingOverlayView(isDarkMode: browserModel.isDarkMode)
                                }
                            }
                        )
                    
                    if browserModel.showDevConsole {
                        DeveloperConsoleView(browserModel: browserModel)
                    }
                    
                    toolbarView
                }
            }
        }
        .preferredColorScheme(browserModel.isDarkMode ? .dark : .light)
        .sheet(isPresented: $showingSettings) {
            SettingsView(browserModel: browserModel, showingActivityLog: $showingActivityLog)
        }
        .sheet(isPresented: $showingHistory) {
            HistoryView(browserModel: browserModel)
        }
        .sheet(isPresented: $showingBookmarks) {
            BookmarksView(browserModel: browserModel)
        }
        .sheet(isPresented: $showingActivityLog) {
            ActivityLogView(browserModel: browserModel)
        }
        .sheet(isPresented: $browserModel.showingCommandEditor) {
            CustomCommandEditorView(browserModel: browserModel)
        }
        .alert("Error", isPresented: $browserModel.showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(browserModel.errorMessage)
        }
        .alert("Bookmark", isPresented: $browserModel.showingBookmarkAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(browserModel.bookmarkAlertMessage)
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button(action: { browserModel.toggleTabView() }) {
                    Image(systemName: "square.on.square")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(browserModel.isDarkMode ? .white : .black)
                        .frame(width: 32, height: 32)
                }
                
                Button(action: { browserModel.goBack() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(browserModel.canGoBack ? (browserModel.isDarkMode ? .white : .black) : .gray)
                        .frame(width: 32, height: 32)
                }
                .disabled(!browserModel.canGoBack)
                
                Button(action: { browserModel.goForward() }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(browserModel.canGoForward ? (browserModel.isDarkMode ? .white : .black) : .gray)
                        .frame(width: 32, height: 32)
                }
                .disabled(!browserModel.canGoForward)
                
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                    
                    TextField("Search or enter URL", text: $browserModel.currentURL)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 16))
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onSubmit { browserModel.loadURL() }
                    
                    if !browserModel.currentURL.isEmpty {
                        Button(action: { browserModel.currentURL = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(browserModel.isDarkMode ? Color(.systemGray5) : Color(.systemGray6))
                .cornerRadius(8)
                
                Button(action: { browserModel.reload() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(browserModel.isDarkMode ? .white : .black)
                        .frame(width: 32, height: 32)
                }
                
                Button(action: { browserModel.createNewTab() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(browserModel.isDarkMode ? .white : .black)
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal, 12)
            
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: geometry.size.width * browserModel.loadProgress, height: 2)
            }
            .frame(height: 2)
        }
        .padding(.vertical, 8)
        .background(browserModel.isDarkMode ? Color(.systemBackground) : Color.white)
        .overlay(
            Rectangle()
                .fill(browserModel.isDarkMode ? Color(.systemGray4) : Color(.systemGray3))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
    
    private var toolbarView: some View {
        HStack {
            ToolbarButton(icon: "house", title: "Home", isDarkMode: browserModel.isDarkMode) {
                browserModel.loadHomepage()
            }
            
            Spacer()
            
            ToolbarButton(icon: "clock", title: "History", isDarkMode: browserModel.isDarkMode) {
                showingHistory = true
            }
            
            Spacer()
            
            ToolbarButton(icon: "bookmark", title: "Bookmark", isDarkMode: browserModel.isDarkMode) {
                browserModel.addBookmark()
            }
            
            Spacer()
            
            ToolbarButton(icon: "arrow.down.circle", title: "Downloads", isDarkMode: browserModel.isDarkMode) {
                browserModel.toggleDownloads()
            }
            
            Spacer()
            
            ToolbarButton(
                icon: browserModel.isDarkMode ? "sun.max" : "moon",
                title: browserModel.isDarkMode ? "Light" : "Dark",
                isDarkMode: browserModel.isDarkMode
            ) {
                browserModel.toggleDarkMode()
            }
            
            Spacer()
            
            ToolbarButton(icon: "terminal", title: "Console", isDarkMode: browserModel.isDarkMode) {
                browserModel.toggleDevConsole()
            }
            
            Spacer()
            
            ToolbarButton(icon: "gear", title: "Settings", isDarkMode: browserModel.isDarkMode) {
                showingSettings = true
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(browserModel.isDarkMode ? Color(.systemBackground) : Color.white)
        .overlay(
            Rectangle()
                .fill(browserModel.isDarkMode ? Color(.systemGray4) : Color(.systemGray3))
                .frame(height: 0.5),
            alignment: .top
        )
    }
}

struct DownloadsView: View {
    @ObservedObject var browserModel: BrowserModel
    
    var body: some View {
        NavigationView {
            VStack {
                if browserModel.downloads.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("No Downloads")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Downloaded files will appear here")
                            .font(.body)
                            .foregroundColor(.gray)
                        
                        Button(action: { browserModel.openDownloadsFolder() }) {
                            Text("Open Downloads Folder")
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .padding(.top, 20)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(browserModel.downloads) { download in
                            DownloadItemView(download: download)
                        }
                        .onDelete { indexSet in
                            indexSet.forEach { index in
                                if browserModel.downloads.indices.contains(index) {
                                    browserModel.downloads.remove(at: index)
                                }
                            }
                        }
                    }
                    
                    HStack {
                        Button("Clear All") {
                            browserModel.clearDownloads()
                        }
                        .foregroundColor(.red)
                        .padding()
                        
                        Spacer()
                        
                        Button("Open Folder") {
                            browserModel.openDownloadsFolder()
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        browserModel.showingDownloads = false
                    }
                }
            }
        }
    }
}

struct DownloadItemView: View {
    let download: DownloadItem
    
    var body: some View {
        HStack {
            Image(systemName: download.isCompleted ? "checkmark.circle.fill" : "arrow.down.circle")
                .foregroundColor(download.isCompleted ? .green : .blue)
            
            VStack(alignment: .leading) {
                Text(download.filename)
                    .font(.headline)
                    .lineLimit(1)
                
                if download.isDownloading {
                    ProgressView(value: download.progress)
                        .progressViewStyle(LinearProgressViewStyle())
                    Text("Downloading...")
                        .font(.caption)
                        .foregroundColor(.gray)
                } else {
                    Text("Completed")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            
            Spacer()
            
            if download.isDownloading {
                Text("\(Int(download.progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TabGridView: View {
    @ObservedObject var browserModel: BrowserModel
    
    var body: some View {
        VStack {
            HStack {
                Text("Tabs (\(browserModel.tabs.count))")
                    .font(.headline)
                    .foregroundColor(browserModel.isDarkMode ? .white : .black)
                
                Spacer()
                
                Button("Done") {
                    browserModel.showTabView = false
                }
                .foregroundColor(.blue)
            }
            .padding()
            
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 16) {
                    ForEach(browserModel.tabs) { tab in
                        TabViewItem(tab: tab, browserModel: browserModel)
                    }
                    
                    Button(action: { browserModel.createNewTab() }) {
                        VStack {
                            Image(systemName: "plus")
                                .font(.title2)
                                .foregroundColor(browserModel.isDarkMode ? .white : .black)
                            Text("New Tab")
                                .font(.caption)
                                .foregroundColor(browserModel.isDarkMode ? .white : .black)
                        }
                        .frame(width: 150, height: 120)
                        .background(browserModel.isDarkMode ? Color(.systemGray5) : Color(.systemGray6))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
        .background(browserModel.isDarkMode ? Color(.systemBackground) : Color.white)
    }
}

struct TabViewItem: View {
    let tab: BrowserTab
    @ObservedObject var browserModel: BrowserModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Rectangle()
                    .fill(browserModel.isDarkMode ? Color(.systemGray5) : Color(.systemGray6))
                    .frame(height: 80)
                    .cornerRadius(6)
                
                VStack {
                    Image(systemName: "globe")
                        .font(.title)
                        .foregroundColor(.gray)
                    Text(tab.title.prefix(20))
                        .font(.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .padding()
                
                Button(action: { browserModel.closeTab(tab.id) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.red)
                        .background(Color.white.clipShape(Circle()))
                }
                .offset(x: 8, y: -8)
            }
            
            Text(tab.title.prefix(30))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(browserModel.isDarkMode ? .white : .black)
                .lineLimit(1)
            
            Text(tab.url.prefix(30))
                .font(.system(size: 10))
                .foregroundColor(.gray)
                .lineLimit(1)
        }
        .frame(width: 150)
        .onTapGesture {
            browserModel.switchToTab(tab.id)
            browserModel.showTabView = false
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tab.isActive ? Color.blue : Color.clear, lineWidth: 2)
        )
    }
}

struct DeveloperConsoleView: View {
    @ObservedObject var browserModel: BrowserModel
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Developer Console")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(browserModel.isDarkMode ? .white : .black)
                
                Spacer()
                
                Button(action: { browserModel.showingCommandEditor = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(browserModel.isDarkMode ? .white : .black)
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: { browserModel.clearConsole() }) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(browserModel.isDarkMode ? .white : .black)
                    }
                    
                    Button(action: { 
                        browserModel.executeQuickCommand("console.log('Elements:', document.querySelectorAll('*').length)")
                    }) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(browserModel.isDarkMode ? .white : .black)
                    }
                    
                    Button(action: { browserModel.showDevConsole = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(browserModel.isDarkMode ? .white : .black)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(browserModel.isDarkMode ? Color(.systemGray5) : Color(.systemGray4))
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(browserModel.customCommands) { command in
                        CustomCommandButton(command: command, browserModel: browserModel)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(browserModel.isDarkMode ? Color(.systemGray6) : Color(.systemGray5))
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(browserModel.consoleMessages, id: \.self) { message in
                        Text(message)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(browserModel.isDarkMode ? .white : .black)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(height: 200)
            .background(browserModel.isDarkMode ? Color(.systemBackground) : Color.white)
            
            HStack {
                TextField("Enter JavaScript command...", text: $browserModel.consoleInput)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 14, design: .monospaced))
                    .padding(8)
                    .background(browserModel.isDarkMode ? Color(.systemGray5) : Color(.systemGray6))
                    .cornerRadius(6)
                    .foregroundColor(browserModel.isDarkMode ? .white : .black)
                    .onSubmit { browserModel.executeConsoleCommand() }
                
                Button(action: { browserModel.executeConsoleCommand() }) {
                    Image(systemName: "return")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(browserModel.isDarkMode ? .white : .black)
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(browserModel.isDarkMode ? Color(.systemGray5) : Color(.systemGray4))
        }
        .background(browserModel.isDarkMode ? Color(.systemBackground) : Color.white)
    }
}

struct CustomCommandButton: View {
    let command: CustomCommand
    @ObservedObject var browserModel: BrowserModel
    @State private var showingDeleteAlert = false
    
    var body: some View {
        Button(action: { browserModel.executeCustomCommand(command) }) {
            HStack(spacing: 4) {
                Image(systemName: command.icon)
                    .font(.system(size: 12))
                Text(command.name)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.blue)
            .cornerRadius(6)
        }
        .contextMenu {
            Button(role: .destructive) {
                showingDeleteAlert = true
            } label: {
                Label("Delete Command", systemImage: "trash")
            }
        }
        .alert("Delete Command?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                browserModel.deleteCustomCommand(command)
            }
        } message: {
            Text("Are you sure you want to delete \"\(command.name)\"?")
        }
    }
}

struct CustomCommandEditorView: View {
    @ObservedObject var browserModel: BrowserModel
    @Environment(\.dismiss) private var dismiss
    
    let commonIcons = ["terminal", "bell", "link", "text.bubble", "square.grid.2x2", "doc.text", "person", "gearshape", "network", "cursorarrow.click"]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Command Details")) {
                    TextField("Command Name", text: $browserModel.newCommandName)
                    TextField("JavaScript Code", text: $browserModel.newCommandCode)
                        .lineLimit(3)
                }
                
                Section(header: Text("Icon")) {
                    Picker("Select Icon", selection: $browserModel.newCommandIcon) {
                        ForEach(commonIcons, id: \.self) { icon in
                            HStack {
                                Image(systemName: icon)
                                Text(icon)
                            }.tag(icon)
                        }
                    }
                    .pickerStyle(WheelPickerStyle())
                    .frame(height: 150)
                }
                
                Section {
                    Button("Add Command") {
                        browserModel.addCustomCommand()
                        dismiss()
                    }
                    .disabled(browserModel.newCommandName.isEmpty || browserModel.newCommandCode.isEmpty)
                }
            }
            .navigationTitle("New Custom Command")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct ActivityLogView: View {
    @ObservedObject var browserModel: BrowserModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                if browserModel.logger.getLogContents().isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("No Activity Logs")
                            .font(.title2)
                            .fontWeight(.medium)
                        Text("Your activity will appear here!")
                            .font(.body)
                            .foregroundColor(.gray)
                    }
                    .padding()
                } else {
                    ScrollView {
                        Text(browserModel.logger.getLogContents())
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(browserModel.isDarkMode ? .white : .black)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                }
            }
            .navigationTitle("Activity Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Clear Logs") {
                        browserModel.logger.clearLogs()
                    }
                    .foregroundColor(.red)
                    .disabled(browserModel.logger.getLogContents().isEmpty)
                }
            }
        }
        .preferredColorScheme(browserModel.isDarkMode ? .dark : .light)
    }
}

struct ToolbarButton: View {
    let icon: String
    let title: String
    let isDarkMode: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(isDarkMode ? .white : .black)
                Text(title)
                    .font(.system(size: 10))
                    .foregroundColor(isDarkMode ? .white : .black)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct WebView: UIViewRepresentable {
    @ObservedObject var browserModel: BrowserModel
    
    func makeUIView(context: Context) -> WKWebView {
        browserModel.webView ?? WKWebView()
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct LoadingOverlayView: View {
    let isDarkMode: Bool
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.1)
                .ignoresSafeArea()
            
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                    .progressViewStyle(CircularProgressViewStyle(tint: isDarkMode ? .white : .black))
                
                Text("Loading...")
                    .font(.system(size: 14))
                    .foregroundColor(isDarkMode ? .white : .black)
            }
            .padding(20)
            .background(isDarkMode ? Color(.systemGray5) : Color.white)
            .cornerRadius(8)
            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var browserModel: BrowserModel
    @Binding var showingActivityLog: Bool
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Search Engine")) {
                    Picker("Default Search Engine", selection: $browserModel.selectedSearchEngine) {
                        ForEach(SearchEngine.allCases, id: \.self) { engine in
                            Text(engine.rawValue).tag(engine)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: browserModel.selectedSearchEngine) { _ in
                        browserModel.saveSettings()
                    }
                }
                
                Section(header: Text("Appearance")) {
                    Toggle("Dark Mode", isOn: $browserModel.isDarkMode)
                        .onChange(of: browserModel.isDarkMode) { _ in
                            browserModel.saveSettings()
                        }
                }
                
                Section(header: Text("Tabs")) {
                    Text("Open tabs: \(browserModel.tabs.count)")
                    Text("Active tab: \(browserModel.activeTab?.title ?? "None")")
                }
                
                Section(header: Text("Downloads")) {
                    Text("Downloads folder: Documents/")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Button("Open Downloads Folder") {
                        browserModel.openDownloadsFolder()
                    }
                }
                
                Section(header: Text("Developer")) {
                    Text("Console: Tap the terminal icon to open developer tools")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Button("View Activity Log") {
                        showingActivityLog = true
                        dismiss()
                    }
                }
                
                Section(header: Text("Privacy")) {
                    Button("Clear All History") {
                        browserModel.clearHistory()
                    }
                    .foregroundColor(.red)
                    
                    Button("Clear All Bookmarks") {
                        browserModel.clearBookmarks()
                    }
                    .foregroundColor(.red)
                }
                
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.3.0")
                            .foregroundColor(.gray)
                    }
                    
                    HStack {
                        Text("App Name")
                        Spacer()
                        Text("ClapBrowse")
                            .foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(browserModel.isDarkMode ? .dark : .light)
    }
}

struct HistoryView: View {
    @ObservedObject var browserModel: BrowserModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Group {
                if browserModel.history.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("No History")
                            .font(.title2)
                            .fontWeight(.medium)
                        Text("Your browsing history will appear here")
                            .font(.body)
                            .foregroundColor(.gray)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(browserModel.history.reversed(), id: \.id) { item in
                            Button(action: {
                                browserModel.currentURL = item.url
                                browserModel.loadURL()
                                dismiss()
                            }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text(item.url)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .onDelete(perform: browserModel.deleteHistoryItems)
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
                if !browserModel.history.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        EditButton()
                    }
                }
            }
        }
        .preferredColorScheme(browserModel.isDarkMode ? .dark : .light)
    }
}

struct BookmarksView: View {
    @ObservedObject var browserModel: BrowserModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Group {
                if browserModel.bookmarks.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("No Bookmarks")
                            .font(.title2)
                            .fontWeight(.medium)
                        Text("Add bookmarks by tapping the bookmark icon")
                            .font(.body)
                            .foregroundColor(.gray)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(browserModel.bookmarks) { bookmark in
                            BookmarkRow(bookmark: bookmark, browserModel: browserModel, dismiss: dismiss)
                        }
                        .onDelete { indexSet in
                            indexSet.forEach { index in
                                if browserModel.bookmarks.indices.contains(index) {
                                    browserModel.removeBookmark(browserModel.bookmarks[index])
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
                if !browserModel.bookmarks.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        EditButton()
                    }
                }
            }
        }
        .preferredColorScheme(browserModel.isDarkMode ? .dark : .light)
    }
}

struct BookmarkRow: View {
    let bookmark: Bookmark
    @ObservedObject var browserModel: BrowserModel
    let dismiss: DismissAction
    
    var body: some View {
        Button(action: {
            browserModel.currentURL = bookmark.url
            browserModel.loadURL()
            dismiss()
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bookmark.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(bookmark.url)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Button(action: { browserModel.removeBookmark(bookmark) }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
