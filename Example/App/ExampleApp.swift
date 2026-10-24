import SwiftUI

@main
struct ExampleApp: App {
    #if USE_ADAPTOR
    @UIApplicationDelegateAdaptor(ExampleAppDelegate.self) private var appDelegate
    #endif
    @StateObject private var model = ExampleModel.live()

    var body: some Scene {
        WindowGroup {
            RootView(model: model, log: model.log)
        }
    }

    /// Whether this build uses `@UIApplicationDelegateAdaptor`. The flag is set on the app target only, so the
    /// hosted tests read it here.
    static var usesAdaptor: Bool {
        #if USE_ADAPTOR
        return true
        #else
        return false
        #endif
    }
}
