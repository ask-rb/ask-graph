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
  # @example With parallel steps
  #   class SyncData < Ask::Graph
  #     step FetchRecords
  #
  #     steps CrmUpdate, CalendarSync, SendNotification
  #
  #     step ConfirmResponse
  #   end
  #
  # @example With human-in-the-loop
  #   class ProcessBooking < Ask::Graph
  #     step BookAppointment
  #     approve ReviewBooking, if: :expensive?
  #     step ConfirmBooking
  #   end
  #
  # @example With per-item looping
  #   class SendReminders < Ask::Graph
  #     step FetchAppointments
  #     step RemindEach   # calls context.each(:appointments) internally
  #     step MarkComplete
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

      # Create a new instance and run the graph.
      # @param input [Object] optional initial input
      # @param checkpoint_store [#set, #get, #delete] optional persistent store
      # @return [Ask::Graph::Context] the completed context
      def run(input = nil, checkpoint_store: nil)
        new(checkpoint_store: checkpoint_store).run(input)
      end

      # Resume a paused graph with human input.
      # @param input [Object] the human's input
      # @param checkpoint_store [#set, #get, #delete] the same store used for the original run
      # @return [Ask::Graph::Context] the completed context
      def resume(input:, checkpoint_store:)
        new(checkpoint_store: checkpoint_store).resume(input: input)
      end
    end

    # @param checkpoint_store [#set, #get, #delete, nil] optional persistent store
    def initialize(checkpoint_store: nil)
      @runner = Runner.new(self.class.declarations, checkpoint_store: checkpoint_store)
      @context = nil
    end

    # @return [Ask::Graph::Runner] the runner (exposed for checkpoint coordination)
    attr_reader :runner

    # @return [Ask::Graph::Context, nil] the shared context
    attr_reader :context

    # Run the graph with the given input.
    # @param input [Object] optional initial input
    # @return [Ask::Graph::Context] the completed context
    def run(input = nil)
      @context = Context.new(self, input)
      @runner.run(@context)
      @context
    rescue => e
      raise unless e.class.name&.end_with?("Paused")
      @context
    end

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
