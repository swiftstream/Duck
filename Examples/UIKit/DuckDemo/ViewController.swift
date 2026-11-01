import Duck
import Foundation
import UIKit

final class ViewController: UIViewController {
    @IBOutlet private weak var nameField: UITextField!
    @IBOutlet private weak var addButton: UIButton!
    @IBOutlet private weak var tableView: UITableView!
    @IBOutlet private weak var activityIndicator: UIActivityIndicatorView!

    private var todos: [Todo] = []
    private var observationTask: Task<Void, Never>?
    private var isReady = false

    override func viewDidLoad() {
        super.viewDidLoad()
        setReady(false)
    }

    deinit {
        observationTask?.cancel()
    }

    func start() {
        setReady(true)

        observationTask = Task { [weak self] in
            await self?.observeTodos()
        }
    }

    func show(error: Error) {
        loadViewIfNeeded()
        setReady(false)

        guard presentedViewController == nil else { return }

        let alert = UIAlertController(
            title: "Database Error",
            message: String(describing: error),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        present(alert, animated: true)
    }

    @IBAction
    private func nameDidChange(_ sender: UITextField) {
        updateAddButton()
    }

    @IBAction
    private func addTodo(_ sender: Any) {
        let name = nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return }

        nameField.text = ""
        updateAddButton()

        Task { [weak self] in
            guard let self else { return }

            do {
                let todo = Todo()
                todo.id = UUID()
                todo.name = name
                todo.createdAt = Date()

                try await todo.insertNonReturning(on: .demo)
            } catch {
                show(error: error)
            }
        }
    }

    private func observeTodos() async {
        do {
            for try await result in try Todo
                .select
                .where(Todo.$deletedAt == nil)
                .orderBy(.asc(Todo.$createdAt))
                .observe(on: .demo)
            {
                todos = try result.all(decoding: Todo.self)
                tableView.reloadData()
            }
        } catch is CancellationError {
            return
        } catch {
            show(error: error)
        }
    }

    private func toggle(_ todo: Todo) {
        Task { [weak self] in
            guard let self else { return }

            do {
                let update = Todo()
                update.id = todo.id
                update.doneAt = todo.doneAt == nil ? Date() : nil

                try await update.updateNonReturning(on: \.$id, on: .demo)
            } catch {
                show(error: error)
            }
        }
    }

    private func softDelete(_ todo: Todo) async throws {
        let update = Todo()
        update.id = todo.id
        update.deletedAt = Date()

        try await update.updateNonReturning(on: \.$id, on: .demo)
    }

    private func setReady(_ ready: Bool) {
        isReady = ready
        nameField.isEnabled = ready
        tableView.isUserInteractionEnabled = ready

        if ready {
            activityIndicator.stopAnimating()
        } else {
            activityIndicator.startAnimating()
        }

        updateAddButton()
    }

    private func updateAddButton() {
        let name = nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        addButton.isEnabled = isReady && !name.isEmpty
    }
}

extension ViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        todos.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TodoCell", for: indexPath)
        let todo = todos[indexPath.row]

        let attributes: [NSAttributedString.Key: Any]
        if todo.doneAt == nil {
            attributes = [:]
        } else {
            attributes = [
                .foregroundColor: UIColor.secondaryLabel,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue
            ]
        }

        var content = cell.defaultContentConfiguration()
        content.attributedText = NSAttributedString(
            string: todo.name,
            attributes: attributes
        )
        content.image = UIImage(
            systemName: todo.doneAt == nil ? "circle" : "checkmark.circle.fill"
        )
        content.imageProperties.tintColor = .systemBlue
        cell.contentConfiguration = content

        return cell
    }
}

extension ViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        toggle(todos[indexPath.row])
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let todo = todos[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            guard let self else {
                completion(false)
                return
            }

            Task {
                do {
                    try await softDelete(todo)
                    completion(true)
                } catch {
                    show(error: error)
                    completion(false)
                }
            }
        }

        return UISwipeActionsConfiguration(actions: [delete])
    }
}
