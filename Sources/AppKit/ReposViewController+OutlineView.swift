import AppKit
import Cake

extension ReposViewController: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let login = item as? String {
            return rootedRepos[login]!.count
        } else {
            return rootedRepos.keys.count
        }
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return item is String
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let login = item as? String {
            return rootedRepos[login]![index]
        } else {
            return rootedReposKeys[index]
        }
    }

    func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
        switch tableColumn {
        case mainColumn:
            if item is String {
                return item
            } else {
                return (item as! Repo).full_name
            }
        case statusColumn:
            if let repo = item as? Repo, enrollments.contains(repo) {
                if repo.isPartOfOrganization && hooked.contains(.organization(repo.owner.login)) || hooked.contains(repo) {
                    return "✓"
                } else if !fetching {
                    return "⚠"
                } else {
                    return nil
                }
            } else if fetching {
                return nil
            } else if let repo = item as? Repo, !repo.permissions.admin {
                if !repo.isPartOfOrganization, !hooked.contains(repo) {
                    return "⚠"
                } else if !hooked.contains(.organization(repo.owner.login)) {
                    return "⚠"
                } else {
                    return nil
                }
            } else {
                return nil
            }
        default:
            return nil
        }
    }
}

extension ReposViewController: NSOutlineViewDelegate {
    func outlineViewSelectionDidChange(_: Notification) {

        startupTipsContainer.isHidden = true
        notifyButton.isHidden = false

        enum State {
            case fetching
            case noSelection
            case selected(Kind)

            enum Kind {
                case organization(Satisfaction, enable: Bool)
                case user(Satisfaction, enable: Bool)
                case repo(enrolled: Bool, hookable: Hookable)

                enum Hookable {
                    case `true`
                    case contact(String)
                }
            }
        }

        var state: State {
            guard !fetching else {
                return .fetching
            }
            guard let selectedItem = self.selectedItem else {
                return .noSelection
            }
            switch selectedItem {
            case .repository(let repo):
                let enrolled = enrollments.contains(repo)
                var hookable: State.Kind.Hookable {
                    if hooked.contains(repo) {
                        return .true
                    } else if repo.isPartOfOrganization, hooked.contains(.organization(repo.owner.login)) {
                        return .true
                    } else if repo.permissions.admin {
                        return .true
                    } else if repo.isPartOfOrganization {
                        return .contact("an admin of the \(repo.owner.login) organization")
                    } else {
                        return .contact("@\(repo.owner.login)")
                    }
                }
                return .selected(.repo(enrolled: enrolled, hookable: hookable))
            case .organization(let login):
                let repos = rootedRepos[login]!
                let enrollment = repos.satisfaction{ enrollments.contains($0) }
                let enable = hasVerifiedReceipt || repos.satisfaction(\.`private`) == .none || repos.satisfaction(\.permissions.admin) == .all || hooked.contains(.organization(login))
                return .selected(.organization(enrollment, enable: enable))
            case .user(let login):
                let repos = rootedRepos[login]!
                let enrollment = rootedRepos[login]!.satisfaction{ enrollments.contains($0) }
                let enable = hasVerifiedReceipt || repos.satisfaction(\.`private`) == .none || repos.satisfaction(\.permissions.admin) == .all || repos.satisfaction{ hooked.contains($0) } == .all
                return .selected(.user(enrollment, enable: enable))
            }
        }

        var status: String
        let enable: Bool
        let switcH: SwitchState
        let config: Bool

        //TODO if they are subscribed but the subscription has lapsed
        // we should flag that with an alert symbol and text below

        configureButton.isHidden = false

        switch state {
        case .fetching:
            status = "One moment…"
            enable = false
            switcH = .off
            config = false
        case .noSelection:
            status = ""
            enable = false
            switcH = .off
            config = false
        case .selected(.organization(.all, _)):
            status = "All repositories are enrolled for push notifications."
            enable = true
            switcH = .on
            config = false
        case .selected(.organization(.none, let enablE)):
            status = "No repositories are enrolled for push notifications."
            enable = enablE
            switcH = .off
            config = false
            if !enablE { status = "You cannot install the organization webhook, contact an administrator.\n\n" + status }
        case .selected(.organization(.some, let enablE)):
            status = "Some repositories are enrolled for push notifications."
            enable = enablE
            switcH = .mixed
            config = false
            if !enablE { status = "You cannot install the organization webhook, contact an administrator.\n\n" + status }
        case .selected(.user(.all, _)):
            status = "All this user’s repositories are enrolled for push notifications."
            enable = true
            switcH = .on
            config = false
        case .selected(.user(.none, let enablE)):
            status = "You are not enrolled for push notifications for any of this user’s repositories."
            enable = enablE
            switcH = .off
            config = false
            if !enablE { status = "You cannot install webhooks, contact the user.\n\n" + status }
        case .selected(.user(.some, let enablE)):
            status = "Some of this user’s repositories are enrolled for push notifications."
            enable = enablE
            switcH = .mixed
            config = false
            if !enablE { status = "You cannot install webhooks, contact the user.\n\n" + status }
        case .selected(.repo(true, _)):
            //TODO
//            if !hooked.contains(repo.isPartOfOrganization ? .organization(repo.owner.login) : .init(repo)) {
//                status = "No webhook is installed, notifications will not be sent."
//            } else {
                status = ""
//            }
            enable = true
            switcH = .on
            config = true
            if configureEnrollmentsViewController != nil {
                updateConfigureEnrollmentsViewController()
            }
        case .selected(.repo(false, hookable: .true)):
            status = ""
            enable = true
            switcH = .off
            config = false
        case .selected(.repo(false, hookable: .contact(let owner))):
            status = """
                You do not have permission to install webhooks on this repository.

                Contact \(owner) and ask them to install the Canopy webhook (it’s free!).

                They can use the app, or do it manually (there are instructions at the Canopy website).
                """
            enable = false
            switcH = .off
            config = false
        }

        switch switcH {
        case .mixed:
            notifyButton.allowsMixedState = true
            notifyButton.state = .mixed
        case .on, .off:
            notifyButton.allowsMixedState = false
            notifyButton.state = switcH.nsControlStateValue
        }

        notifyButton.isEnabled = enable
        statusLabel.stringValue = status
        configureButton.isHidden = !config

        if !config, let window = configureEnrollmentsViewController?.view.window {
            window.close()
        }
        if config {
            configureButton.state = configureEnrollmentsViewController == nil ? .off : .on
        }
    }

    func outlineView(_ outlineView: NSOutlineView, dataCellFor tableColumn: NSTableColumn?, item: Any) -> NSCell? {
        guard let cell = tableColumn?.dataCell(forRow: 0) as? NSTextFieldCell else {
            return nil
        }
        let integrated: Bool
        if let login = item as? String {
            integrated = rootedRepos[login]!.satisfaction{ enrollments.contains($0) } == .all
        } else if let repo = item as? Repo {
            integrated = enrollments.contains(repo)
        } else {
            return nil
        }
        cell.isEnabled = integrated
        return cell
    }
}
