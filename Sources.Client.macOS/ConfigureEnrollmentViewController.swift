import PromiseKit
import AppKit

class MyWindow: NSWindow {
    override var canBecomeKey: Bool {
        return false
    }
}

class ConfigureEnrollmentsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let mgr: EnrollmentsManager

    private let events = Event.allCases.sorted(by: { $0.description < $1.description })

    var enrollment: Enrollment {
        didSet {
            tableView.reloadData()
        }
    }

    init(enrollment: Enrollment, manager: EnrollmentsManager) {
        self.enrollment = enrollment
        self.mgr = manager
        super.init(nibName: nil, bundle: nil)
    }

    required init(coder: NSCoder) {
        fatalError()
    }

    override func loadView() {
        view = scrollView

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.frame = CGRect(x: 0, y: 0, width: 240, height: 600)
        scrollView.horizontalScrollElasticity = .none

        let column1 = NSTableColumn(identifier: .init(rawValue: "NAME_COLUMN"))
        column1.title = "Event"
        tableView.addTableColumn(column1)
        let column2 = NSTableColumn(identifier: .init(rawValue: "ENABLED_COLUMN"))
        column2.title = "Enabled"
        tableView.addTableColumn(column2)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.headerView = nil

        tableView.rowSizeStyle = .small
        tableView.allowsColumnResizing = false
        tableView.allowsColumnReordering = false
        tableView.usesAlternatingRowBackgroundColors = true

        column2.width = 30
        column1.width = tableView.bounds.width - column2.width - 8
        // ^^ -8 or for some reason there is some horizontal “give”
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        return events.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let event = events[row]
        if tableColumn?.identifier.rawValue == "NAME_COLUMN" {
            let tf = NSTextField()
            tf.isBordered = false
            tf.stringValue = "  " + event.description
            tf.backgroundColor = nil
            return tf
        } else {
            let bn = NSButton()
            bn.title = ""
            bn.setButtonType(.switch)
            bn.state = enrollment.events.contains(event) ? .on : .off
            bn.target = self
            bn.action = #selector(onChecked)
            bn.tag = row
            return bn
        }
    }

    @objc func onChecked(sender: NSButton) {
        let event = self.events[sender.tag]
        var events = enrollment.events

        if events.contains(event) {
            events.remove(event)
        } else {
            events.insert(event)
        }

        firstly {
            try mgr.alter(enrollment: enrollment, events: events)
        }.done {
            self.enrollment = $0
        }.catch {
            alert(error: $0)
        }
    }
}
