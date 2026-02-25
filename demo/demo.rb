#!/usr/bin/env ruby
# frozen_string_literal: true

# Demo script to show AI formatter output
# Run: ruby demo/demo.rb

require 'bundler/setup'
require 'rspec/ai_formatter'
require 'fileutils'

# Create temporary test file
test_content = <<~RUBY
  RSpec.describe 'User' do
    describe '#valid?' do
      it 'passes with valid email' do
        expect(true).to be true
      end

      it 'fails with invalid email' do
        expect(false).to be true
      end

      it 'is pending', skip: 'not implemented' do
        expect(true).to be false
      end
    end

    describe '#save' do
      it 'saves to database' do
        expect(true).to be true
      end
    end
  end
RUBY

Dir.mktmpdir do |dir|
  test_file = File.join(dir, 'user_spec.rb')
  File.write(test_file, test_content)

  log_dir = File.join(dir, 'logs')
  FileUtils.mkdir_p(log_dir)

  puts '=' * 80
  puts 'AI FORMATTER OUTPUT:'
  puts '=' * 80
  puts

  output = StringIO.new
  formatter = RSpec::AiFormatter::Formatter.new(output, log_dir: log_dir)

  # Mock RSpec run
  RSpec::Core::World.new.tap do |world|
    # Load example group
    world.register_matching_example_groups_from(files_or_directories_to_run: [test_file])

    # Get examples
    examples = world.ordered_example_groups.flat_map(&:examples)

    # Simulate run
    formatter.start(double(loaded_specs: [test_file], count: examples.length, estimated_duration: nil))

    examples.each do |example|
      # Run example
      example.run(world.example_groups.first, Reporter.new(world.configuration))

      # Notify formatter
      case example.execution_result.status
      when :passed
        formatter.example_passed(double(example: example))
      when :failed
        formatter.example_failed(double(example: example, exception: example.execution_result.exception,
                                        formatted_backtrace: []))
      when :pending
        formatter.example_pending(double(example: example))
      end
    end

    formatter.dump_summary(double(example_count: examples.length, failure_count: 1, pending_count: 1))
  end

  output.rewind
  puts output.read

  puts
  puts '=' * 80
  puts 'FAILURE LOG:'
  puts '=' * 80
  puts

  log_files = Dir.glob(File.join(log_dir, '*.log'))
  if log_files.any?
    puts File.read(log_files.first)
  else
    puts 'No failure logs generated'
  end
end

# Helper classes
class Reporter < RSpec::Core::Reporter
  def initialize(config)
    super
  end
end

class NullObject
  def method_missing(*)
    self
  end
end

def double(stubs = {})
  stubs.each_with_object(NullObject.new) do |(method, value), obj|
    obj.define_singleton_method(method) { value }
  end
end
