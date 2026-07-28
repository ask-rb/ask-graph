# frozen_string_literal: true

require_relative "test_helper"

describe "ask-graph gemspec" do
  it "has a version" do
    assert Ask::Graph::VERSION
  end

  it "has a valid gemspec" do
    spec = Gem::Specification.load("ask-graph.gemspec")
    assert spec
    assert_equal "ask-graph", spec.name
    assert spec.summary
    assert spec.description
    assert spec.authors.include?("Kaka Ruto")
  end
end
