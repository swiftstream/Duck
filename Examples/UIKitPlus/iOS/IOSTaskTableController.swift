#if !os(macOS)
import UIKit
import UIKitPlus

@MainActor
final class IOSTaskTableController: ViewController, UITableViewDataSource, UITableViewDelegate {
    private let owner: DemoDatabase?
    private let reactive: Bool
    private let table = UTableView(.plain)
    @UState private var observedRows: [DemoTask] = []
    @UState private var actionMessage = "Ready"
    private var manualRows: [DemoTask] = []
    private var observation: DemoObservationStore?
    private var listener: StateListener?

    init(owner: DemoDatabase?, reactive: Bool) {
        self.owner = owner
        self.reactive = reactive
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func buildUI() {
        super.buildUI()
        table.dataSource = self
        table.delegate = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "task")
        body {
            UVStack {
                UText(reactive ? "Reactive UTableView + @UState + QueryObservation" : "Manual UTableView · no QueryObservation")
                UHStack {
                    UButton("Add 1").onTapGesture { [weak self] in self?.perform("Add 1") }
                    UButton("Add many").onTapGesture { [weak self] in self?.perform("Add many") }
                    UButton("Update 1").onTapGesture { [weak self] in self?.perform("Update 1") }
                }
                UHStack {
                    UButton("Update many").onTapGesture { [weak self] in self?.perform("Update many") }
                    UButton("Delete 1").onTapGesture { [weak self] in self?.perform("Delete 1") }
                    UButton("Delete many").onTapGesture { [weak self] in self?.perform("Delete many") }
                }
                UText($actionMessage).multiline()
                table
            }
            .alignment(.fill)
            .spacing(8)
            .edgesToSuperview(h: 12, v: 12)
        }
        if reactive, let owner {
            let store = DemoObservationStore(database: owner.database)
            store.onChange = { [weak self, weak store] in
                guard let self, let store else { return }
                self.observedRows = store.state
            }
            listener = $observedRows.listen { [weak self] _ in self?.table.reloadData() }
            observation = store
            store.start()
        } else { refreshManual() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        observation?.stop()
    }

    func numberOfSections(in tableView: UITableView) -> Int { 1 }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { reactive ? observedRows.count : manualRows.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "task", for: indexPath)
        let task = reactive ? observedRows[indexPath.row] : manualRows[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = task.title
        content.secondaryText = "\(task.status) · priority \(task.priority)"
        cell.contentConfiguration = content
        return cell
    }

    private func perform(_ action: String) {
        Task {
            guard let owner else { return }
            do {
                let affected = try await owner.repository.perform(action)
                let latest: [DemoTask]
                if reactive { latest = try await owner.repository.fetchTasks() }
                else {
                    manualRows = try await owner.repository.fetchTasks()
                    table.reloadData()
                    latest = manualRows
                }
                let expected = action == "Add many" ? 5 : ((action == "Update many" || action == "Delete many") ? 2 : 1)
                actionMessage = "\(action): expected \(expected), affected \(affected), current rows \(latest.count) at \(Date().formatted(date: .omitted, time: .standard))"
            } catch { actionMessage = "\(action) failed: \(error)" }
        }
    }

    private func refreshManual() {
        Task {
            guard let owner else { return }
            do { manualRows = try await owner.repository.fetchTasks(); table.reloadData() }
            catch { actionMessage = "Manual query failed: \(error)" }
        }
    }
}
#endif
