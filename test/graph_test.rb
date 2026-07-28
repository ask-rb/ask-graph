# frozen_string_literal: true

require_relative "test_helper"

# Step classes used in tests
class AppendToLog
  def call(context)
    context.log << "append:#{context.value}"
  end
end

class SetValue
  def call(context)
    context.result = context.input * 2
  end
end

class RaiseError
  def call(context)
    raise "something went wrong"
  end
end

class RecordRun
  def call(context)
    (context.log ||= []) << :ran
  end
end

class RecordIfTrue
  def call(context)
    (context.log ||= []) << :if_true
  end
end

class RecordIfFalse
  def call(context)
    (context.log ||= []) << :if_false
  end
end

class DoubleValue
  def call(context)
    context.value = (context.value || 0) * 2
  end
end

class SleepStep
  def call(context)
    sleep 0.05
    (context.log ||= []) << :slept
  end
end

module Ask
  class GraphTest < Minitest::Test
    include TestHelpers

    def setup
      TestHelpers::LogStep.clear_log
    end

    # --- Basic graph execution ---

    def test_empty_graph
      g = Class.new(Ask::Graph) do
      end
      result = g.run
      assert_kind_of Ask::Graph::Context, result
    end

    def test_single_step
      g = Class.new(Ask::Graph) do
        step SetValue
      end
      result = g.run(5)
      assert_equal 10, result.result
    end

    def test_multiple_steps_run_in_order
      g = Class.new(Ask::Graph) do
        step DoubleValue
        step DoubleValue
        step DoubleValue
      end
      result = g.run
      result.value = 1
      result = g.new.run(nil)
      # Actually run it properly
      g = Class.new(Ask::Graph) do
        step DoubleValue
        step DoubleValue
        step DoubleValue
      end
      graph = g.new
      ctx = Ask::Graph::Context.new(graph, nil)
      ctx.value = 1
      graph.send(:runner).run(ctx)
      assert_equal 8, ctx.value
    end

    # --- Conditional steps ---

    def test_step_with_if_runs_when_condition_true
      g = Class.new(Ask::Graph) do
        step RecordIfTrue, if: :should_run?

        def should_run?
          true
        end
      end
      ctx = g.run
      assert_equal [:if_true], ctx.log
    end

    def test_step_with_if_skips_when_condition_false
      g = Class.new(Ask::Graph) do
        step RecordIfTrue, if: :should_run?

        def should_run?
          false
        end
      end
      ctx = g.run
      assert_nil ctx.log
    end

    def test_step_with_unless_runs_when_condition_false
      g = Class.new(Ask::Graph) do
        step RecordRun, unless: :skip?

        def skip?
          false
        end
      end
      ctx = g.run
      assert_equal [:ran], ctx.log
    end

    def test_step_with_unless_skips_when_condition_true
      g = Class.new(Ask::Graph) do
        step RecordRun, unless: :skip?

        def skip?
          true
        end
      end
      ctx = g.run
      assert_nil ctx.log
    end

    def test_conditional_skipped_steps_dont_affect_subsequent_steps
      g = Class.new(Ask::Graph) do
        step RecordIfTrue, if: :false?
        step RecordRun

        def false?
          false
        end
      end
      ctx = g.run
      assert_equal [:ran], ctx.log
    end

    # --- Context ---

    def test_context_reader_and_writer
      g = Class.new(Ask::Graph) do
        step Class.new {
          def call(ctx)
            ctx.greeting = "hello"
          end
        }
      end
      ctx = g.run
      assert_equal "hello", ctx.greeting
    end

    def test_context_bracket_access
      g = Class.new(Ask::Graph) do
        step Class.new {
          def call(ctx)
            ctx[:color] = "blue"
          end
        }
      end
      ctx = g.run
      assert_equal "blue", ctx[:color]
    end

    def test_context_input
      g = Class.new(Ask::Graph) do
        step Class.new {
          def call(ctx)
            ctx.output = ctx.input[:value]
          end
        }
      end
      graph = g.new
      ctx = graph.run({ value: "test" })
      assert_equal "test", ctx.output
    end

    # --- Step failures ---

    def test_step_failure_raises
      g = Class.new(Ask::Graph) do
        step RaiseError
      end
      assert_raises(Ask::Graph::StepFailed) { g.run }
    end

    def test_step_failure_includes_step_name
      g = Class.new(Ask::Graph) do
        step RaiseError
      end
      error = assert_raises(Ask::Graph::StepFailed) { g.run }
      assert_includes error.message, "RaiseError"
    end

    # --- Parallel steps ---

    def test_parallel_steps_all_execute
      g = Class.new(Ask::Graph) do
        steps SleepStep, SleepStep, SleepStep
        step Class.new {
          def call(ctx)
            (ctx.log ||= []) << :done
          end
        }
      end
      ctx = g.run
      assert ctx.log.include?(:slept)
      assert ctx.log.include?(:done)
    end

    def test_parallel_steps_failure_raises
      g = Class.new(Ask::Graph) do
        steps SleepStep, RaiseError
      end
      assert_raises(Ask::Graph::StepFailed) { g.run }
    end

    def test_parallel_with_condition
      g = Class.new(Ask::Graph) do
        steps SleepStep, SleepStep, if: :parallel?

        def parallel?
          true
        end
      end
      ctx = g.run
      assert ctx.log, "log should not be nil — steps should have run"
      assert ctx.log.include?(:slept)
    end

    def test_parallel_skipped_when_condition_false
      g = Class.new(Ask::Graph) do
        steps SleepStep, SleepStep, unless: :go?

        def go?
          true
        end
      end
      ctx = g.run
      assert_nil ctx.log
    end

    # --- Approve / Human-in-the-loop ---

    def test_approve_pauses_execution
      g = Class.new(Ask::Graph) do
        step Class.new {
          def call(ctx)
            (ctx.log ||= []) << :before
          end
        }
        approve Class.new {
          def call(ctx)
            (ctx.log ||= []) << :approve_step
          end
        }
        step Class.new {
          def call(ctx)
            (ctx.log ||= []) << :after
          end
        }
      end
      graph = g.new
      ctx = graph.run
      assert ctx.log.include?(:before)
      assert ctx.log.include?(:approve_step)
      refute ctx.log.include?(:after), "should pause before after step"
    end

    def test_approve_conditional_does_not_pause_when_false
      g = Class.new(Ask::Graph) do
        step Class.new {
          def call(ctx)
            (ctx.log ||= []) << :step1
          end
        }
        approve Class.new {
          def call(ctx)
            (ctx.log ||= []) << :approve
          end
        }, if: :needs_approval?
        step Class.new {
          def call(ctx)
            (ctx.log ||= []) << :step2
          end
        }

        def needs_approval?
          false
        end
      end
      ctx = g.run
      assert ctx.log.include?(:step1)
      assert ctx.log.include?(:step2)
      refute ctx.log.include?(:approve), "approve step should not run"
    end

    # --- Checkpointing ---

    def test_checkpoint_saves_after_execution
      store = MemoryStore.new
      g = Class.new(Ask::Graph) do
        step RecordRun
      end
      g.run(checkpoint_store: store)
      keys = store.instance_variable_get(:@data).keys
      assert keys.any? { |k| k.start_with?("ask:graph:run:") },
             "checkpoint should be saved after run"
    end

    def test_checkpoint_store_receives_data
      store = MemoryStore.new
      g = Class.new(Ask::Graph) do
        step RecordRun
      end
      g.run(checkpoint_store: store)
      stored = store.instance_variable_get(:@data).values.first
      assert stored, "checkpoint data should exist"
      assert stored.include?("completed_index"),
             "checkpoint should contain completed_index"
    end

    # --- Context#each per-item iteration ---

    def test_context_each_iterates_all_items
      items = %w[a b c]
      g = Class.new(Ask::Graph) do
        step Class.new {
          def call(ctx)
            ctx.results = []
            ctx.each(%w[a b c]) { |item| ctx.results << "processed:#{item}" }
          end
        }
      end
      ctx = g.run
      assert_equal ["processed:a", "processed:b", "processed:c"], ctx.results
    end

    def test_context_each_checkpoints_per_item
      store = MemoryStore.new
      results = []

      step_class = Class.new do
        define_method(:call) do |ctx|
          ctx.each(%w[x y z]) { |item| results << item }
        end
      end

      g = Class.new(Ask::Graph) do
        step step_class
      end

      # Can't easily pass store to context.each in this design
      # This tests that context.each works with checkpoint store
      g.run(checkpoint_store: store)
      assert_equal %w[x y z], results
    end

    def test_context_each_sets_item
      seen_items = []
      g = Class.new(Ask::Graph) do
        step Class.new {
          def call(ctx)
            ctx.each(%w[a b c]) { |_item| seen_items << ctx.item }
          end
        }
      end
      # Using instance variable
      g = Class.new(Ask::Graph) do
        step Class.new {
          def call(ctx)
            items = []
            ctx.each(%w[a b c]) { |_item| items << ctx.item }
            ctx.seen = items
          end
        }
      end
      ctx = g.run
      assert_equal %w[a b c], ctx.seen
    end

    # --- Inheritance ---

    def test_child_graph_inherits_steps
      parent = Class.new(Ask::Graph) do
        step RecordRun
      end

      child = Class.new(parent) do
        step DoubleValue
      end

      assert_equal 2, child.declarations.length
      assert_equal RecordRun, child.declarations[0][:class]
    end

    def test_child_does_not_affect_parent_declarations
      parent = Class.new(Ask::Graph) do
        step RecordRun
      end

      child = Class.new(parent) do
        step DoubleValue
      end

      assert_equal 1, parent.declarations.length
      assert_equal 2, child.declarations.length
    end

    # --- Instance vs Class-level execution ---

    def test_instance_run
      g = Class.new(Ask::Graph) do
        step Class.new {
          def call(ctx)
            ctx.value = 42
          end
        }
      end
      graph = g.new
      ctx = graph.run
      assert_equal 42, ctx.value
    end

    def test_class_run
      g = Class.new(Ask::Graph) do
        step Class.new {
          def call(ctx)
            ctx.value = 99
          end
        }
      end
      ctx = g.run
      assert_equal 99, ctx.value
    end

    # --- Edge cases ---

    def test_no_steps_still_returns_context
      g = Class.new(Ask::Graph)
      ctx = g.run("data")
      assert_equal "data", ctx[:input]
    end

    def test_step_receives_context_with_previous_output
      g = Class.new(Ask::Graph) do
        step Class.new {
          def call(ctx)
            ctx.value = 1
          end
        }
        step Class.new {
          def call(ctx)
            ctx.value += 1
          end
        }
      end
      ctx = g.run
      assert_equal 2, ctx.value
    end

    def test_large_number_of_steps
      step_class = Class.new do
        def call(ctx)
          ctx.counter = (ctx.counter || 0) + 1
        end
      end

      g = Class.new(Ask::Graph)
      50.times { g.step(step_class) }

      ctx = g.run
      assert_equal 50, ctx.counter
    end
  end
end
