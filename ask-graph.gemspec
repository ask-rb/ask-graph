require_relative "lib/ask/graph/version"

Gem::Specification.new do |spec|
  spec.name = "ask-graph"
  spec.version = Ask::Graph::VERSION
  spec.authors = ["Kaka Ruto"]
  spec.email = ["kaka@myrrlabs.com"]

  spec.summary = "Durable workflow graphs for the ask-rb ecosystem"
  spec.description = "Define workflows as graphs of named steps with conditional routing, parallel execution, human-in-the-loop approval, per-item checkpointing loops, and sub-graph composition. Each step is a plain Ruby class."

  spec.homepage = "https://github.com/ask-rb/ask-graph"
  spec.license = "MIT"

  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/master/CHANGELOG.md"

  spec.files = Dir["lib/**/*", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "ask-core", ">= 0.6"

  spec.add_development_dependency "minitest", "~> 5.25"
  spec.add_development_dependency "mocha", "~> 3.1"
  spec.add_development_dependency "rake", "~> 13.0"
end
