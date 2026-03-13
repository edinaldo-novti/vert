# frozen_string_literal: true

require_relative "lib/vert/version"

Gem::Specification.new do |spec|
  spec.name = "vert-core"
  spec.version = Vert::VERSION
  spec.authors = ["Vert Team"]
  spec.email = ["dev@vert.dev"]

  spec.summary = "Generic core library for Rails microservices"
  spec.description = "Optional patterns for Rails apps: multi-tenancy, RLS, outbox, health checks, auditing, soft delete, UUID primary keys, and document storage client. All features are configurable via initializer."
  spec.homepage = "https://github.com/edinaldo-novti/vert"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(__dir__) do
    Dir.glob("**/*").reject do |f|
      File.directory?(f) ||
        (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport", ">= 7.0"
  spec.add_dependency "activerecord", ">= 7.0"
  spec.add_dependency "discard", "~> 1.3"
  spec.add_dependency "bunny", "~> 2.22"
  spec.add_dependency "sidekiq", ">= 7.0"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.21"
  spec.add_development_dependency "rubocop-rails", "~> 2.0"
  spec.add_development_dependency "rubocop-rspec", "~> 2.0"
end
