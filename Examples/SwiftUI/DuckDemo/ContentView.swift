import Duck
import Foundation
import SwiftUI

struct ContentView: View {
    @State private var todos: [Todo] = []
    @State private var newTodoName = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        TextField("New TODO", text: $newTodoName)
                            .onSubmit(addTodo)

                        Button(action: addTodo) {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(newTodoName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section {
                    ForEach(todos, id: \.id) { todo in
                        Button {
                            toggle(todo.id, isDone: todo.doneAt != nil)
                        } label: {
                            HStack {
                                Image(systemName: todo.doneAt == nil ? "circle" : "checkmark.circle.fill")
                                Text(todo.name)
                                    .strikethrough(todo.doneAt != nil)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: softDelete)
                }
            }
            .navigationTitle("TODO")
        }
        .task {
            await observeTodos()
        }
        .alert(
            "Database Error",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
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
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func addTodo() {
        let name = newTodoName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        newTodoName = ""

        Task {
            do {
                let todo = Todo()
                todo.id = UUID()
                todo.name = name
                todo.createdAt = Date()

                try await todo.insertNonReturning(on: .demo)
            } catch {
                errorMessage = String(describing: error)
            }
        }
    }

    private func toggle(_ id: UUID, isDone: Bool) {
        Task {
            do {
                let todo = Todo()
                todo.id = id
                todo.doneAt = isDone ? nil : Date()

                try await todo.updateNonReturning(on: \.$id, on: .demo)
            } catch {
                errorMessage = String(describing: error)
            }
        }
    }

    private func softDelete(_ offsets: IndexSet) {
        let ids = offsets.map { todos[$0].id }

        Task {
            do {
                try await DatabaseIdentifier.demo.connection { connection in
                    for id in ids {
                        let todo = Todo()
                        todo.id = id
                        todo.deletedAt = Date()
                        try await todo.updateNonReturning(on: \.$id, on: connection)
                    }
                }
            } catch {
                errorMessage = String(describing: error)
            }
        }
    }
}
