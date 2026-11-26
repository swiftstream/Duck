# Duck 1.1: один Connection Pool и реактивные SQL-запросы в Swift

Статус: грубый авторский черновик, НЕ опубликован. Подготовлен после независимого R4 CLEAN 24.11.2026. Перед публикацией проверить ссылку на фактический релиз, повторно отредактировать текст в авторском стиле и проверить все новые/перекомбинированные примеры. Это не разрешение на публикацию.

Первая статья: [Duck: DuckDB для Swift. Мощный SQL прямо в iOS и macOS приложениях](https://habr.com/ru/articles/1107762/). Стилистический ориентир: .agent/PUBLIC_WRITING_STYLE.md.

## Черновик статьи

Привет, Хабр!

После первой публикации о Duck я получил несколько очень хороших вопросов про реактивные запросы и Connection Pooling. В частности, как observation ведет себя на границе транзакции, не теряется ли COMMIT, если наблюдение уже успело прочитать старые данные, зачем обычному запросу и пулу разные способы получения connection и насколько точно вообще можно понять, что наблюдаемый SQL нужно выполнить еще раз.

Мне хотелось не просто ответить на эти вопросы в комментариях, а разобраться с ними в самой библиотеке. В результате получилась новая архитектура работы с DuckDB, которая при этом почти не меняет повседневный Swift API. Сразу оговорюсь: наиболее сложную часть оптимизации invalidation я решил оставить на 1.2. Ниже расскажу почему.

## Один Database, один Connection Pool

В Duck 1.0 обычные операции могли создавать новые native Connections вне отдельного Connection Pool. Наблюдение также держало свой Connection на протяжении жизни iterator. В приложении с большим количеством запросов и реактивных подписок это не очень удачная модель владения ресурсами.

В Duck 1.1 у каждой логической Database теперь один канонический пул в пределах процесса. Обычный SQL, CRUD, миграции, Appender, транзакции и refresh наблюдений автоматически берут Connection из этого пула. Пользователю не нужно передавать pool в каждую операцию.

Модель осталась такой же. Для примеров используется Todo из README:

```swift
import Duck
import Foundation

struct Todo: Table {
    @Column("id") var id: UUID
    @Column("name") var name: String
    @Column("created_at") var createdAt: Date
    @Column("done_at") var doneAt: Date?
    @Column("deleted_at") var deletedAt: Date?

    init() {}

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        doneAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.doneAt = doneAt
        self.deletedAt = deletedAt
    }
}
```

В приложении я бы по-прежнему использовал отдельное объявление базы и миграции, а не передавал ее файловый путь в каждый запрос.

```swift
private var appDatabaseDirectory: URL {
    FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
}

extension Database {
    static var app: Self {
        Self(
            path: appDatabaseDirectory
                .appendingPathComponent("Todos.duckdb")
                .path
        )
    }
}

extension Todo {
    struct Create: Migration {
        let name = "Todo.Create"

        var up: MigrationPlan {
            CreateTable("todo") {
                NewColumn("id", .uuid).primaryKey()
                NewColumn("name", .text).notNull()
                NewColumn("created_at", .timestamptz).notNull()
                NewColumn("done_at", .timestamptz)
                NewColumn("deleted_at", .timestamptz)
            }
        }

        var down: MigrationPlan {
            DropTableBuilder<Todo>()
        }
    }
}

func prepareDatabase() async throws {
    try FileManager.default.createDirectory(
        at: appDatabaseDirectory,
        withIntermediateDirectories: true
    )

    // Optional. Configure before the first database operation,
    // including migrations and observation.
    try await Database.app.configure(
        minimumConnections: 1,
        maximumConnections: 4
    )

    _ = try await Database.app
        .migrator([Todo.Create()])
        .migrate()
}
```

Выполняем prepareDatabase() при запуске, до обращения к базе. Если настройки не нужны, вызов configure можно убрать: по умолчанию minimumConnections = 1 и maximumConnections = 1. Конструирование Database само по себе не открывает DuckDB. Минимум открывается при инициализации пула, остальные connections создаются лениво по мере необходимости. Допускается минимум 0. Значение 1/1 выбрано как консервативная отправная точка, а не результат измерения оптимальной производительности.

Например, обычные операции выглядят так же, как раньше:

```swift
let todo = Todo(name: "Learn Duck")
try await todo.insertNonReturning(on: .app)

let inserted = try await Todo(name: "Another task").insert(on: .app)
let todos = try await Todo.all(on: .app)
```

Fluent-запрос:

```swift
let todos = try await Todo
    .query
    .where(Todo.$deletedAt == nil)
    .orderBy(.asc(Todo.$createdAt))
    .all(on: .app)
```

И тот же SELECT в result builder:

```swift
let todos = try await SQL {
    Select {
        \Todo.$id
        \Todo.$name
        \Todo.$createdAt
        \Todo.$doneAt
        \Todo.$deletedAt
    }
    From(Todo.table)
    Where(\Todo.$deletedAt == nil)
    OrderBy(.asc(\Todo.$createdAt))
}.all(decoding: Todo.self, on: .app)
```

Пользователь вообще не обязан получать Connection вручную. Если несколько операций должны работать на одном connection, можно взять его на время closure:

```swift
let todos = try await Database.app.connection { connection in
    try await Todo.all(on: connection)
}
```

А если нужна атомарность, можно работать сразу с транзакцией:

```swift
try await Database.app.transaction { transaction in
    try await Todo(name: "Первый").insertNonReturning(on: transaction)
    try await Todo(name: "Второй").insertNonReturning(on: transaction)
}
```

Эти scoped формы были доступны и в 1.0. Теперь они используют общий пул, вместо того чтобы открывать независимые connections. После окончания closure здоровый connection возвращается в пул. При работе внутри lease нужно использовать полученный Connection или DuckTransaction, а не пытаться получить второй lease той же базы.

## Observation осталась AsyncSequence

Мне очень нравится, что для реактивной работы не нужен отдельный UI framework или database manager. Обычный SwiftUI task может читать результаты точно так же, как раньше:

```swift
@State private var todos: [Todo] = []

// In the View's body, after database startup:
.task {
    do {
        for try await result in try Todo
            .select
            .where(Todo.$deletedAt == nil)
            .orderBy(.asc(Todo.$createdAt))
            .observe(on: .app)
        {
            todos = try result.all(decoding: Todo.self)
        }
    } catch is CancellationError {
        // The view disappeared or the task was replaced.
    } catch {
        print("Duck error:", error)
    }
}
```

Модель объявлена в отдельном файле от SwiftUI, чтобы не конфликтовали имена Table. Для UIKit подойдет тот же AsyncSequence в управляемом Task с обновлением UI на MainActor и отменой по lifecycle.

Можно и наблюдать явно построенный SQL:

```swift
let observation = try SQL
    .select(Int32(42) => "answer")
    .observe(on: .app)

for try await result in observation {
    print(result.rows)
}
```

Константа 42 здесь только иллюстрирует форму API, не полезную подписку на изменения таблицы.

Раньше каждый iterator открывал и удерживал Connection до завершения. Теперь он держит регистрацию в observation coordinator, worker и bounded latest-state channel. Connection заимствуется только на время READ ONLY refresh, а после материализации результата возвращается в пул, еще до публикации результата. В покое наблюдение не занимает lease вообще.

Для 20 наблюдений раньше могло быть 20 выделенных connections только под них. Теперь при max=4 все операции этой Database, включая наблюдения, разделяют максимум четыре native connections. Это пример архитектурного ограничения, не измерение памяти или скорости. Сам пул может оставлять здоровые idle connections открытыми для переиспользования. Каждый iterator по-прежнему имеет собственное состояние, а размер результата зависит от запроса.

## Что происходит при COMMIT?

Первый комментарий спрашивал, отправляется ли уведомление при INSERT/UPDATE или после COMMIT, и что будет, если параллельное наблюдение успело прочитать старый результат.

В явной транзакции Duck накапливает mutation impact и не публикует отдельную invalidation на каждый INSERT/UPDATE/DELETE. При успешном COMMIT накопленный impact публикуется после финализации. Read-only observation получает согласованный committed snapshot, а не чужие незакоммиченные строки. Сигнал invalidation не означает синхронного завершения refresh к моменту возврата COMMIT.

На двух connections возможен такой порядок:

```text
Connection A (writer)             Connection B (observation)
BEGIN
INSERT / UPDATE
INSERT / UPDATE                   READ ONLY refresh: old state
COMMIT -------------------------> invalidation pending
return lease                      finish old refresh / return lease
                                  refresh again
                                  emit changed committed result
```

Здесь важно не потерять invalidation при переходе между анализом зависимостей, ожиданием lease, чтением и возвратом connection. На время refresh регистрация расширяется до database-wide coverage до ожидания capacity и остается такой вплоть до возврата lease. Затем можно сузить зависимости. Pending invalidations коалесцируются, а один ожидающий сигнал достаточен, чтобы повторно прочитать актуальное состояние.

Гарантия latest-state: при живой подписке, доступной capacity, успешных refresh и прекратившихся изменениях результат сходится к актуальному committed состоянию. Это не change log и не обещание отдельного emission на каждый COMMIT. При продолжительных записях промежуточные committed состояния могут пропускаться. Не надо обещать ограниченную latency при непрерывной нагрузке или отсутствии доступного lease.

ROLLBACK тоже иногда вызывает invalidation. Например, sequence может измениться даже при откате вставленной строки, поэтому нельзя безусловно игнорировать rollback. При отмене managed Task до успешного COMMIT действует rollback; промежуточные строки не попадают в наблюдение. Отмена после фактического COMMIT не отменяет уже committed изменения.

Для атомарной пакетной загрузки стоит использовать Appender внутри transaction. Вне transaction ordinary Appender может auto-flush часть данных еще до выхода из closure, и этот durable prefix может сохраниться даже при последующей ошибке. Это отдельный контракт, не нарушение observation.

## Как мы это проверяли

Тест O06 использует max=2 и детерминированную остановку observation после получения старого результата, до возврата lease. Второй Connection выполняет настоящий COMMIT. После возобновления подписчик получает результат с измененным значением. Не тестируем удачный случай с искусственной задержкой, а явно выстраиваем нужный порядок действий.

Другой тест ставит четыре независимых iterator в состояние со stale snapshot после возврата lease. При max=2 выполняет 191 отдельную транзакцию: 64 INSERT, 64 UPDATE и 63 DELETE. Каждый commit может создать новый demand, но отдельный coordinator witness подтверждает, что paused registration сохраняет один ожидающий сигнал. После возобновления все четыре iterator получают результат, совпадающий с независимым SELECT: единственная строка id=64, value=640. Все leases возвращены, регистрации очищены.

Еще один тест держит реальную незакоммиченную строку, запускает параллельный READ ONLY refresh, отменяет writer Task, проверяет rollback, отсутствие строки в refresh и в независимом SELECT. B10 проверяет снимки refresh; не заявлять, что он отдельно вычитывает весь пользовательский stream после отмены.

Тесты Appender покрывают 205000 строк внутри flat transaction, отсутствие видимости и публикации до финализации, COMMIT и ROLLBACK. Обычный Appender отдельно проверен на границе auto-flush и ошибках.

## Один неприятный баг с lifetime

На финальном независимом аудите выяснилось, что логический лимит pool еще не обязательно означал физический лимит. Устаревший public Connection handle мог продолжать удерживать Runtime и открытый native connection даже после retirement. Если пул освободил слот и создал replacement, при max=1 получалось два одновременно открытых native connections.

В старом варианте такая ошибка могла пройти мимо теста, который проверяет только число слотов или успешность replacement. Поэтому добавили witness на настоящие вызовы duckdb_connect/duckdb_disconnect и воспроизвели ошибку на старом поведении. Peak действительно был 2.

В исправленной реализации слот остается .retiring до завершения disconnect. Старая Swift-ссылка может оставаться живой, но уже не удерживает открытый native handle. Здоровый release переиспользует connection, retirement освобождает его. Prepared Statement и Appender должны быть уничтожены до disconnect. При невозможности доказать безопасное завершение пул сообщает об ошибке и закрывает допуск новых checkout, вместо того чтобы освободить accounting и притвориться, что shutdown удался.

Проверены max-one replacement с удерживаемыми старыми handles, healthy reuse, shutdown в покое и с активным lease, queued activation, cleanup failure, точная generation authority, rollback и порядок native child destruction. 14 новых регрессий на каждом toolchain. Для defensive retirement refusal использована безопасная test seam до C disconnect, а не искусственная поломка C API. Отдельный post-activation failure fence проверен по исходнику, не заявлять отдельный runtime test этой ветки.

## Насколько точно Observation выбирает запросы для refresh?

Третий комментарий как раз про стоимость повторных запросов. В 1.0 уже были анализ read dependencies, coalescing и suppression равных результатов. Но обычные mutation paths консервативно инвалидировали всю базу.

В 1.1 эта консервативная политика остается. Если запросы наблюдают messages, profiles и settings, INSERT в messages может вызвать повторные SELECT всех трех. Если QueryResult для profiles не изменился, новый результат не уйдет подписчику, и UI не будет зря декодировать его в модели. Но сам SELECT, материализация и сравнение все равно выполнятся. Отказ от dedicated connections и bounded pending demand не устраняют этот расход.

Почему я не хочу просто взять имя целевой таблицы из INSERT и инвалидировать ее? В проверенном DuckDB движке Appender может вызвать trigger, который изменит другую таблицу. В тесте OA25 запись в одну таблицу через Appender приводит к вставке во вторую. Если инвалидировать только первую, observation второй пропустит изменение.

Упрощенная иллюстрация (SQL, не рекомендуемый способ построения запросов Duck):

```sql
CREATE TRIGGER copy_message
AFTER INSERT ON messages
FOR EACH ROW
INSERT INTO notifications VALUES (NEW.id);
```

Нужен способ установить полный execution-effect set, а не просто структурный primary target. До этого момента и обычные writes, и Appender используют database-wide fallback. Для будущих column-, predicate- и row-aware оптимизаций также нужно доказать безопасность для joins, aggregates, views, сложных выражений и fallback.

В первой статье я наметил эту работу для 1.1. По итогам разработки решил выпустить архитектурный фундамент сейчас, а точность invalidation и полноценные million-row/high-write benchmarks перенести на 1.2. Не обещаю ускорения в процентах или что любой большой workload уже эффективен. Сначала корректность, затем измерение и более точная маршрутизация.

## Переход с 1.0

Повседневные CRUD, SQL DSL, migrations, scoped transaction и observation не требуют нового обязательного аргумента. Старое имя DatabaseIdentifier сохранено как deprecated typealias:

```swift
// Existing app code remains source-compatible.
extension DatabaseIdentifier {
    static let app = DatabaseIdentifier(memory: "app")
}
```

В новом коде лучше так (альтернатива file-backed .app выше, не объявлять вместе):

```swift
extension Database {
    static let app = Database(memory: "app")
}
```

Есть важное изменение поведения. В 1.0 явный connect открывал отдельный connection. Теперь он берет manual lease из общего пула. Такой старый код может компилироваться, но при max=1 зависнуть в ожидании второго lease:

```swift
let connection = try await DatabaseIdentifier.app.connect()
let result = try await connection.query(SQL.select(Int32(42) => "answer"))
let todos = try await Todo.all(on: .app) // Do not do this in 1.1.
```

Лучше вернуть lease перед следующим запросом:

```swift
let result = try await Database.app.connection { connection in
    try await connection.query(SQL.select(Int32(42) => "answer"))
}

let todos = try await Todo.all(on: .app)
```

Или использовать вручную полученный handle с обязательным awaited release на всех путях выхода:

```swift
let connection = try await Database.app.connect()
// No throwing work in this minimal lease example.
try await connection.release()
```

Не переносить release в fire-and-forget Task из defer. После release handle и его Statement/Appender больше не действительны. Если работа может бросить ошибку, предпочитать scoped API; manual release должен быть структурно гарантирован, а ошибки cleanup не следует скрывать.

Второй нюанс: pool(maximumConnections:) теперь compatibility API, а не создание независимого пула. Настраивать capacity необходимо до первой операции. Повторный вызов с конфликтующей конфигурацией бросает ошибку. Правильный порядок:

```swift
let database = Database.memory()
try await database.configure(minimumConnections: 1, maximumConnections: 4)
let pool = try await database.pool()
let result = try await SQL.select(Int32(1)).query(on: database)
try await pool.shutdown()
```

shutdown теперь terminal для канонического runtime в данном процессе. Не вызывайте его внутри своего lease. Не ожидайте, что после него обычный запрос создаст новый пул.

В строгом смысле source compatibility не равна behavioral compatibility. Я сознательно сохраняю номер 1.1.0 при этих изменениях, поскольку у библиотеки пока практически нет пользователей. Это не повод прятать новые требования к lifetime. Они должны быть явно описаны в release notes.

Минимальные требования не изменились: Swift tools 6.3, iOS 15+, macOS 12+, SQL от 3.1.0 в рамках 3.x. Duck по-прежнему re-export SQL, обычного import Duck достаточно. Не заявлять новую платформенную поддержку на основании этой macOS/iOS build validation.

## И немного про WidgetKit

Канонический pool и observation coordinator являются process-local. Даже App Group и один файловый путь не делают приложение и WidgetKit extension одним runtime. Для виджета лучше публиковать небольшой committed Codable projection или отдельный finalized snapshot, а не пытаться одновременно читать и писать основной live DuckDB file из разных процессов. Cross-process observation здесь нет.

## Результат и что дальше

Перед принятием 1.1 мы прогнали full suite на Swift 6.3.3 (859 тестов, 31 suite) и Swift 6.4 (870 тестов, 31 suite, включая 41 C bridge test). Normal-import compatibility consumer собран и выполнен обоими toolchains. Documentation consumer собран и запущен. Оба реальных проекта SwiftUI и UIKit собраны и слинкованы с локальным кандидатом для arm64 и x86_64 iOS Simulator. Simulator runtime не запускался. Финальный независимый R4 re-audit CLEAN, все семь gates PASS.

Все эти цифры относятся к проверке корректности, а не к сравнению latency или throughput. Отдельного replay абсолютно всех фрагментов первой статьи не проводилось.

Мне нравится, что удалось изменить довольно серьезную часть внутренней архитектуры, сохранив тот API, ради которого вообще создавался Duck. При этом впереди еще работа над тем, чтобы на busy database observation выполняла меньше лишних запросов.

[GitHub Duck](https://github.com/SwiftStream/Duck), [Swift Stream SQL](https://github.com/SwiftStream/SQL), [Discord](https://discord.gg/q5wCPYv). После выхода релиза вставить ссылку на фактический 1.1.0 GitHub release, SwiftUI/UIKit examples и приглашение делиться реальными сценариями с большой частотой записей.

## Редакторские заметки и evidence (не публиковать как часть статьи)

### Исходные комментарии, предоставленные maintainer

> Как observation связана с границами транзакции: уведомление об изменениях отправляется после успешного COMMIT или уже при выполнении INSERT/UPDATE? Для пула это интересно проверить на двух соединениях: первое меняет несколько строк в одной транзакции, второе наблюдает результат запроса. Есть ли тест, что после COMMIT подписчик обязательно получает итоговое состояние, даже если до коммита уже успел перечитать прежний результат? И отдельно — что при ROLLBACK или отмене Task в подписку не попадают промежуточные изменения. Это помогло бы понять гарантии observe при пакетной загрузке.

> удивился что соединение с базой не нужно создавать явно, в то время как в случае с connection pool нужно сделать это явно. Я бы заложил одинаковое поведение для обоих случаев.

> Observing a query as an async stream is a nice shape for SwiftUI, much nicer than wiring up reloads by hand.
>
> Two questions. How does the observation decide when to re-run? Is it any write to the database, any write to a table the query touches, or something finer? With a busy table that's the difference between fine and re-decoding everything constantly.

### Дополнительные примеры для сравнения API

Исторический 1.0 explicit Connection transaction (не рекомендуемый новый код, без release в 1.1):

```swift
let connection = try await DatabaseIdentifier.app.connect()

try await connection.transaction { transaction in
    let first = Todo(name: "Первый")
    let second = Todo(name: "Второй")

    try await first.insertNonReturning(on: transaction)
    try await second.insertNonReturning(on: transaction)
}
```

Историческая последовательность ordinary query -> separate pool, которая теперь может закончиться configuration conflict:

```swift
let todos = try await Todo.all(on: .app)

let pool = try await DatabaseIdentifier.app
    .pool(maximumConnections: 4)
```

### Техническая проверка и редактура

- Исходные три комментария: транзакционные границы/две связи/COMMIT после stale refresh/ROLLBACK/Task cancellation; одинаковое обычное и pooled использование; database/table/finer rerun и стоимость busy table. Первые два закрыты по существу, третий только по bounded ownership и demand, не по precision. Не цитировать комментарии дословно без сверки оригинала.
- Диаграммы для статьи: 1.0 independent ordinary connections + separate pool + dedicated observation connection -> 1.1 shared canonical pool; sequence diagram COMMIT during stale refresh; messages/profiles/settings database-wide fanout, equal-result suppression; max=1 physical retirement before/after. Числовой пример 20 observations / max4 является моделью, не benchmark.
- O06: Tests/DuckTests/ObservationPoolRefreshTests.swift:268-320, реальный writer commit и iterator result.
- OT02, OT03, OT06, OT08, OP03: ObservationTransactionTests.swift, ConnectionPoolObservationTests.swift; transaction publication after finalization and rollback effects.
- OA15-17: ObservationAppenderTests.swift:881-1018; 205000 rows and independent reader. OA25: lines 585-665, trigger-transitive effects, database-wide invalidation. OA04-07 ordinary durable prefix.
- B10/B14/B15: Tests/DuckTests/ObservationDeterministicStressTests.swift, 284 lines SHA a2e76fc7dc740c46cecf3f71a971b9dcd7d8c26ccba24446ad1151c45e6fc7e0.
- F01: Tests/DuckTests/NativeConnectionRetirementTests.swift, 802 lines SHA c7f8caedc0a850b11c17f8b10217ba4d0f2d07d582a4e5bc7247ce1b1acfdce8; real native boundary witness, RED peak2/max1, GREEN. No performance inference.
- Final evidence: .artifacts/handoff/v1-1-r4-f01-native-retirement-correction02-secondary-2026-11-24/EXECUTION_REPORT.md SHA 27cc5697a017d9c4b2cf0b1b01eb281aa1bd8d777a22e1daae29f072f8b668dc.
- Final independent report: .artifacts/reviews/duck-v1-1-r4-f01-final-correction-reaudit-2026-11-24/FINAL_CORRECTION_REAUDIT_REPORT.md SHA a826b006b5e35f8f84a0cbb86367d864b0bbd551f7768f27457e304a90698625.
- Preserve existing public API examples, check all assembled snippets against exact released version before publication. No article replay has been run. The explicit configuration in prepareDatabase must happen before the first pool use; if called from SwiftUI repeatedly, prefer one startup task and separate prepare-once coordination rather than implying reconfiguration after pool initialization.
- Maintainer decisions 2026-11-24: ship the accepted architectural scope as 1.1.0; accept explicit connect/pool behavioral changes in minor release given the very small existing user base; defer safe mutation precision and large workload benchmarks to 1.2. These decisions do not authorize implementation of 1.2, push/tag/release, or article publication.
