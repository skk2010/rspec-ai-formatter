# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = 'rspec-ai-formatter'
  spec.version = '0.3.0'
  spec.authors = ['SK']
  spec.email = ['konstantin.suhov@gmail.com']

  spec.summary = 'AI-friendly RSpec formatter with minimal token usage'
  spec.description = <<~DESC
    RSpec formatter optimized for AI agents and CI systems.
    Outputs compact NDJSON with file references instead of verbose text.
    Supports log splitting, error deduplication, and context-efficient reporting.
  DESC

  spec.homepage = 'https://github.com/skk2010/rspec-ai-formatter'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.0.0'

  spec.metadata['allowed_push_host'] = 'https://rubygems.org'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir[
    'lib/**/*',
    'LICENSE',
    'README.md'
  ]

  spec.bindir = 'bin'
  spec.executables = %w[rspec-ai rspec-ai-merge]
  spec.require_paths = ['lib']
  spec.autorequire = 'rspec_ai_formatter'

  spec.add_dependency 'rspec-core', '>= 3.10'
end
