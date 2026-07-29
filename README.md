# ask-graph

**Durable workflow graphs for the ask-rb ecosystem.** Define workflows as graphs of named steps with conditional routing, parallel execution, human-in-the-loop approval, per-item checkpointing loops, and sub-graph composition. Each step is a plain Ruby class.

```ruby
gem "ask-graph"
```

	## Quick Start
	
	```ruby
	require "ask-graph"
	
	# Define a workflow
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
	
	# Run it
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

	### Sequential steps
	
	```ruby
	module HandleCall
	  class Workflow < Ask::Graph
	    step Transcribe
	    step Classify
	    step Respond
	  end
	end
	```
	
	### Conditional steps
	
	```ruby
	module HandleCall
	  class Workflow < Ask::Graph
	    step BookAppointment,  if: :booking?
	    step EmergencyAlert,   if: :emergency?
	    step HandleInquiry,    unless: :known_intent?
	
	    private
	
	    def booking?   = context.intent == "booking"
	    def emergency? = context.intent == "emergency"
	    def known_intent? = %w[booking emergency inquiry].include?(context.intent)
	  end
	end
	```

	### Parallel steps
	
	Use `steps` (plural) to run multiple steps simultaneously:
	
	```ruby
	module SyncData
	  class Workflow < Ask::Graph
	    step FetchRecords
	
	    # All three run in parallel
	    steps CrmUpdate, CalendarSync, SendNotification
	
	    step ConfirmResponse
	  end
	end
	```
	
	### Human-in-the-loop (approve)
	
	`approve` runs a step, then pauses the workflow and waits for external input:
	
	```ruby
	module ProcessBooking
	  class Workflow < Ask::Graph
	    step BookAppointment
	    approve ReviewBooking, if: :expensive?
	    step ConfirmBooking
	  end
	end
	```
	
	After `approve` pauses, resume with:
	
	```ruby
	graph = ProcessBooking::Workflow.new
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
	
	module DailyReminders
	  class Workflow < Ask::Graph
	    step FetchAppointments
	    step SendVoiceReminders  # loops with per-item checkpointing
	    step MarkComplete
	  end
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

A step can delegate to another workflow by calling `Workflow.call(context)`.
The context is automatically exported, passed to the sub-workflow, and
results are merged back on completion:

```ruby
module OrderFulfillment
  class NotifyCustomer
    def call(context)
      NotifyCustomer::Workflow.call(context)
    end
  end

  class Workflow < Ask::Graph
    step ValidatePayment
    step NotifyCustomer
    step ShipOrder
  end
end
```

Or use `context.run` for the same thing:

```ruby
class NotifyCustomer
  def call(context)
    context.run(NotifyCustomer::Workflow)
  end
end
```

### Checkpointing

Pass a `storage` backend to make workflows durable across crashes:

```ruby
store = Ask::State::Memory.new  # or Redis, SQLite, etc.

# Runs through all steps, saving after each
result = OrderFulfillment::Workflow.call(input, storage: store)

# If a crash occurs, resume from the last completed step
result = OrderFulfillment::Workflow.call(input, storage: store)
```

### Error handling

Failed steps raise `Ask::Graph::StepFailed` with the step name:

```ruby
module MyWorkflow
  class Workflow < Ask::Graph
    step RiskyOperation
  end
end

begin
  MyWorkflow::Workflow.call
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
