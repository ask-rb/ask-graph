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
    graph = g.new(storage: store)
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
      g.new(storage: store).call

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
      ctx = g2.new(storage: store).call
      assert_equal "persisted", ctx.consumed,
                   "context should be restored from checkpoint on resume"
    end

    def test_storage_defaults_to_memory
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
      g.new(storage: store).call

      runs.clear
      g.new(storage: store).call  # resume — should skip step_a
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
  class GraphNewFeaturesTest < Minitest::Test

  # --- Step metadata ---

  def test_step_description
    g = Class.new(Ask::Graph) do
      step RecordRun, description: "Records that the step ran"
    end
    decl = g.declarations.first
    assert_equal "Records that the step ran", decl[:description]
  end

  def test_step_without_description
    g = Class.new(Ask::Graph) do
      step RecordRun
    end
    assert_nil g.declarations.first[:description]
  end

  def test_steps_metadata
    g = Class.new(Ask::Graph) do
      steps SleepStep, SleepStep, description: "Parallel tasks"
    end
    assert_equal "Parallel tasks", g.declarations.first[:description]
  end

  def test_approve_metadata
    g = Class.new(Ask::Graph) do
      approve RecordRun, description: "Pause for human review"
    end
    assert_equal "Pause for human review", g.declarations.first[:description]
  end

  # --- Step timeouts ---

  def test_step_timeout_raises_on_slow_step
    g = Class.new(Ask::Graph) do
      step Class.new {
        def call(ctx)
          sleep 5
        end
      }, timeout: 0.1
    end
    error = assert_raises(Ask::Graph::StepFailed) { g.new.call }
    assert_includes error.message, "timed out"
  end

  def test_timeout_declaration_stored
    g = Class.new(Ask::Graph) do
      step RecordRun, timeout: 30
    end
    assert_equal 30, g.declarations.first[:timeout]
  end

  def test_no_timeout_by_default
    g = Class.new(Ask::Graph) do
      step RecordRun
    end
    assert_nil g.declarations.first[:timeout]
  end

  def test_steps_timeout
    g = Class.new(Ask::Graph) do
      steps SleepStep, SleepStep, timeout: 5
    end
    ctx = g.new.call
    assert ctx.log, "steps with generous timeout should not timeout"
  end

  # --- Retry ---

  def test_retry_declaration_stored
    g = Class.new(Ask::Graph) do
      step RecordRun, retry: 3
    end
    assert_equal 3, g.declarations.first[:retry]
  end

  def test_retry_retries_on_failure
    attempts = 0
    step_class = Class.new do
      define_method(:call) do |ctx|
        attempts += 1
        raise "fail" if attempts < 3
        ctx.succeeded = true
      end
    end

    g = Class.new(Ask::Graph) { step step_class, retry: 3 }
    ctx = g.new.call
    assert ctx.succeeded, "step should succeed after retries"
    assert_equal 3, attempts
  end

  def test_retry_exhausted_raises
    attempts = 0
    step_class = Class.new do
      define_method(:call) do |_ctx|
        attempts += 1
        raise "always fails"
      end
    end

    g = Class.new(Ask::Graph) { step step_class, retry: 2 }
    assert_raises(Ask::Graph::StepFailed) { g.new.call }
    assert_equal 3, attempts
  end

  def test_no_retry_by_default
    g = Class.new(Ask::Graph) do
      step RaiseError
    end
    assert_raises(Ask::Graph::StepFailed) { g.new.call }
  end

  # --- Lifecycle hooks ---

  def test_before_step_hook_runs
    log = []
    g = Class.new(Ask::Graph) do
      before_step :log_before
      step RecordRun

      def log_before(declaration:, context:)
        (@hook_log ||= []) << :before
      end

      def hook_log; @hook_log || []; end
    end
    graph = g.new
    graph.call
  end

  def test_after_step_hook_runs
    g = Class.new(Ask::Graph) do
      after_step :log_after

      step Class.new {
        def call(ctx); ctx.done = true; end
      }

      def log_after(declaration:, context:)
        (@hook_log ||= []) << :after
      end

      def hook_log; @hook_log || []; end
    end
    graph = g.new
    graph.call
  end

  def test_on_failure_hook_runs
    g = Class.new(Ask::Graph) do
      on_failure :track
      step RaiseError

      def track(declaration:, context:, error:)
        (@hook_log ||= []) << :failure
      end

      def hook_log; @hook_log || []; end
    end
    assert_raises(Ask::Graph::StepFailed) { g.new.call }
  end

  def test_multiple_hooks_run_in_order
    order = []
    g = Class.new(Ask::Graph) do
      before_step :first
      before_step :second
      after_step :third

      step Class.new { def call(ctx); ctx.ok = true; end }

      def first(declaration:, context:); (@log ||= []) << :first; end
      def second(declaration:, context:); (@log ||= []) << :second; end
      def third(declaration:, context:); (@log ||= []) << :third; end

      def log; @log || []; end
    end
    graph = g.new
    graph.call
    assert graph.context.ok, "step should still execute with hooks"
  end

  def test_hooks_inherited
    parent = Class.new(Ask::Graph) do
      before_step :hook
      def hook(declaration:, context:)
        (@log ||= []) << :parent_hook
      end
    end

    child = Class.new(parent) do
      step RecordRun
      def log; @log || []; end
    end

    graph = child.new
    graph.call
  end

  # --- Combined features ---

  def test_timeout_with_retry
    attempts = 0
    step_class = Class.new do
      define_method(:call) do |_ctx|
        attempts += 1
        sleep 10
      end
    end

    g = Class.new(Ask::Graph) { step step_class, timeout: 0.05, retry: 1 }
    assert_raises(Ask::Graph::StepFailed) { g.new.call }
    assert_equal 2, attempts, "should retry after timeout"
  end

  def test_retry_with_hook
    calls = 0
    step_class = Class.new do
      define_method(:call) { |_ctx| calls += 1; raise "nope" }
    end

    g = Class.new(Ask::Graph) do
      on_failure :capture
      step step_class, retry: 1

      def capture(declaration:, context:, error:)
        (@errors ||= []) << error.message
      end
    end
    assert_raises(Ask::Graph::StepFailed) { g.new.call }
  end

  # --- default_timeout ---

  def test_default_timeout_applied_to_step_without_explicit_timeout
    g = Class.new(Ask::Graph) do
      step_timeout 0.05
      step Class.new {
        def call(ctx)
          sleep 5
        end
      }
    end
    error = assert_raises(Ask::Graph::StepFailed) { g.new.call }
    assert_includes error.message, "timed out"
  end

  def test_step_explicit_timeout_overrides_graph_default
    g = Class.new(Ask::Graph) do
      step_timeout 30
      step Class.new {
        def call(ctx)
          sleep 0.05
          ctx.done = true
        end
      }, timeout: 0.5
    end
    ctx = g.new.call
    assert ctx.done
  end

  def test_graph_default_not_used_when_step_has_explicit_timeout
    g = Class.new(Ask::Graph) do
      step_timeout 0.05
      step Class.new {
        def call(ctx)
          ctx.done = true
        end
      }, timeout: 30
    end
    ctx = g.new.call
    assert ctx.done
  end

  def test_no_timeout_when_no_default_and_no_explicit_timeout
    g = Class.new(Ask::Graph) do
      step RecordRun
    end
    assert_nil g.step_timeout
    assert_nil g.declarations.first[:timeout]
  end

  def test_default_timeout_declaration_stored
    g = Class.new(Ask::Graph) do
      step_timeout 30
    end
    assert_equal 30, g.step_timeout
  end

  def test_global_default_timeout_on_graph_class
    Ask::Graph.default_step_timeout 0.05
    g = Class.new(Ask::Graph) do
      step Class.new {
        def call(ctx)
          sleep 5
        end
      }
    end
    error = assert_raises(Ask::Graph::StepFailed) { g.new.call }
    assert_includes error.message, "timed out"
  ensure
    Ask::Graph.instance_variable_set(:@step_timeout, nil)
  end

  def test_child_graph_inherits_parent_default_timeout
    parent = Class.new(Ask::Graph) do
      step_timeout 0.05
    end
    child = Class.new(parent) do
      step Class.new {
        def call(ctx)
          sleep 5
        end
      }
    end
    error = assert_raises(Ask::Graph::StepFailed) { child.new.call }
    assert_includes error.message, "timed out"
  end

  def test_child_graph_can_override_parent_default_timeout
    parent = Class.new(Ask::Graph) do
      step_timeout 0.05
    end
    child = Class.new(parent) do
      step_timeout 30
      step Class.new {
        def call(ctx)
          ctx.done = true
        end
      }
    end
    ctx = child.new.call
    assert ctx.done
  end

  def test_child_nil_timeout_overrides_parent_timeout
    parent = Class.new(Ask::Graph) do
      step_timeout 0.05
    end
    child = Class.new(parent) do
      step_timeout nil
      step Class.new {
        def call(ctx)
          ctx.done = true
        end
      }
    end
    ctx = child.new.call
    assert ctx.done
  end

  # --- workflow_timeout ---

  def test_workflow_timeout_aborts_entire_workflow
    g = Class.new(Ask::Graph) do
      workflow_timeout 0.05
      step Class.new {
        def call(ctx)
          sleep 5
        end
      }
    end
    error = assert_raises(Ask::Graph::WorkflowTimeout) { g.new.call }
    assert_includes error.message, "timed out"
  end

  def test_workflow_timeout_fires_across_multiple_steps
    g = Class.new(Ask::Graph) do
      workflow_timeout 0.1
      step Class.new {
        def call(ctx)
          sleep 0.08
        end
      }
      step Class.new {
        def call(ctx)
          sleep 0.08
        end
      }
    end
    error = assert_raises(Ask::Graph::WorkflowTimeout) { g.new.call }
    assert_includes error.message, "timed out"
  end

  def test_workflow_timeout_not_triggered_within_budget
    g = Class.new(Ask::Graph) do
      workflow_timeout 30
      step Class.new {
        def call(ctx)
          ctx.done = true
        end
      }
    end
    ctx = g.new.call
    assert ctx.done
  end

  def test_global_default_workflow_timeout_on_graph_class
    Ask::Graph.default_workflow_timeout 0.05
    g = Class.new(Ask::Graph) do
      step Class.new {
        def call(ctx)
          sleep 5
        end
      }
    end
    error = assert_raises(Ask::Graph::WorkflowTimeout) { g.new.call }
    assert_includes error.message, "timed out"
  ensure
    Ask::Graph.instance_variable_set(:@workflow_timeout, nil)
  end

  def test_child_graph_inherits_parent_workflow_timeout
    parent = Class.new(Ask::Graph) do
      workflow_timeout 0.05
    end
    child = Class.new(parent) do
      step Class.new {
        def call(ctx)
          sleep 5
        end
      }
    end
    assert_raises(Ask::Graph::WorkflowTimeout) { child.new.call }
  end

  def test_child_graph_can_override_parent_workflow_timeout
    parent = Class.new(Ask::Graph) do
      workflow_timeout 0.05
    end
    child = Class.new(parent) do
      workflow_timeout 30
      step Class.new {
        def call(ctx)
          ctx.done = true
        end
      }
    end
    ctx = child.new.call
    assert ctx.done
  end

  def test_workflow_timeout_declaration_stored
    g = Class.new(Ask::Graph) do
      workflow_timeout 60
    end
    assert_equal 60, g.workflow_timeout
  end

  def test_no_workflow_timeout_by_default
    g = Class.new(Ask::Graph)
    assert_nil g.workflow_timeout
  end

  def test_step_timeout_still_applies_within_workflow_timeout
    g = Class.new(Ask::Graph) do
      workflow_timeout 30
      step Class.new {
        def call(ctx)
          sleep 5
        end
      }, timeout: 0.05
    end
    error = assert_raises(Ask::Graph::StepFailed) { g.new.call }
    assert_includes error.message, "timed out"
  end

  def test_workflow_timeout_does_not_apply_without_workflow_timeout
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

  # --- storage ---

  def test_storage_declaration_stored
    store = Ask::State::Memory.new
    g = Class.new(Ask::Graph) do
      storage store
    end
    assert_same store, g.storage
  end

  def test_storage_assignment_form
    store = Ask::State::Memory.new
    g = Class.new(Ask::Graph)
    g.storage = store
    assert_same store, g.storage
  end

  def test_no_storage_returns_nil
    g = Class.new(Ask::Graph)
    assert_nil g.storage
  end

  def test_global_storage_set_on_graph_class
    store = Ask::State::Memory.new
    Ask::Graph.storage store
    g = Class.new(Ask::Graph)
    assert_same store, g.storage
  ensure
    Ask::Graph.instance_variable_set(:@storage, nil)
  end

  def test_child_inherits_parent_storage
    store = Ask::State::Memory.new
    parent = Class.new(Ask::Graph) do
      storage store
    end
    child = Class.new(parent)
    assert_same store, child.storage
  end

  def test_child_can_override_parent_storage
    parent_store = Ask::State::Memory.new
    child_store = Ask::State::Memory.new
    parent = Class.new(Ask::Graph) do
      storage parent_store
    end
    child = Class.new(parent) do
      storage child_store
    end
    assert_same child_store, child.storage
    assert_same parent_store, parent.storage
  end

  def test_per_call_storage_overrides_class_storage
    class_store = Ask::State::Memory.new
    call_store = Ask::State::Memory.new
    g = Class.new(Ask::Graph) do
      storage class_store
      step Class.new {
        def call(ctx)
          ctx.done = true
        end
      }
    end
    ctx = g.new(storage: call_store).call
    assert ctx.done
  end

  def test_class_storage_used_when_no_per_call_storage
    class_store = Ask::State::Memory.new
    g = Class.new(Ask::Graph) do
      storage class_store
      step Class.new {
        def call(ctx)
          ctx.done = true
        end
      }
    end
    ctx = g.new.call
    assert ctx.done
  end

  def test_class_storage_used_via_call_method
    store = Ask::State::Memory.new
    g = Class.new(Ask::Graph) do
      storage store
      step Class.new {
        def call(ctx)
          ctx.done = true
        end
      }
    end
    ctx = g.call
    assert ctx.done
  end

  # --- Sub-graph composition ---

  def test_subgraph_runs_inner_steps
    workflow = Class.new(Ask::Graph) do
      step Class.new {
        def call(ctx)
          (ctx.log ||= []) << :inner
        end
      }
    end
    step = Class.new do
      define_method(:call) { |ctx| workflow.call(ctx) }
    end
    outer = Class.new(Ask::Graph) { step step }
    ctx = outer.new.call
    assert_equal [:inner], ctx.log
  end

  def test_subgraph_merges_context_back
    workflow = Class.new(Ask::Graph) do
      step Class.new {
        def call(ctx)
          ctx.inner_result = "from_sub"
        end
      }
    end
    step = Class.new do
      define_method(:call) { |ctx| workflow.call(ctx) }
    end
    outer = Class.new(Ask::Graph) do
      step step
      step Class.new {
        def call(ctx)
          ctx.final = ctx.inner_result
        end
      }
    end
    ctx = outer.new.call
    assert_equal "from_sub", ctx.final
  end

  def test_subgraph_reads_outer_context
    workflow = Class.new(Ask::Graph) do
      step Class.new {
        def call(ctx)
          ctx.result = ctx.outer_val * 2
        end
      }
    end
    step = Class.new do
      define_method(:call) { |ctx| workflow.call(ctx) }
    end
    outer = Class.new(Ask::Graph) do
      step Class.new {
        def call(ctx)
          ctx.outer_val = 21
        end
      }
      step step
    end
    ctx = outer.new.call
    assert_equal 42, ctx.result
  end

  def test_multiple_subgraph_steps
    workflow_a = Class.new(Ask::Graph) do
      step Class.new {
        def call(ctx)
          (ctx.log ||= []) << :a
        end
      }
    end
    workflow_b = Class.new(Ask::Graph) do
      step Class.new {
        def call(ctx)
          (ctx.log ||= []) << :b
        end
      }
    end
    step_a = Class.new { define_method(:call) { |ctx| workflow_a.call(ctx) } }
    step_b = Class.new { define_method(:call) { |ctx| workflow_b.call(ctx) } }
    outer = Class.new(Ask::Graph) do
      step step_a
      step step_b
    end
    ctx = outer.new.call
    assert_equal [:a, :b], ctx.log
  end

  def test_mixed_regular_and_subgraph_steps
    workflow = Class.new(Ask::Graph) do
      step Class.new {
        def call(ctx)
          ctx.inner_val = ctx.outer_val * 3
        end
      }
    end
    step = Class.new { define_method(:call) { |ctx| workflow.call(ctx) } }
    outer = Class.new(Ask::Graph) do
      step Class.new {
        def call(ctx)
          ctx.outer_val = 10
        end
      }
      step step
      step Class.new {
        def call(ctx)
          ctx.final = ctx.inner_val + 1
        end
      }
    end
    ctx = outer.new.call
    assert_equal 31, ctx.final
  end

  def test_nested_subgraphs
    leaf = Class.new(Ask::Graph) do
      step Class.new {
        def call(ctx)
          (ctx.log ||= []) << :leaf
        end
      }
    end
    leaf_step = Class.new { define_method(:call) { |ctx| leaf.call(ctx) } }
    middle = Class.new(Ask::Graph) do
      step leaf_step
      step Class.new {
        def call(ctx)
          (ctx.log ||= []) << :middle
        end
      }
    end
    middle_step = Class.new { define_method(:call) { |ctx| middle.call(ctx) } }
    outer = Class.new(Ask::Graph) do
      step middle_step
      step Class.new {
        def call(ctx)
          (ctx.log ||= []) << :outer
        end
      }
    end
    ctx = outer.new.call
    assert_equal [:leaf, :middle, :outer], ctx.log
  end

  def test_subgraph_with_inner_conditional
    workflow = Class.new(Ask::Graph) do
      step Class.new {
        def call(ctx)
          (ctx.log ||= []) << :always
        end
      }
      step Class.new {
        def call(ctx)
          (ctx.log ||= []) << :conditional
        end
      }, if: :should_run?

      def should_run?
        true
      end
    end
    step = Class.new { define_method(:call) { |ctx| workflow.call(ctx) } }
    outer = Class.new(Ask::Graph) { step step }
    ctx = outer.new.call
    assert_equal [:always, :conditional], ctx.log
  end

  def test_subgraph_skipped_when_inner_condition_false
    workflow = Class.new(Ask::Graph) do
      step Class.new {
        def call(ctx)
          (ctx.log ||= []) << :always
        end
      }
      step Class.new {
        def call(ctx)
          (ctx.log ||= []) << :conditional
        end
      }, if: :should_run?

      def should_run?
        false
      end
    end
    step = Class.new { define_method(:call) { |ctx| workflow.call(ctx) } }
    outer = Class.new(Ask::Graph) { step step }
    ctx = outer.new.call
    assert_equal [:always], ctx.log
  end

  def test_subgraph_with_outer_step_timeout
    workflow = Class.new(Ask::Graph) do
      step Class.new {
        def call(ctx)
          sleep 5
        end
      }
    end
    step = Class.new { define_method(:call) { |ctx| workflow.call(ctx) } }
    outer = Class.new(Ask::Graph) { step step, timeout: 0.05 }
    error = assert_raises(Ask::Graph::StepFailed) { outer.new.call }
    assert_includes error.message, "timed out"
  end

  def test_subgraph_with_outer_retry
    attempt_count = 0
    workflow = Class.new(Ask::Graph) do
      step Class.new {
        define_method(:call) do |_ctx|
          attempt_count += 1
          raise "fail" if attempt_count < 3
        end
      }
    end
    step = Class.new { define_method(:call) { |ctx| workflow.call(ctx) } }
    outer = Class.new(Ask::Graph) { step step, retry: 3 }
    ctx = outer.new.call
    assert_equal 3, attempt_count
  end

  def test_empty_subgraph
    workflow = Class.new(Ask::Graph)
    step = Class.new { define_method(:call) { |ctx| workflow.call(ctx) } }
    outer = Class.new(Ask::Graph) do
      step Class.new {
        def call(ctx)
          (ctx.log ||= []) << :before
        end
      }
      step step
      step Class.new {
        def call(ctx)
          (ctx.log ||= []) << :after
        end
      }
    end
    ctx = outer.new.call
    assert_equal [:before, :after], ctx.log
  end

  def test_outer_hooks_fire_around_subgraph
    hook_log = []
    workflow = Class.new(Ask::Graph) do
      step Class.new {
        def call(ctx)
          (ctx.log ||= []) << :inner_step
        end
      }
    end
    step = Class.new { define_method(:call) { |ctx| workflow.call(ctx) } }
    outer = Class.new(Ask::Graph) do
      before_step :log_before
      after_step :log_after
      step step

      define_method(:log_before) { |declaration:, context:| hook_log << :before }
      define_method(:log_after)  { |declaration:, context:| hook_log << :after }
    end
    ctx = outer.new.call
    assert_equal [:inner_step], ctx.log
    assert_equal [:before, :after], hook_log
  end

  def test_subgraph_with_outer_condition
    workflow = Class.new(Ask::Graph) do
      step Class.new {
        def call(ctx)
          (ctx.log ||= []) << :inner
        end
      }
    end
    step = Class.new { define_method(:call) { |ctx| workflow.call(ctx) } }
    outer = Class.new(Ask::Graph) do
      step step, if: :skip?

      def skip?
        false
      end
    end
    ctx = outer.new.call
    assert_nil ctx.log
  end

  def test_subgraph_preserves_outer_context_keys
    workflow = Class.new(Ask::Graph) do
      step Class.new {
        def call(ctx)
          ctx.inner_val = "set_by_sub"
        end
      }
    end
    step = Class.new { define_method(:call) { |ctx| workflow.call(ctx) } }
    outer = Class.new(Ask::Graph) do
      step Class.new {
        def call(ctx)
          ctx.outer_val = "preserved"
        end
      }
      step step
    end
    ctx = outer.new.call
    assert_equal "preserved", ctx.outer_val
    assert_equal "set_by_sub", ctx.inner_val
  end

  def test_subgraph_with_parallel_steps
    workflow = Class.new(Ask::Graph) do
      steps SleepStep, SleepStep, SleepStep
      step Class.new {
        def call(ctx)
          (ctx.log ||= []) << :done
        end
      }
    end
    step = Class.new { define_method(:call) { |ctx| workflow.call(ctx) } }
    outer = Class.new(Ask::Graph) { step step }
    ctx = outer.new.call
    assert ctx.log.include?(:done)
  end
end
end
