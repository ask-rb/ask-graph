# ask-graph

**Durable workflow graphs for the ask-rb ecosystem.** Define workflows as graphs of named steps with conditional routing, parallel execution, human-in-the-loop approval, per-item checkpointing loops, and sub-graph composition. Each step is a plain Ruby class.

```ruby
gem "ask-graph"
```

## Quick Start

```ruby
require "ask-graph"

# Define a workflow
class ProcessOrder < Ask::Graph
  step ValidateOrder
  step ChargeCustomer,  if: :valid?
  step SendConfirmation, if: :valid?
  step NotifyAdmin,     unless: :valid?

  private

  def valid?
    context.order.valid?
  end
end

# Run it
result = ProcessOrder.run(order: order)
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

### Sequential steps

```ruby
class HandleCall < Ask::Graph
  step Transcribe
  step Classify
  step Respond
end
```

### Conditional steps

```ruby
class HandleCall < Ask::Graph
  step BookAppointment,  if: :booking?
  step EmergencyAlert,   if: :emergency?
  step HandleInquiry,    unless: :known_intent?

  private

  def booking?   = context.intent == "booking"
  def emergency? = context.intent == "emergency"
  def known_intent? = %w[booking emergency inquiry].include?(context.intent)
end
```

### Parallel steps

Use `steps` (plural) to run multiple steps simultaneously:

```ruby
class SyncData < Ask::Graph
  step FetchRecords

  # All three run in parallel
  steps CrmUpdate, CalendarSync, SendNotification

  step ConfirmResponse
end
```

### Human-in-the-loop (approve)

`approve` runs a step, then pauses the workflow and waits for external input:

```ruby
class ProcessBooking < Ask::Graph
  step BookAppointment
  approve ReviewBooking, if: :expensive?
  step ConfirmBooking
end
```

After `approve` pauses, resume with:

```ruby
graph = ProcessBooking.new
result = graph.run              # runs, pauses after ReviewBooking
result = graph.resume(input: "approved")  # resumes, runs ConfirmBooking
```

### Per-item loops

Use `context.each` inside a step for iteration with automatic checkpointing:

```ruby
class SendVoiceReminders
  def call(context)
    context.each(context.appointments) do |appt|
      PhoneService.call(appt.number, appt.message)
    end
  end
end

class DailyReminders < Ask::Graph
  step FetchAppointments
  step SendVoiceReminders  # loops with per-item checkpointing
  step MarkComplete
end
```

If the process crashes mid-loop, it resumes from the last completed item.

### Context

Shared state flows between steps via `context`:

```ruby
class SetValue
  def call(context)
    context.greeting = "hello"        # set via method
    context[:color] = "blue"          # set via bracket
  end
end

class ReadValue
  def call(context)
    puts context.greeting             # => "hello"
    puts context[:color]              # => "blue"
  end
end
```

### Sub-workflows

A step can delegate to another workflow:

```ruby
class IntentHandler
  def call(context)
    case context.intent
    when "booking"
      BookingWorkflow.new.call(context)  # sub-workflow as a step
    when "emergency"
      EmergencyWorkflow.new.call(context)
    end
  end
end
```

### Checkpointing

Pass a checkpoint store to make workflows durable across crashes:

```ruby
store = Ask::State::Memory.new  # or Redis, SQLite, etc.

# Runs through all steps, saving after each
result = MyWorkflow.run(input, checkpoint_store: store)

# If a crash occurs, resume from the last completed step
result = MyWorkflow.run(input, checkpoint_store: store)
```

### Error handling

Failed steps raise `Ask::Graph::StepFailed` with the step name:

```ruby
class MyGraph < Ask::Graph
  step RiskyOperation
end

begin
  MyGraph.run
rescue Ask::Graph::StepFailed => e
  puts e.message  # => "RiskyOperation failed: connection timeout"
end
```

## Development

```bash
bundle exec rake test
```

## License

MIT
