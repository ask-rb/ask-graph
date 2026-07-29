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
