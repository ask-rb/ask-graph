## [0.7.1] — 2026-07-31

### Added

- **`storage=` setter** — assignment form of the class-level `storage` method,
  convenient in initializers: `Ask::Graph.storage = RedisPool.new`.

### Tested

- 96 tests, 130 assertions, 0 failures

## [0.7.0] — 2026-07-31

### Added

- **`workflow_timeout`** — total runtime cap for the entire workflow. The
  whole run aborts with `Ask::Graph::WorkflowTimeout` if it exceeds the
  limit, regardless of individual step timeouts.

  ```ruby
  class MyWorkflow < Ask::Graph
    workflow_timeout 60   # whole workflow must finish within 60s
    step FetchData, timeout: 30
    step ProcessData, timeout: 30
  end
  ```

- **`Ask::Graph.default_workflow_timeout`** — global default total cap for
  all graphs that don't set their own.

### Changed

- **`timeout` renamed to `step_timeout`** — the class-level default timeout
  per step is now `step_timeout`. The inline step option `step X, timeout: 10`
  is unchanged. No alias is kept — the gem is pre-1.0.

  ```ruby
  # Before
  class MyWorkflow < Ask::Graph
    timeout 30
  end
  Ask::Graph.timeout 30

  # After
  class MyWorkflow < Ask::Graph
    step_timeout 30
  end
  Ask::Graph.default_step_timeout 30
  ```

### Tested

- 95 tests, 129 assertions, 0 failures

## [0.6.1] — 2026-07-27

### Fixed

- **Hooks leak between classes** — `inherited` now deep-copies lifecycle
  hook arrays instead of sharing them. Previously, a child class's
  `after_step :foo` would mutate the parent class's hook arrays, causing
  hooks to fire multiple times in sibling classes.

### Changed

- **Docs updated** to use the `Module::Workflow` convention throughout.
  Recommended layout:

  ```
  app/workflows/
    notify_customer/
      workflow.rb          # module NotifyCustomer; class Workflow < Ask::Graph
      steps/
        send_email.rb
        log_notification.rb
    order_fulfillment/
      workflow.rb
      steps/
        validate_payment.rb
        notify_customer.rb
        ship_order.rb
  ```

  Sub-graph composition via `Workflow.call(context)` or `context.run(Workflow)`.

### Tested

- 85 tests, 111 assertions, 0 failures

## [0.6.0] — 2026-07-27

### Changed

- **All steps must be POROs** — the framework no longer auto-detects
  `Ask::Graph` subclasses used directly as steps. Every `step` declaration
  must be a plain Ruby class with a `call(context)` method. This eliminates
  ambiguity at the `step` call site.

  ```ruby
  # Before — worked but was ambiguous
  step NotifyCustomer   # is this a Graph or a PORO?

  # After — always a PORO
  step NotifyCustomer   # definitely a PORO
  ```

- **Sub-graph composition via `Workflow.call(context)`** — compose workflows
  by calling another graph's class method with the current context. The
  method auto-detects a Context argument and handles export → run → import.

  ```ruby
  class NotifyCustomer
    def call(context)
      NotifyCustomerWorkflow.call(context)
    end
  end
  ```

  `Graph.call(ctx)` is the same API users already know from controllers:
  `Graph.call(params)`. Just pass a Context instead of data.

### Added

- **`Context#run(graph_class)`** — convenience wrapper around the export →
  create → call → import pattern.

- **Hash inputs flatten into context keys** — when a Hash is passed as
  input, its keys are directly accessible on the context in addition to
  `context.input`. Enables sub-graphs to transparently read outer values.

- **`Context#export_data`** and **`Context#import(other)`** — public API
  for sub-graph data passing.

### Tested

- 85 tests, 111 assertions, 0 failures

## [0.5.0] — 2026-07-27

### Added

