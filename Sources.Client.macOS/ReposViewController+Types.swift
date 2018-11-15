import AppKit

extension ReposViewController {
    enum OutlineViewItem: Equatable {
        case repo(Repo)
        case organization(login: String, id: Int)
        case user(String)
    }

    enum SwitchState {
        case on
        case off
        case mixed

        init(_ bool: Bool) {
            if bool {
                self = .on
            } else {
                self = .off
            }
        }

        init<T>(_ array: [T], where: (T) -> Bool) {
            guard let first = array.first else {
                self = .off
                return
            }
            let prev = `where`(first)
            for x in array.dropFirst() {
                guard `where`(x) == prev else {
                    self = .mixed
                    return
                }
            }
            self.init(prev)
        }

        var nsControlStateValue: NSControl.StateValue {
            switch self {
            case .on:
                return .on
            case .off:
                return .off
            case .mixed:
                return .mixed
            }
        }
    }
}
