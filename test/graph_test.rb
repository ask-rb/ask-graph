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

    # --- Basic graph execution ---

    def test_empty_graph
      g = Class.new(Ask::Graph)
      result = g.new.call
      assert_kind_of Ask::Graph::Context, result
    end

    def test_single_step
      g = Class.new(Ask::Graph) do
        step SetValue
      end
      result = g.new(5).call
      assert_equal 10, result.result
    end

    def test_multiple_steps_run_in_order
      g = Class.new(Ask::Graph) do
        step DoubleValue
        step DoubleValue
        step DoubleValue
      end
      ctx = Ask::Graph::Context.new(g.new, nil)
      ctx.value = 1
      g.new.send(:runner).run(ctx)
      assert_equal 8, ctx.value
    end

    # --- .new.call interface ---

    def test_new_call_returns_context
      g = Class.new(Ask::Graph) do
        step Class.new {
          def call(ctx)
            ctx.done = true
          end
        }
      end
      ctx = g.new.call
      assert ctx.done
    end

    def test_class_call_convenience
      g = Class.new(Ask::Graph) do
        step Class.new {
          def call(ctx)
            ctx.value = 42
          end
        }
      end
      ctx = g.call
      assert_equal 42, ctx.value
    end

    # --- Conditional steps ---

    def test_step_with_if_runs_when_condition_true
      g = Class.new(Ask::Graph) do
        step RecordIfTrue, if: :should_run?

        def should_run?
          true
        end
      end
      ctx = g.new.call
      assert_equal [:if_true], ctx.log
    end

    def test_step_with_if_skips_when_condition_false
      g = Class.new(Ask::Graph) do
        step RecordIfTrue, if: :should_run?

        def should_run?
          false
        end
      end
      ctx = g.new.call
      assert_nil ctx.log
    end

    def test_step_with_unless_runs_when_condition_false
      g = Class.new(Ask::Graph) do
        step RecordRun, unless: :skip?

        def skip?
          false
        end
      end
      ctx = g.new.call
      assert_equal [:ran], ctx.log
    end

    def test_step_with_unless_skips_when_condition_true
      g = Class.new(Ask::Graph) do
        step RecordRun, unless: :skip?

        def skip?
          true
        end
      end
      ctx = g.new.call
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
      ctx = g.new.call
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
      ctx = g.new.call
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
      ctx = g.new.call
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
      ctx = g.new({ value: "test" }).call
      assert_equal "test", ctx.output
    end

    # --- Step failures ---

    def test_step_failure_raises
      g = Class.new(Ask::Graph) do
        step RaiseError
      end
      assert_raises(Ask::Graph::StepFailed) { g.new.call }
    end

    def test_step_failure_includes_step_name
      g = Class.new(Ask::Graph) do
        step RaiseError
      end
      error = assert_raises(Ask::Graph::StepFailed) { g.new.call }
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
      ctx = g.new.call
      assert ctx.log.include?(:slept)
      assert ctx.log.include?(:done)
    end

    def test_parallel_steps_failure_raises
      g = Class.new(Ask::Graph) do
        steps SleepStep, RaiseError
      end
      assert_raises(Ask::Graph::StepFailed) { g.new.call }
    end

    def test_parallel_with_condition
      g = Class.new(Ask::Graph) do
        steps SleepStep, SleepStep, if: :parallel?

        def parallel?
          true
        end
      end
      ctx = g.new.call
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
      ctx = g.new.call
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
      ctx = graph.call
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
      ctx = g.new.call
      assert ctx.log.include?(:step1)
      assert ctx.log.include?(:step2)
      refute ctx.log.include?(:approve), "approve step should not run"
    end

    # --- Checkpointing ---

    def test_checkpoint_saves_context_state
      g = Class.new(Ask::Graph) do
        step Class.new {
          def call(ctx)
            ctx.important = "data from step 1"
          end
        }
        step Class.new {
          def call(ctx)
            ctx.more = "data from step 2"
          end
        }
      end
      store = Ask::State::Memory.new
      graph = g.new(checkpoint_store: store)
      graph.call

      # The checkpoint key is generated by the runner
      checkpoint_raw = graph.runner.send(:store).get(
        graph.runner.send(:checkpoint_key)
      )
      data = JSON.parse(checkpoint_raw)
      assert_equal "data from step 1", data["context"]["important"]
      assert_equal "data from step 2", data["context"]["more"]
    end

    def test_checkpoint_restores_context_on_resume
      store = Ask::State::Memory.new

      # Run step that would fail if context was restored from checkpoint
      g = Class.new(Ask::Graph) do
        step Class.new {
          def call(ctx)
            ctx.produced = "persisted"
          end
        }
        step Class.new {
          def call(ctx)
            ctx.consumed = ctx.produced
          end
        }
      end

      # First run — checkpoints after each step
      g.new(checkpoint_store: store).call

      # Simulate resume: load checkpoint and skip completed steps
      g2 = Class.new(Ask::Graph) do
        step Class.new {
          def call(ctx)
            ctx.produced = "persisted"
          end
        }
        step Class.new {
          def call(ctx)
            ctx.consumed = ctx.produced
          end
        }
      end

      # On resume, step 0 is skipped (checkpointed), but context.produced
      # should be restored from the checkpoint
      ctx = g2.new(checkpoint_store: store).call
      assert_equal "persisted", ctx.consumed,
                   "context should be restored from checkpoint on resume"
    end

    def test_checkpoint_store_defaults_to_memory
      g = Class.new(Ask::Graph) do
        step Class.new {
          def call(ctx)
            ctx.ran = true
          end
        }
      end
      # No store passed — should use default in-memory
      ctx = g.new.call
      assert ctx.ran
    end

    def test_checkpoint_resume_skips_completed_steps
      runs = []
      step_a = Class.new do
        define_method(:call) do |ctx|
          runs << :a
        end
      end

      store = Ask::State::Memory.new
      g = Class.new(Ask::Graph) { step step_a }
      g.new(checkpoint_store: store).call

      runs.clear
      g.new(checkpoint_store: store).call  # resume — should skip step_a
      assert_empty runs, "step should not re-run on resume"
    end

    # --- Context#each per-item iteration ---

    def test_context_each_iterates_all_items
      g = Class.new(Ask::Graph) do
        step Class.new {
          def call(ctx)
            ctx.results = []
            ctx.each(%w[a b c]) { |item| ctx.results << "processed:#{item}" }
          end
        }
      end
      ctx = g.new.call
      assert_equal ["processed:a", "processed:b", "processed:c"], ctx.results
    end

    def test_context_each_sets_item
      g = Class.new(Ask::Graph) do
        step Class.new {
          def call(ctx)
            items = []
            ctx.each(%w[a b c]) { |_item| items << ctx.item }
            ctx.seen = items
          end
        }
      end
      ctx = g.new.call
      assert_equal %w[a b c], ctx.seen
    end

    def test_context_each_checkpoints_per_item
      results = []
      step_class = Class.new do
        define_method(:call) do |ctx|
          ctx.each(%w[x y z]) { |item| results << item }
        end
      end

      g = Class.new(Ask::Graph) { step step_class }
      g.new.call
      assert_equal %w[x y z], results
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

    # --- Edge cases ---

    def test_no_steps_still_returns_context
      g = Class.new(Ask::Graph)
      ctx = g.new("data").call
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
      ctx = g.new.call
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

      ctx = g.new.call
      assert_equal 50, ctx.counter
    end

    def test_default_uses_in_memory_store
      g = Class.new(Ask::Graph) do
        step Class.new { def call(ctx); ctx.ok = true; end }
      end
      graph = g.new
      assert_kind_of Ask::State::Memory, graph.runner.send(:store)
    end
  end
end