- **Sub-graph composition via `Workflow.call(context)`** — compose workflows
  by calling another graph's `call` class method with the current context.
  The method detects the Context argument and handles export → run → import
  automatically.

  ```ruby
  # Define a workflow
  class NotifyCustomerWorkflow < Ask::Graph
    step SendEmail
    step LogNotification
  end

  # Use it as a step via a PORO wrapper
  class NotifyCustomer
    def call(context)
      NotifyCustomerWorkflow.call(context)
    end
  end

  # Compose — every step is a PORO
  class HandleOrder < Ask::Graph
    step ValidatePayment
    step NotifyCustomer
    step ShipOrder
  end
  ```

  - `Graph.call(context)` exports the context data, creates the sub-graph,
    runs it, and imports results back — all automatically
  - Same API users already know from `Graph.call(params)` in controllers
  - Supports nesting (sub-graphs calling sub-graphs)
  - Supports `timeout:`, `retry:`, and `if:`/`unless:` on the outer step
  - Supports parallel steps inside sub-graphs

- **Hash inputs flatten into context keys** — when a Hash is passed as
  input, its keys are directly accessible on the context in addition to
  `context.input`. This enables sub-graphs to transparently read outer
  context values.

  ```ruby
  g.new({ value: 42 }).call
  ctx.value   # => 42 (directly accessible)
  ctx.input   # => { value: 42 } (still works as before)
  ```

- **`Context#export_data`** — returns the raw store hash without JSON
  serialization. Used internally for sub-graph data passing.

- **`Context#import(other)`** — merges data from another context or hash
  into this one.

- **`Context#run(graph_class)`** — convenience method wrapping the
  export → create → call → import pattern.

  ```ruby
  def call(context)
    context.run(NotifyCustomerWorkflow)
  end
  ```

### Changed

- **All steps are POROs** — the framework no longer detects `Ask::Graph`
  subclasses used directly as steps. Every `step` declaration must be a
  plain Ruby class with a `call(context)` method. This eliminates the
  ambiguity of "is this step a graph or a PORO?"

### Tested

- 85 tests, 111 assertions, 0 failures

## [0.4.0] — 2026-07-27

### Changed

- **`checkpoint_store:` renamed to `storage:`** — shorter, more general name
  for the backend that persists checkpoint data for crash recovery.

  ```ruby
  # Before
  MyGraph.call(input, checkpoint_store: RedisPool.new)
  g.new(input, checkpoint_store: RedisPool.new)

  # After
  MyGraph.call(input, storage: RedisPool.new)
  g.new(input, storage: RedisPool.new)
  ```

### Added

- **Class-level `storage`** — set once at the class level instead of passing
  per-call. Works the same as `timeout`: per-call → graph class → global.

  ```ruby
  # Global default for all graphs
  Ask::Graph.storage RedisPool.new

  # Per-graph override
  class MyGraph < Ask::Graph
    storage PostgresStore.new
  end

  # Per-call override (overrides everything)
  MyGraph.call(input, storage: InMemory.new)
  ```

  Falls back to `Ask::State::Memory.new` when nothing is configured.

### Tested

- 70 tests, 92 assertions, 0 failures

## [0.3.0] — 2026-07-27

### Added

- **Class-level `timeout`** — set a default timeout for all steps in a graph.
  Steps without an explicit `timeout:` option inherit the class default.

  ```ruby
  class MyGraph < Ask::Graph
    timeout 30
    step FastOp   # uses 30s
    step SlowOp, timeout: 120  # overrides
  end
  ```

- **Global default timeout** — `Ask::Graph.timeout 30` applies to all graphs
  that don't set their own `timeout`. Resolution order: step option → graph
  class → `Ask::Graph`.

  ```ruby
  Ask::Graph.timeout 30
  ```

- **Child override and clearing** — child graphs can override or clear
  (`timeout nil`) the parent's default.

### Tested

- 62 tests, 83 assertions, 0 failures

## [0.2.0] — 2026-07-29

### Added

- **Step timeouts** — `step SlowOp, timeout: 30` raises `StepFailed` if a step takes longer than the given seconds.

  ```ruby
  step FetchApi, timeout: 10, retry: 2
  ```

