# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ask-graph"

require "minitest/autorun"
require "mocha/minitest"

module TestHelpers
  # A step that records its execution in a global log for test assertions.
  class LogStep
    @@log = []

    def self.log
      @@log
    end

    def self.clear_log
      @@log = []
    end
  end

  # Simple in-memory checkpoint store for testing.
  class MemoryStore
    def initialize
      @data = {}
    end

    def get(key)
      @data[key]
    end

    def set(key, value)
      @data[key] = value
    end

    def delete(key)
      @data.delete(key)
    end
  end
end
