# frozen_string_literal: true

module Ask
  class Graph
    # Shared state that flows through every step of a graph execution.
    #
    # Stores input, output, and intermediate data produced by steps.
    # Accessed by step classes via +context.data_key+ or +context[:data_key]+.
    # Thread-safe by design — each context is scoped to one graph run.
    #
    # @example
    #   class MyStep
    #     def call(context)
    #       context.transcript = "Hello"
    #       context[:classification] = "booking"
    #     end
    #   end
    #
    class Context
      # @return [Ask::Graph] the graph this context belongs to
      attr_reader :graph

      # @return [Object, nil] the current item when iterating via {#each}
      attr_reader :item

      def initialize(graph, input = nil)
        @graph = graph
        @store = {}
        @each_index = nil
        @each_items = nil
        @item = nil
        @mutex = Mutex.new
        @resume_input = nil
        if input.is_a?(Hash)
          @store[:input] = input
          @store.merge!(input)
        elsif input
          @store[:input] = input
        end
      end

      # @return [Object, nil] input provided on resume for approval steps
      attr_accessor :resume_input

      # Access a stored value by method name.
      def method_missing(name, *args, &block)
        if name.to_s.end_with?("=")
          key = name.to_s.chomp("=").to_sym
          @mutex.synchronize { @store[key] = args.first }
        elsif args.empty? && !block
          @mutex.synchronize { @store[name] }
        else
          super
        end
      end

      def respond_to_missing?(name, include_private = false)
        clean = name.to_s.sub(/=$/, "").to_sym
        @store.key?(clean) || super
      end

      # Access a stored value by key.
      # @param key [Symbol] the key
      # @return [Object, nil]
      def [](key)
        @mutex.synchronize { @store[key.to_sym] }
      end

      # Store a value by key.
      # @param key [Symbol] the key
      # @param value [Object] the value
      def []=(key, value)
        @mutex.synchronize { @store[key.to_sym] = value }
      end

      # Iterate over items with per-item checkpointing.
      #
      # Each iteration is checkpointed so that if the process crashes,
      # it resumes from the last completed item rather than starting over.
      #
      # @param items [Array] the items to iterate over
      # @yield [item] called once per item
      # @yieldparam item [Object] the current item
      def each(items, &block)
        @each_index = graph.runner.resume_index_for(items) || 0
        @each_items = items

        items.each_with_index do |item, idx|
          break if idx < @each_index

          @item = item
          block.call(item)
          graph.runner.checkpoint_each!(idx)
        end
      ensure
        @each_index = nil
        @each_items = nil
        @item = nil
      end

      # @return [Hash] serializable snapshot of the context state.
      # All keys and values are converted to JSON-safe types (string keys,
      # symbols converted to strings, arrays recursed).
      def to_h
        @mutex.synchronize do
          deep_json_safe(@store)
        end
      end

      # @return [Hash] raw store data with original object references.
      # Unlike {to_h}, this returns the actual Ruby objects without
      # serialization. Useful for passing state to sub-graphs.
      def export_data
        @mutex.synchronize { @store.dup }
      end

      # Merge data from another context (or hash) into this one.
      # Existing keys in this context are overwritten.
      #
      # @param other [Context, Hash] source of data to merge in
      def import(other)
        data = other.is_a?(Context) ? other.export_data : other
        @mutex.synchronize { @store.merge!(data) }
      end

      # Run an {Ask::Graph} as a sub-graph, merging its context back.
      #
      # Exports the current context data, creates the sub-graph with it,
      # runs it, and merges any results back into this context.
      #
      # @param graph_class [Class < Ask::Graph] the graph to run
      # @return [Ask::Graph::Context] the sub-graph's context
      # @example
      #   # Inside a step PORO
      #   class CalculateShipping
      #     def call(context)
      #       context.run(Shipping::Workflow)
      #     end
      #   end
      def run(graph_class)
        sub = graph_class.new(export_data)
        sub_ctx = sub.call
        import(sub_ctx)
        sub_ctx
      end

      private

      # Recursively convert a value to a JSON-safe structure.
      def deep_json_safe(value)
        case value
        when Hash
          value.each_with_object({}) { |(k, v), h| h[k.to_s] = deep_json_safe(v) }
        when Array
          value.map { |v| deep_json_safe(v) }
        when Symbol
          value.to_s
        when String, Numeric, true, false, nil
          value
        else
          value.respond_to?(:to_h) ? deep_json_safe(value.to_h) : value.to_s
        end
      end
    end
  end
end
