# ask-graph

Durable workflow graphs for the ask-rb ecosystem. Define workflows as graphs
of named steps with conditional routing, parallel execution, human-in-the-loop
approval, per-item checkpointing loops, and sub-graph composition. Each step
is a plain Ruby class with a `call(context)` method.

ask-graph is for deterministic pipelines: you declare the steps and the
routing. For LLM-driven loops that decide their own next step, use
ask-agent instead.

## Installation

```ruby
gem "ask-graph"
```

## Quick Start

```ruby
require "ask-graph"

module ProcessOrder
  class Workflow < Ask::Graph
    step ValidateOrder
    step ChargeCustomer,  if: :valid?
    step SendConfirmation, if: :valid?
    step NotifyAdmin,     unless: :valid?

    private

    def valid?
      context.order.valid?
    end
  end
end

result = ProcessOrder::Workflow.call(order: order)
```

## Steps

Steps are plain Ruby classes with a `call(context)` method:

```ruby
class ValidateOrder
  def call(context)
    context.order = OrderValidator.validate(context.order)
  end
end
```

| Declaration | Behavior |
|---|---|
| `step Klass` | Run a step in order |
| `step Klass, if: :method?` / `unless: :method?` | Conditional routing |
| `step Klass, timeout: 30, retry: 3` | Per-step timeout and retry |
| `step Klass, description: "..."` | Human-readable label |
| `steps A, B, C` | Run multiple steps in parallel |
| `approve Klass` | Run the step, then pause and wait for external input |

A paused workflow resumes with `graph.resume(input: "approved")` after
`graph.run`.

### Context

Shared state flows between steps. Set and read values by method or bracket,
iterate with per-item checkpointing, and run sub-workflows:

```ruby
class SendVoiceReminders
  def call(context)
    context.greeting = "hello"          # method access
    context[:color] = "blue"            # bracket access

    context.each(context.appointments) do |appt|  # per-item checkpointing
      PhoneService.call(appt.number, appt.message)
    end

    context.run(NotifyCustomer::Workflow)         # sub-workflow
  end
end
```

If the process crashes mid-loop, it resumes from the last completed item.

## Storage and Checkpointing

Pass a storage backend to make workflows durable across crashes. The default
is `Ask::State::Memory`; any backend from ask-state-providers works:

```ruby
store = Ask::State::Memory.new  # or Redis, SQLite, etc.

# Runs through all steps, saving after each; a later call resumes
result = OrderFulfillment::Workflow.call(input, storage: store)
```

`Ask::Graph.storage(store)` sets a class-level default for the workflow.

## Errors and Hooks

Failed steps raise `Ask::Graph::StepFailed`; timeouts raise `StepTimeout`,
`WorkflowTimeout`, and approval pauses raise `Paused`.

Declare lifecycle hooks with `before_step :method`, `after_step :method`, and
`on_failure :method`. Set timeouts at the class level with `step_timeout` (or
its alias `default_step_timeout`) and `workflow_timeout`.

## Full documentation

The full ask-rb documentation lives at https://ask-rb.github.io/ask-docs.
https://ask-rb.github.io/ask-docs/core/graph covers ask-graph in depth,
including crash recovery, inheritance, and the full configuration reference.
API reference: https://ask-rb.github.io/ask-docs/reference/api.

## Development

bundle install
bundle exec rake test

## License

MIT
