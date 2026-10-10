import Observation
import SwiftUI

@MainActor
@Observable
final class PublishingCommandDispatcher {
    enum Command: Sendable {
        case settings
        case publishSite
        case republishAllFiles
        case markAllChanged
        case markAllUnchanged
    }

    struct Request: Identifiable {
        let id = UUID()
        let command: Command
    }

    private(set) var request: Request?

    func send(_ command: Command) {
        request = Request(command: command)
    }
}

private struct PublishingCommandDispatcherKey: FocusedValueKey {
    typealias Value = PublishingCommandDispatcher
}

extension FocusedValues {
    var publishingCommandDispatcher: PublishingCommandDispatcher? {
        get { self[PublishingCommandDispatcherKey.self] }
        set { self[PublishingCommandDispatcherKey.self] = newValue }
    }
}

struct PublishingMenuCommands: Commands {
    @FocusedValue(\.publishingCommandDispatcher) private var dispatcher

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Divider()

            Button("Publishing Settings") {
                dispatcher?.send(.settings)
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(dispatcher == nil)

            Button("Publish Site…") {
                dispatcher?.send(.publishSite)
            }
            .keyboardShortcut("k", modifiers: [.shift, .command])
            .disabled(dispatcher == nil)

            Button("Re-Publish All Files") {
                dispatcher?.send(.republishAllFiles)
            }
            .keyboardShortcut("k", modifiers: [.option, .command])
            .disabled(dispatcher == nil)

            Divider()

            Button("Mark All Pages & Resources as Changed") {
                dispatcher?.send(.markAllChanged)
            }
            .keyboardShortcut("m", modifiers: [.shift, .command])
            .disabled(dispatcher == nil)
            .modifierKeyAlternate(.option) {
                Button("Mark All Pages & Resources as Unchanged") {
                    dispatcher?.send(.markAllUnchanged)
                }
                .keyboardShortcut("m", modifiers: [.option, .shift, .command])
                .disabled(dispatcher == nil)
            }
        }
    }
}
