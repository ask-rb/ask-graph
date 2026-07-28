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
        @store[:input] = input if input
      end

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

      # @return [Hash] serializable snapshot of the context state
      def to_h
        @mutex.synchronize do
          serializable = {}
          @store.each do |k, v|
            serializable[k] = v.respond_to?(:to_h) ? v.to_h : v
          end
          serializable
        end
      end
    end
  end
end
