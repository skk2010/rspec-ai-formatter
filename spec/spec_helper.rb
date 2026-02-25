# frozen_string_literal: true

require 'bundler/setup'
require 'stringio'
require 'rspec/ai_formatter'
require 'json'
require 'fileutils'
require 'tempfile'

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
