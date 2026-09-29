import SwiftUI

@main struct PGNAnnotatorApp: App {
    var body: some Scene {
        // The first scene is what appears at launch, so the welcome window
        // replaces the open panel that a document app would normally show.
        Window("Welcome to PGN Annotator", id: welcomeWindowID) {
            WelcomeView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .keyboardShortcut("1", modifiers: [.command, .shift])

        DocumentGroup(newDocument: { PGNDocument() }) { file in
            ContentView(document: file.document, fileURL: file.fileURL)
        }
        .defaultSize(width: 1000, height: 700)
    }
}