- **Retry policy** — `step FlakyOp, retry: 3` retries failed steps up to the specified number of times with exponential backoff.

  ```ruby
  step ApiCall, retry: 3
  ```

- **Lifecycle hooks** — `before_step`, `after_step`, and `on_failure` hooks for observability, logging, and monitoring.

  ```ruby
  class MyGraph < Ask::Graph
    before_step :log_start
    after_step  :log_completion
    on_failure  :alert_team

    step ProcessPayment, timeout: 15, retry: 2
  end
  ```

  Hooks receive `declaration:` and `context:` keyword args. `on_failure` also receives `error:`.

- **Step metadata** — `step X, description: "Human-readable label"` stores metadata in the declaration for debugging and monitoring.

### Tested

- 55 tests, 73 assertions, 0 failures

## [0.1.3] — 2026-07-28

### Changed

- **Added `ask-state-providers` dependency** — `Ask::State::Memory` is now provided by the `ask-state-providers` gem (moved from `ask-core` 0.8.0). `ask-graph` automatically loads it.

## [0.1.2] — 2026-07-28

### Changed

- **`Graph.new(input).call` API** — input is now passed to the constructor, not to `call`. This reads more naturally: create a graph with data, then execute it. `Graph.call(input, checkpoint_store:)` class method still available for convenience.

  ```ruby
  # Before
  HandleCall.new.call(recording: "call.wav")

  # After
  HandleCall.new({ recording: "call.wav" }).call
  ```

### Tested

- 36 tests, 52 assertions, 0 failures

## [0.1.1] — 2026-07-28

### Fixed

- **Full context checkpointing** — Checkpoints now save the complete context state alongside the step index. On resume, all data produced by completed steps is restored. Previously only the step index was persisted, causing nil errors when resumed steps referenced prior outputs.

- **`call` as primary API** — `Graph.new.call(input)` is now the primary interface, consistent with step classes. `Graph.call` and `Graph.run` remain as convenience class methods.

- **Default in-memory store** — Checkpoint store defaults to `Ask::State::Memory` (shipped with `ask-core`, zero additional dependencies). No database, migration, or configuration needed. Pass a persistent store for crash recovery across restarts.

### Changed

- `context.to_h` now produces JSON-safe hashes (string keys, symbols converted to strings, arrays recursed). Checkpoints serialize correctly in Ruby 4.0.

- `initialize(checkpoint_store:)` stores the checkpoint store on the instance. Pass `nil` to use the default in-memory store.

### Tested

- 36 tests, 52 assertions, 0 failures

## [0.1.0] — 2026-07-28

### Added

- **Initial release** — Durable workflow graphs for the ask-rb ecosystem.

- **Graph definition** — Define workflows with declarative steps:

  ```ruby
  class HandleCall < Ask::Graph
    step Transcribe
    step Classify, if: :needs_classification?
    step BookAppointment
  end
  ```

- **Conditional steps** — `step ClassName, if: :method?` and `step ClassName, unless: :method?` — methods on the graph class control whether a step runs.

- **Parallel execution** — `steps ClassA, ClassB, ClassC` runs multiple steps simultaneously and waits for all to complete before continuing.

- **Human-in-the-loop** — `approve ReviewBooking` runs a step then pauses execution, persisting state and waiting for external input via `resume`.

- **Per-item checkpointing** — `context.each(items)` iterates with automatic checkpointing after each item. Crashes resume from the last completed item, not the beginning.

- **Step checkpointing** — every completed step is persisted via an optional store. Crashes resume from the last completed step.

- **Step failure handling** — failed steps raise `Ask::Graph::StepFailed` with the step name in the message.

- **Inheritance** — child graphs inherit parent steps without affecting the parent.

- **Class and instance execution** — `Graph.run` (class method) or `Graph.new.run` (instance method).

### Tested

- 31 tests, 42 assertions, 0 failures
- Covers: step order, conditions, parallel, approve, checkpointing, context, inheritance, edge cases
