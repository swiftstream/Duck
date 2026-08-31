# Future Publications

Durable backlog of concrete README/article/publication topics that the maintainer explicitly wants preserved for future public writing.

These entries are **not implementation authorization** and are **not current API claims**. Any code using an unimplemented capability is illustrative until that capability has completed research, planning, implementation, validation, audit, and public-documentation acceptance.

## 001 — Public Reusable Prepared Statements API: what it is and why it matters

Status: **future publication / future README material**

Trigger for publication: after a Public Reusable Prepared Statements API is actually implemented, validated, independently audited, and accepted for public documentation.

Preserve the following explanation and examples as source material.

`Public Reusable Prepared Statements API` — это когда ты один раз подготавливаешь SQL-запрос, а потом много раз выполняешь его с разными параметрами, не заставляя DuckDB каждый раз заново разбирать SQL и создавать новый prepared statement.

Сейчас у нас API примерно такого уровня:

```swift
let users = Path.Table("users")

try await SwifQL
    .insertInto(users, fields: "email", "name")
    .values
    .values("mike@example.com", "Mike")
    .execute(on: connection)
```

Если нужно вставить 10 000 пользователей, ты вызываешь `.execute(on:)` 10 000 раз. Внутри каждый вызов проходит путь примерно:

```text
SwifQL
→ render SQL
→ duckdb_prepare(...)
→ bind parameters
→ execute
→ destroy prepared statement
```

Reusable prepared statement позволил бы сделать подготовку **один раз**.

Например, будущий API мог бы выглядеть примерно так:

```swift
let users = Path.Table("users")

let insertUser = try await connection.prepare(
    SwifQL
        .insertInto(users, fields: "email", "name")
        .values
        .values(Parameter(1), Parameter(2))
)

try await insertUser.execute(
    "mike@example.com",
    "Mike"
)

try await insertUser.execute(
    "olga@example.com",
    "Olga"
)

try await insertUser.execute(
    "alex@example.com",
    "Alex"
)
```

Здесь `INSERT INTO ...` компилируется DuckDB только один раз, а дальше меняются только значения.

### Более жизненный пример

Представь локальную аналитику:

```swift
let events = Path.Table("events")

let insertEvent = try await connection.prepare(
    SwifQL
        .insertInto(
            events,
            fields: "timestamp", "name", "payload"
        )
        .values
        .values(
            Parameter(1),
            Parameter(2),
            Parameter(3)
        )
)
```

После этого:

```swift
for event in incomingEvents {
    try await insertEvent.execute(
        event.timestamp,
        event.name,
        event.payload
    )
}
```

Вместо:

```swift
for event in incomingEvents {
    try await SwifQL
        .insertInto(
            events,
            fields: "timestamp", "name", "payload"
        )
        .values
        .values(
            event.timestamp,
            event.name,
            event.payload
        )
        .execute(on: connection)
}
```

Главное различие не столько в количестве строк Swift-кода, сколько в native lifecycle.

Prepared statements полезны не только для `INSERT`.

Например, один часто повторяемый `SELECT`:

```swift
let users = Path.Table("users")

let findUser = try await connection.prepare(
    SwifQL
        .select(users.column("id"), users.column("name"))
        .from(users)
        .where(users.column("email") == Parameter(1))
)
```

И дальше:

```swift
let mike = try await findUser.query("mike@example.com")
let olga = try await findUser.query("olga@example.com")
let alex = try await findUser.query("alex@example.com")
```

То есть `findUser` становится фактически готовой reusable query.

Есть ещё более интересный вопрос — как это должно работать с нашими `Transaction`.

Например, пользователь мог бы захотеть:

```swift
let insertUser = try await connection.prepare(
    SwifQL
        .insertInto(users, fields: "email", "name")
        .values
        .values(Parameter(1), Parameter(2))
)

try await connection.transaction { transaction in
    try await insertUser.execute(
        "mike@example.com",
        "Mike",
        on: transaction
    )

    try await insertUser.execute(
        "olga@example.com",
        "Olga",
        on: transaction
    )
}
```

И вот здесь начинается архитектурно важная часть.

Нам нужно решить: prepared statement физически привязан к `Connection`. Следовательно, он не должен внезапно выполняться на другой Connection:

```swift
let statement = try await connectionA.prepare(...)

// Скорее всего, такое должно быть запрещено:
try await statement.execute(..., on: connectionB)
```

