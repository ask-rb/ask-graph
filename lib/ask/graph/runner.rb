# frozen_string_literal: true

require "json"

module Ask
  class Graph
    # Error raised when a step fails.
    class StepFailed < StandardError; end

    # Error raised when a step pauses for human approval.
    class Paused < StandardError; end

    # Executes the declared steps of a graph, managing checkpointing,
    # condition evaluation, parallel execution, and human-in-the-loop pauses.
    #
    # Checkpoints save the full context state after each step so that
    # crashes resume from the last completed step with all data intact.
    # Uses an in-memory store by default; pass a persistent store for
    # crash recovery across restarts.
    class Runner
      # @return [Array<Hash>] step declarations with name, type, condition
      attr_reader :declarations

      # @return [#set, #get, #delete] the checkpoint store
      attr_reader :store

      # @param declarations [Array<Hash>] step declarations
      # @param checkpoint_store [#set, #get, #delete] key-value store.
      #   Defaults to in-memory (no durability across restarts).
      def initialize(declarations, checkpoint_store: nil)
        @declarations = declarations
        @store = checkpoint_store
        @completed_steps = []
      end

      # Run the graph from the beginning or resume from the last checkpoint.
      # @param context [Ask::Graph::Context] the shared context
      # @return [Ask::Graph::Context] the completed context
      def run(context)
        resume_index = load_checkpoint(context)

        @declarations.each_with_index do |decl, idx|
          next if resume_index && idx <= resume_index

          unless condition_met?(decl, context)
            record_completion(idx, :skipped)
            next
          end

          execute_step(decl, context)
          record_completion(idx, :completed)
          save_checkpoint(context, idx)
        end

        context
      end

      # Resume a paused graph with human input.
      # @param context [Ask::Graph::Context] the context at pause point
      # @param input [Object] the human's input
      # @return [Ask::Graph::Context] the completed context
      def resume(context, input:)
        context.resume_input = input
        run(context)
      end

      # Get the index to resume from for an {Context#each} iteration.
      # @param items [Array] the full list of items
      # @return [Integer, nil] the index to resume from, or nil
      def resume_index_for(items)
        key = each_checkpoint_key
        raw = @store.get(key)
        raw ? raw.to_i : nil
      end

      # Checkpoint after a single iteration of {Context#each}.
      # @param index [Integer] the completed iteration index
      def checkpoint_each!(index)
        key = each_checkpoint_key
        @store.set(key, index.to_s)
      end

      private

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
      rescue StandardError => e
        raise StepFailed, "#{klass.name} failed: #{e.message}"
      end

      def run_parallel(classes, _name, context)
        threads = classes.map do |klass|
          Thread.new do
            begin
              instance = klass.new
              instance.call(context)
            rescue StandardError => e
              raise StepFailed, "#{klass.name} failed: #{e.message}"
            end
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

      # Save checkpoint with full context state so resumed graphs
      # have access to all data produced by completed steps.
      def save_checkpoint(context, idx)
        data = {
          completed_index: idx,
          context: context.to_h,
          timestamp: Time.now.iso8601
        }
        @store.set(checkpoint_key, JSON.generate(data))
      end

      # Load checkpoint and restore context state if available.
      # Returns the completed_index to skip, or nil for a fresh run.
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
