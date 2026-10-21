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
}
