import PromiseKit
import AppKit

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
        if item is String {
            return item
        } else {
            return (item as! Repo).full_name
        }
    }
}

extension ReposViewController: NSOutlineViewDelegate {
    func outlineViewSelectionDidChange(_ notification: Notification) {
        let defaultWebhookExplanation = "Canopy functions via GitHub webhooks"
        notifyButton.isEnabled = false
        installWebhookButton.isEnabled = false
        installWebhookFirstLabel.isHidden = true
        privateReposAdviceLabel.isHidden = true
        webhookExplanation.stringValue = defaultWebhookExplanation

        guard let selectedItem = self.selectedItem else {
            return
        }

        notifyButton.allowsMixedState = true
        notifyButton.state = state(for: selectedItem).nsControlStateValue
        if notifyButton.state != .mixed {
            notifyButton.allowsMixedState = false
            // ^^ otherwise clicking transitions to the “mixed” state
        }

        switch selectedItem {
        case .organization(let login):
            privateReposAdviceLabel.isHidden = rootedRepos[login]!.allSatisfy{ !$0.private }
            installWebhookButton.isEnabled = true
        case .user(let login):
            privateReposAdviceLabel.isHidden = rootedRepos[login]!.allSatisfy{ !$0.private }
            installWebhookButton.isEnabled = false
        case .repo(let repo):
            privateReposAdviceLabel.isHidden = !repo.private
            notifyButton.allowsMixedState = false
        }

        let notifyButtonEnabled: Bool
        let webhookButtonEnabled: Bool
        var webhookExplanationText: String

        switch (fetching, selectedItem) {
        case (true, _):
            webhookButtonEnabled = false
            webhookExplanationText = "Fetching hook installation information…"
            notifyButtonEnabled = false
        case (false, .organization(let login)):
            if hooked.contains(.organization(login)) {
                webhookButtonEnabled = false
                webhookExplanationText = "Organization webhook installed"
                notifyButtonEnabled = true
            } else {
                switch rootedRepos[login]!.satisfaction(\.permissions.admin) {
                case .none:
                    webhookButtonEnabled = false
                    webhookExplanationText = "Contact the repo admin to install the webhook"
                case .some:
                    webhookButtonEnabled = false
                    webhookExplanationText = "You do not have admin clearance for all repositories"
                case .all:
                    webhookButtonEnabled = true
                    webhookExplanationText = defaultWebhookExplanation
                }
                notifyButtonEnabled = false
            }
        case (false, .user(let login)):
            let repos = rootedRepos[login]!
            let hooks100pc: Bool
            switch repos.satisfaction({ hooked.contains(.init($0)) }) {
            case .all:
                webhookExplanationText = "All children have webhooks installed"
                hooks100pc = true
            case .some:
                webhookExplanationText = "Some children have webhooks installed"
                hooks100pc = false
            case .none:
                webhookExplanationText = "No children have webhooks installed"
                hooks100pc = false
            }
            switch repos.satisfaction(\.permissions.admin) {
            case .all:
                webhookButtonEnabled = true
                notifyButtonEnabled = true
            case .some, .none:
                webhookButtonEnabled = false
                webhookExplanationText += ". You don’t have clearance to control webhooks on all children."
                notifyButtonEnabled = hooks100pc
            }
        case (false, .repo(let repo)) where repo.isPartOfOrganization:
            notifyButtonEnabled = hooked.contains(.organization(repo.owner.login))
            webhookButtonEnabled = false
            webhookExplanationText = "Webhook is controlled at organization level"
        case (false, .repo(let repo)):
            notifyButtonEnabled = hooked.contains(.init(repo))
            webhookButtonEnabled = repo.permissions.admin
            webhookExplanationText = notifyButtonEnabled
                ? "Webhook installed" : webhookButtonEnabled
                ? defaultWebhookExplanation : "Contact the repo admin to install the webhook"
        }

        self.notifyButton.isEnabled = notifyButtonEnabled
        self.webhookExplanation.stringValue = webhookExplanationText
        self.installWebhookFirstLabel.isHidden = notifyButtonEnabled
        self.installWebhookButton.isEnabled = webhookButtonEnabled && !notifyButtonEnabled
                                                                   // ^^ because we don't support uninstalling hooks yet!
    }

    func outlineView(_ outlineView: NSOutlineView, dataCellFor tableColumn: NSTableColumn?, item: Any) -> NSCell? {
        guard let cell = tableColumn?.dataCell(forRow: 0) as? NSTextFieldCell else {
            return nil
        }
        let integrated: Bool
        if let login = item as? String {
            integrated = rootedRepos[login]!.satisfaction{ subscribed.contains($0.id) } == .all
        } else if let repo = item as? Repo {
            integrated = subscribed.contains(repo.id)
        } else {
            return nil
        }
        cell.textColor = integrated ? .labelColor : .secondaryLabelColor
        return cell
    }
}
