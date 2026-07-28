# frozen_string_literal: true

require_relative "graph/version"
require_relative "graph/context"
require_relative "graph/runner"

module Ask
  # Define durable workflow graphs with named steps, conditional routing,
  # parallel execution, human-in-the-loop approval, and per-item
  # checkpointing loops.
  #
  # @example Basic workflow
  #   class HandleCall < Ask::Graph
  #     step Transcribe
  #     step Classify, if: :needs_classification?
  #     step BookAppointment
  #   end
  #
  #   result = HandleCall.new.call(recording: "call.wav")
  #
  # @example With checkpointing
  #   store = Ask::State::Memory.new
  #   result = HandleCall.new.call(input, checkpoint_store: store)
  #
  class Graph
    class << self
      # All step declarations collected across the class hierarchy.
      def declarations
        @declarations ||= []
      end

      # Inherited hook — copies declarations to subclasses.
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@declarations, declarations.dup)
      end

      # Declare a sequential step.
      #
      # @param klass [Class] a class that responds to +#call(context)+
      # @param conditions [Hash] optional +if:+ or +unless:+ condition method name
      def step(klass, **conditions)
        declarations << {
          class: klass,
          type: :step,
          name: klass.name || klass.to_s,
          if: conditions[:if],
          unless: conditions[:unless]
        }
      end

      # Declare parallel steps — all run simultaneously.
      #
      # @param klasses [Array<Class>] step classes to run in parallel
      # @param conditions [Hash] optional +if:+ or +unless:+ condition method name
      def steps(*klasses, **conditions)
        declarations << {
          classes: klasses,
          type: :steps,
          name: klasses.map { |k| k.name || k.to_s }.join(", "),
          if: conditions[:if],
          unless: conditions[:unless]
        }
      end

      # Declare a human-in-the-loop step. Runs the step, then pauses
      # and waits for external input via {Ask::Graph#resume}.
      #
      # @param klass [Class] a class that responds to +#call(context)+
      # @param conditions [Hash] optional +if:+ or +unless:+ condition method name
      def approve(klass, **conditions)
        declarations << {
          class: klass,
          type: :approve,
          name: klass.name || klass.to_s,
          if: conditions[:if],
          unless: conditions[:unless]
        }
      end

      # Convenience: create instance and call.
      # @param input [Object] optional input
      # @param checkpoint_store [#set, #get, #delete] optional persistent store
      # @return [Ask::Graph::Context] the completed context
      def call(input = nil, checkpoint_store: nil)
        new(input, checkpoint_store: checkpoint_store).call
      end
      alias run call
    end

    # @param input [Object, nil] initial input for the graph execution
    # @param checkpoint_store [#set, #get, #delete, nil] optional persistent store.
    #   Defaults to in-memory store. Pass a persistent store for crash recovery.
    def initialize(input = nil, checkpoint_store: nil)
      @input = input
      store = checkpoint_store || Ask::State::Memory.new
      @runner = Runner.new(self.class.declarations, checkpoint_store: store)
      @context = nil
    end

    # @return [Ask::Graph::Runner] the runner (exposed for checkpoint coordination)
    attr_reader :runner

    # @return [Ask::Graph::Context, nil] the shared context
    attr_reader :context

    # Execute the graph.
    # @return [Ask::Graph::Context] the completed context
    def call
      @context = Context.new(self, @input)
      @runner.run(@context)
      @context
    rescue => e
      raise unless e.is_a?(Paused)
      @context
    end
    alias run call

    # Resume a paused graph with human input.
    # @param input [Object] the human's input
    # @return [Ask::Graph::Context] the completed context
    def resume(input:)
      @context.resume_input = input.to_s
      @runner.run(@context)
      @context
    end
  end
end
