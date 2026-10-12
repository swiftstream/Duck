#if os(macOS)
import AppKit
import UIKitPlus

@MainActor
final class MacTaskTableController: ViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let owner: DemoDatabase?
    private let reactive: Bool
    private let table = NSTableView()
    private let scroll = NSScrollView()
    @UState private var observedRows: [DemoTask] = []
    private var manualRows: [DemoTask] = []
    private var observation: DemoObservationStore?
    private var listener: StateListener?
    private let columns = ["title", "status", "priority"]

    init(owner: DemoDatabase?, reactive: Bool) {
        self.owner = owner
        self.reactive = reactive
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func buildUI() {
        super.buildUI()
        for name in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(name))
            column.title = name.capitalized
            column.width = name == "title" ? 380 : 130
            table.addTableColumn(column)
        }
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.autoresizingMask = [.width]
        table.frame = NSRect(x: 0, y: 0, width: 860, height: 520)
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: reactive ? "Reactive NSTableView + @UState + QueryObservation" : "Manual NSTableView · no QueryObservation · array + reloadData()")
        title.font = .boldSystemFont(ofSize: 16)
        let actionMessage = NSTextField(labelWithString: "Ready")
        actionMessage.identifier = NSUserInterfaceItemIdentifier("action-message")
        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.spacing = 8
        for action in ["Add 1", "Add many", "Update 1", "Update many", "Delete 1", "Delete many"] {
            let button = NSButton(title: action, target: self, action: #selector(runAction(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(action)
            actions.addArrangedSubview(button)
        }
        title.translatesAutoresizingMaskIntoConstraints = false
        actions.translatesAutoresizingMaskIntoConstraints = false
        actionMessage.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(title)
        view.addSubview(actions)
        view.addSubview(actionMessage)
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            actions.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            actions.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14),
            actionMessage.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            actionMessage.topAnchor.constraint(equalTo: actions.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            scroll.topAnchor.constraint(equalTo: actionMessage.bottomAnchor, constant: 10),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
        ])
        if reactive, let owner {
            let store = DemoObservationStore(database: owner.database)
            store.onChange = { [weak self, weak store] in
                guard let self, let store else { return }
                self.observedRows = store.state
            }
            listener = $observedRows.listen { [weak self] _ in self?.table.reloadData() }
            observation = store
            store.start()
        } else {
            refreshManual()
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        observation?.stop()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { reactive ? observedRows.count : manualRows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let task = reactive ? observedRows[row] : manualRows[row]
        let identifier = tableColumn?.identifier.rawValue ?? "title"
        let text: String
        switch identifier {
        case "status": text = task.status
        case "priority": text = String(task.priority)
        default: text = task.title
        }
        let cellId = NSUserInterfaceItemIdentifier("cell-\(identifier)")
        let cell = tableView.makeView(withIdentifier: cellId, owner: self) as? NSTableCellView ?? {
            let view = NSTableCellView()
            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            view.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
            view.identifier = cellId
            return view
        }()
        cell.textField?.stringValue = text
        return cell
    }

    @objc private func runAction(_ sender: NSButton) {
        Task {
            guard let owner, let action = sender.identifier?.rawValue else { return }
            do {
                let affected = try await owner.repository.perform(action)
                let latest: [DemoTask]
                if reactive { latest = try await owner.repository.fetchTasks() }
                else { manualRows = try await owner.repository.fetchTasks(); table.reloadData(); latest = manualRows }
                let expected = action == "Add many" ? 5 : ((action == "Update many" || action == "Delete many") ? 2 : 1)
                view.window?.contentView?.subviews.compactMap { $0 as? NSTextField }.first(where: { $0.identifier?.rawValue == "action-message" })?.stringValue = "\(action): expected \(expected), affected \(affected), current rows \(latest.count) at \(Date().formatted(date: .omitted, time: .standard))"
            } catch {
                view.window?.contentView?.subviews.compactMap { $0 as? NSTextField }.first(where: { $0.identifier?.rawValue == "action-message" })?.stringValue = "\(action) failed: \(error)"
            }
        }
    }

    private func refreshManual() {
        Task {
            guard let owner else { return }
            do { manualRows = try await owner.repository.fetchTasks(); table.reloadData() }
            catch { table.reloadData() }
        }
    }
}
#endif