Иначе ломается ownership native `duckdb_prepared_statement`.

### Ещё один возможный вариант API

Можно вообще не передавать connection повторно:

```swift
let statement = try await connection.prepare(...)

try await statement.execute(
    "mike@example.com",
    "Mike"
)
```

Потому что statement уже знает своего owner:

```text
PreparedStatement
       │
       ▼
 Connection
       │
       ▼
duckdb_connection
```

Но тогда надо определить, что произойдёт, если сам `Connection` станет unusable.

Например после нашего ambiguous COMMIT:

```swift
let statement = try await connection.prepare(...)

do {
    try await connection.transaction { transaction in
        // какой-то terminal COMMIT failure
    }
} catch {
    // connection теперь fail-closed
}

try await statement.execute(...)
```

Очевидно, reusable statement тоже должен получить что-то вроде:

```swift
DatabaseError.connectionUnusable
```

а не пытаться работать с native handle.

Ещё один вопрос — concurrent use.

Допустим:

```swift
let statement = try await connection.prepare(...)

async let a = statement.execute(1)
async let b = statement.execute(2)
async let c = statement.execute(3)

try await (a, b, c)
```

Что мы хотим?

Вариант A — это разрешено, а `Connection` сериализует вызовы:

```text
A
↓
B
↓
C
```

Вариант B — один prepared statement нельзя одновременно использовать из нескольких задач:

```swift
DatabaseError.preparedStatementAlreadyExecuting
```

Вариант C — каждый execution получает собственную binding/execution state поверх одного reusable native statement.

Но это уже зависит от реальных гарантий DuckDB C API, поэтому и нужна отдельная research phase.

Ещё одна важная вещь — lifetime.

Например:

```swift
var statement: PreparedStatement?

do {
    let connection = try database.connect()

    statement = try await connection.prepare(...)
}

// connection больше нигде не используется

try await statement!.execute(...)
```

Надо решить, кто кого удерживает.

### Модель 1

`PreparedStatement` strongly retains `Connection`.

Тогда:

```text
PreparedStatement
   └── Connection
        └── NativeConnection
```

Statement может продолжать работать.

### Модель 2

Statement не владеет Connection.

Тогда после окончания lifetime Connection:

```swift
try await statement.execute(...)
```

получит:

```swift
.preparedStatementInvalidated
```

Для Swift API это очень существенная разница.

Prepared statement также позволяет сделать удобный API для batch workloads:

```swift
let insert = try await connection.prepare(
    SwifQL
        .insertInto(metrics, fields: "name", "value")
        .values
        .values(Parameter(1), Parameter(2))
)

for metric in metrics {
    try await insert.execute(metric.name, metric.value)
}
```

Или:

```swift
try await connection.transaction { transaction in
    for metric in metrics {
        try await insert.execute(
            metric.name,
            metric.value,
            on: transaction
        )
    }
}
```

Вот **это** наиболее очевидный user-facing use case.

При этом reusable prepared statements — это **не ORM**.

Не такое:

```swift
try await User
    .where(...)
    .save()
```

И не такое:

```swift
let user: User = try await db.find(...)
```

Это гораздо более низкоуровневый capability:

```text
SwifQL query
    ↓
PreparedStatement
    ↓
bind
    ↓
execute/query
```

То есть архитектурно это следующий слой непосредственно над уже существующим query engine.

### Если упростить до одного примера

**То, что есть сейчас:**

```swift
for id in ids {
    let result = try await SwifQL
        .select(users.column("name"))
        .from(users)
        .where(users.column("id") == id)
        .query(on: connection)
}
```

**То, что потенциально даст reusable prepared statement:**

```swift
let findUser = try await connection.prepare(
    SwifQL
        .select(users.column("name"))
        .from(users)
        .where(users.column("id") == Parameter(1))
)

for id in ids {
    let result = try await findUser.query(id)
}
```

Вот в этом вся идея.

И важный момент: **конкретный синтаксис выше — только пример возможного дизайна. У нас этого API ещё нет и он ещё не спроектирован.** Именно поэтому будущая research phase должна решить, хотим ли мы вообще такой API и каким он должен быть.

Для SwiftDuckDB prepared statements в первую очередь стоит рассматривать ради трёх сценариев:

1. массовые `INSERT` / `UPDATE`;
2. часто повторяемые `SELECT` с разными параметрами;
3. использование одного заранее подготовленного запроса внутри `Transaction`.
