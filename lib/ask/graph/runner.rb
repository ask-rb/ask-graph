# frozen_string_literal: true

require "json"
require "timeout"

module Ask
  class Graph
    # Error raised when a step fails.
    class StepFailed < StandardError; end

    # Error raised when a step times out.
    class StepTimeout < StandardError; end

    # Error raised when a step pauses for human approval.
    class Paused < StandardError; end

    # Executes the declared steps of a graph, managing checkpointing,
    # condition evaluation, parallel execution, timeouts, retries,
    # lifecycle hooks, and human-in-the-loop pauses.
    class Runner
      attr_reader :declarations, :store

      # @param declarations [Array<Hash>] step declarations
      # @param checkpoint_store [#set, #get, #delete] key-value store
      # @param hooks [Hash] lifecycle hook method names
      # @param graph_instance [Object] the graph instance (for hooks)
      # @param default_timeout [Integer, nil] fallback timeout for steps with no explicit timeout
      def initialize(declarations, checkpoint_store: nil,
                     hooks: { before_step: [], after_step: [], on_failure: [] },
                     graph_instance: nil,
                     default_timeout: nil)
        @declarations = declarations
        @store = checkpoint_store
        @hooks = hooks
        @graph = graph_instance
        @default_timeout = default_timeout
        @completed_steps = []
      end

      def run(context)
        resume_index = load_checkpoint(context)

        @declarations.each_with_index do |decl, idx|
          next if resume_index && idx <= resume_index

          unless condition_met?(decl, context)
            record_completion(idx, :skipped)
            next
          end

          run_hooks(:before_step, decl, context)
          execute_with_retry(decl, context)
          run_hooks(:after_step, decl, context)

          record_completion(idx, :completed)
          save_checkpoint(context, idx)
        end

        context
      end

      def resume(context, input:)
        context.resume_input = input
        run(context)
      end

      def resume_index_for(items)
        key = each_checkpoint_key
        raw = @store.get(key)
        raw ? raw.to_i : nil
      end

      def checkpoint_each!(index)
        key = each_checkpoint_key
        @store.set(key, index.to_s)
      end

      private

      def execute_with_retry(decl, context)
        retries = decl[:retry] || 0

        (retries + 1).times do |attempt|
          begin
            run_with_timeout(decl, context, decl[:timeout])
            return
          rescue StepFailed => e
            run_hooks(:on_failure, decl, context, error: e)
            raise if attempt >= retries
            sleep backoff_seconds(attempt, decl[:backoff])
          end
        end
      end

      def run_with_timeout(decl, context, timeout_value)
        timeout_value ||= @default_timeout
        if timeout_value
          ::Timeout.timeout(timeout_value) { execute_step(decl, context) }
        else
          execute_step(decl, context)
        end
      rescue ::Timeout::Error
        raise StepFailed, "#{decl[:name]} timed out after #{timeout_value}s"
      end

      def backoff_seconds(attempt, strategy)
        return 0 if attempt == 0
        case strategy
        when :exponential then 2 ** attempt
        when :constant then 2
        else 2 ** attempt
        end
      end

      def run_hooks(hook_type, decl, context, error: nil)
        @hooks[hook_type]&.each do |method_name|
          next unless @graph&.respond_to?(method_name, true)
          args = { declaration: decl, context: context }
          args[:error] = error if error
          @graph.send(method_name, **args)
        end
      end

      def execute_step(decl, context)
        case decl[:type]
        when :step
          run_single(decl[:class], decl[:name], context)
        when :steps
          run_parallel(decl[:classes], decl[:name], context)
        when :approve
          run_approve(decl[:class], decl[:name], context)
        end
      end

      def run_single(klass, _name, context)
        instance = klass.new
        instance.call(context)
      rescue Paused
        raise
      rescue => e
        raise StepFailed, "#{klass.name} failed: #{e.message}"
      end

      def run_parallel(classes, _name, context)
        threads = classes.map do |klass|
          Thread.new do
            instance = klass.new
            instance.call(context)
          rescue => e
            raise StepFailed, "#{klass.name} failed: #{e.message}"
          end
        end
        threads.each(&:join)
      end

      def run_approve(klass, _name, context)
        instance = klass.new
        instance.call(context)
        save_checkpoint(context, current_index)
        raise Paused, "Graph paused for approval after #{klass.name}"
      end

      def condition_met?(decl, context)
        if decl[:if]
          context.graph.send(decl[:if])
        elsif decl[:unless]
          !context.graph.send(decl[:unless])
        else
          true
        end
      end

      def record_completion(idx, status)
        @completed_steps << { index: idx, status: status }
      end

      # --- Checkpointing ---

      RUN_KEY = "ask:graph:run:%s"

      def checkpoint_key
        RUN_KEY % @declarations.object_id.to_s
      end

      def each_checkpoint_key
        "#{checkpoint_key}:each"
      end

      def save_checkpoint(context, idx)
        data = {
          completed_index: idx,
          context: context.to_h,
          timestamp: Time.now.iso8601
        }
        @store.set(checkpoint_key, JSON.generate(data))
      end

      def load_checkpoint(context)
        raw = @store.get(checkpoint_key)
        return nil unless raw

        data = JSON.parse(raw)
        restored = data["context"]
        if restored.is_a?(Hash)
          restored.each { |k, v| context[k.to_sym] = v }
        end
        data["completed_index"]
      end

      def current_index
        @completed_steps.size
      end
    end
  end
end
