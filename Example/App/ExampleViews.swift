import SwiftUI

struct RootView: View {
    @ObservedObject var model: ExampleModel
    @ObservedObject var log: ExampleLog

    var body: some View {
        TabView {
            tab(SetupView(model: model), "Setup", "gearshape")
            tab(IdentityView(model: model), "Identity", "person")
            tab(TagsView(model: model), "Tags", "tag")
            tab(NotificationsView(model: model), "Push", "bell")
            tab(LogView(log: log), "Log", "list.bullet")
        }
    }

    private func tab<Content: View>(_ content: Content, _ title: String, _ icon: String) -> some View {
        NavigationView { content.navigationTitle(title).navigationBarTitleDisplayMode(.inline) }
            .navigationViewStyle(.stack)
            .tabItem { Label(title, systemImage: icon) }
    }
}

private struct NotConfiguredBanner: View {
    let model: ExampleModel
    var body: some View {
        if !model.isConfigured {
            Section {
                Text("Not configured: the SDK is never called. Set NOTTI_APP_ID and NOTTI_CLIENT_KEY in Config/Example.local.xcconfig.")
                    .foregroundColor(.orange)
            }
        }
    }
}

struct SetupView: View {
    @ObservedObject var model: ExampleModel

    var body: some View {
        Form {
            NotConfiguredBanner(model: model)
            Section("State") {
                StateRow("Configured", model.isConfigured ? "yes" : "no")
                StateRow("Initialized", model.isInitialized ? "yes" : "no")
                StateRow("Device id", model.deviceId ?? "none")
                StateRow("Swizzling", model.manualForwardingEnabled ? "off (manual forwarding)" : "on")
            }
            Section("Actions") {
                Button("Initialize") { model.initialize() }
                Button("Refresh device id") { model.refreshDeviceId() }
                Picker("Log level", selection: Binding(get: { model.logLevel }, set: { model.setLogLevel($0) })) {
                    ForEach(ExampleLogLevel.allCases) { Text($0.rawValue).tag($0) }
                }
            }
        }
    }
}

struct IdentityView: View {
    @ObservedObject var model: ExampleModel
    @State private var userId = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var subscribed = true
    @State private var location = false

    var body: some View {
        Form {
            NotConfiguredBanner(model: model)
            Section("User") {
                TextField("External user id", text: $userId).textInputAutocapitalization(.never)
                Button("Login") { model.login(userId) }
                Button("Logout") { model.logout() }
            }
            Section("Email") {
                TextField("Email", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                Button("Set email") { model.setEmail(email); email = "" }
                Button("Clear email") { model.clearEmail() }
            }
            Section("Phone") {
                TextField("Phone", text: $phone).keyboardType(.phonePad)
                Button("Set phone") { model.setPhone(phone); phone = "" }
                Button("Clear phone") { model.clearPhone() }
            }
            Section("Preferences") {
                Toggle("Subscription", isOn: $subscribed).onChange(of: subscribed) { model.setSubscription($0) }
                Toggle("Share location (country)", isOn: $location).onChange(of: location) { model.setLocationSharing($0) }
            }
        }
    }
}

struct TagsView: View {
    @ObservedObject var model: ExampleModel
    @State private var key = ""
    @State private var value = ""
    @State private var many = ""
    @State private var removeKey = ""
    @State private var removeMany = ""

    var body: some View {
        Form {
            NotConfiguredBanner(model: model)
            Section("One tag") {
                TextField("Key", text: $key).textInputAutocapitalization(.never)
                TextField("Value", text: $value)
                Button("Add tag") { model.addTag(key: key, value: value) }
                TextField("Key to remove", text: $removeKey).textInputAutocapitalization(.never)
                Button("Remove tag") { model.removeTag(removeKey) }
            }
            Section("Many (k1=v1, k2=v2)") {
                TextField("Tags", text: $many).textInputAutocapitalization(.never)
                Button("Add tags") { model.addTags(many) }
                TextField("Keys (k1, k2)", text: $removeMany).textInputAutocapitalization(.never)
                Button("Remove tags") { model.removeTags(removeMany) }
            }
        }
    }
}

struct NotificationsView: View {
    @ObservedObject var model: ExampleModel

    var body: some View {
        Form {
            NotConfiguredBanner(model: model)
            Section("Permission: \(model.permission)") {
                Button("Request permission (async)") { Task { await model.requestPermission() } }
                Button("Request permission (completion)") { model.requestPermissionWithCompletion() }
            }
            Section("Listeners (received, clicked, device id)") {
                Button(model.isListening ? "Listening" : "Add listeners") { model.startListening() }
                    .disabled(model.isListening)
                Button("Remove listeners") { model.stopListening() }
                    .disabled(!model.isListening)
                Button("Take initial click") { model.takeInitialClick() }
            }
            Section("In-App messages") {
                Button("Track event") { model.trackEvent() }
                Text("The click listener is added at Initialize and logs the action type only.")
                    .foregroundColor(.secondary)
            }
            if model.manualForwardingEnabled {
                Section("Manual forwarding") {
                    Text("NottiDisableSwizzling is on: the app delegate forwards the five delegate calls to the SDK.")
                }
            }
        }
    }
}

struct LogView: View {
    @ObservedObject var log: ExampleLog

    var body: some View {
        List {
            if log.rows.isEmpty { Text("No events yet.").foregroundColor(.secondary) }
            ForEach(Array(log.rows.enumerated().reversed()), id: \.offset) { _, row in
                Text(row).font(.system(.footnote, design: .monospaced))
            }
        }
        .toolbar { Button("Clear") { log.clear() } }
    }
}

private struct StateRow: View {
    let title: String
    let value: String

    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundColor(.secondary)
        }
    }
}
