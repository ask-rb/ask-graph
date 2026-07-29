# frozen_string_literal: true

require_relative "graph/version"
require_relative "graph/context"
require_relative "graph/runner"

module Ask
  # Define durable workflow graphs with named steps, conditional routing,
  # parallel execution, human-in-the-loop approval, per-item checkpointing
  # loops, step timeouts, retry policies, and lifecycle hooks.
  #
  # @example Basic workflow
  #   class HandleCall < Ask::Graph
  #     step Transcribe
  #     step Classify, if: :needs_classification?
  #     step BookAppointment
  #   end
  #
  # @example With timeout and retry
  #   class ApiWorkflow < Ask::Graph
  #     step FetchData, timeout: 30, retry: 3
  #     step ProcessData, description: "Transform raw data into reports"
  #   end
  #
  # @example With lifecycle hooks
  #   class MonitoredWorkflow < Ask::Graph
  #     before_step :log_start
  #     after_step  :log_completion
  #     on_failure  :alert_team
  #
  #     step ValidateOrder
  #     step ProcessPayment, timeout: 15, retry: 2
  #   end
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
        subclass.instance_variable_set(:@lifecycle_hooks, lifecycle_hooks.dup)
      end

      # --- Lifecycle hooks ---

      def lifecycle_hooks
        @lifecycle_hooks ||= { before_step: [], after_step: [], on_failure: [] }
      end

      # Register a callback to run before every step.
      # @param method_name [Symbol] method name on the graph class
      def before_step(method_name)
        lifecycle_hooks[:before_step] << method_name
      end

      # Register a callback to run after every successful step.
      # @param method_name [Symbol] method name on the graph class
      def after_step(method_name)
        lifecycle_hooks[:after_step] << method_name
      end

      # Register a callback to run when a step fails.
      # @param method_name [Symbol] method name on the graph class
      def on_failure(method_name)
        lifecycle_hooks[:on_failure] << method_name
      end

      # --- Step declarations ---

      # Declare a sequential step.
      #
      # @param klass [Class] a class that responds to +#call(context)+
      # @param conditions [Hash] optional +if:+ or +unless:+ condition method name,
      #   +description:+ human-readable label, +timeout:+ seconds,
      #   +retry:+ number of retries on failure
      def step(klass, **opts)
        declarations << build_declaration(:step, klass, opts)
      end

      # Declare parallel steps — all run simultaneously.
      #
      # @param klasses [Array<Class>] step classes to run in parallel
      # @param opts [Hash] optional +if:+, +unless:+, +timeout:+ seconds,
      #   +retry:+ number of retries
      def steps(*klasses, **opts)
        declarations << {
          classes: klasses,
          type: :steps,
          name: klasses.map { |k| k.name || k.to_s }.join(", "),
          if: opts[:if],
          unless: opts[:unless],
          description: opts[:description],
          timeout: opts[:timeout],
          retry: opts[:retry]
        }
      end

      # Declare a human-in-the-loop step. Runs the step, then pauses
      # and waits for external input via {Ask::Graph#resume}.
      #
      # @param klass [Class] a class that responds to +#call(context)+
      # @param opts [Hash] optional +if:+, +unless:+, +description:+,
      #   +timeout:+, +retry:+
      def approve(klass, **opts)
        declarations << build_declaration(:approve, klass, opts)
      end

      # Convenience: create instance and call.
      def call(input = nil, checkpoint_store: nil)
        new(input, checkpoint_store: checkpoint_store).call
      end
      alias run call

      private

      def build_declaration(type, klass, opts)
        {
          class: klass,
          type: type,
          name: klass.name || klass.to_s,
          if: opts[:if],
          unless: opts[:unless],
          description: opts[:description],
          timeout: opts[:timeout],
          retry: opts[:retry]
        }
      end
    end

    def initialize(input = nil, checkpoint_store: nil)
      @input = input
      store = checkpoint_store || Ask::State::Memory.new
      hooks = self.class.lifecycle_hooks
      @runner = Runner.new(self.class.declarations,
                           checkpoint_store: store,
                           hooks: hooks,
                           graph_instance: self)
      @context = nil
    end

    attr_reader :runner
    attr_reader :context

    def call
      @context = Context.new(self, @input)
      @runner.run(@context)
      @context
    rescue => e
      raise unless e.is_a?(Paused)
      @context
    end
    alias run call

    def resume(input:)
      @context.resume_input = input.to_s
      @runner.run(@context)
      @context
    end
  end
end
