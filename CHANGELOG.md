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
