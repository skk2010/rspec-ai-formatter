# frozen_string_literal: true

require 'rspec/ai_formatter'

RSpec.describe RSpec::AiFormatter::Formatter do
  let(:output) { StringIO.new }
  let(:formatter) { described_class.new(output) }
  let(:log_dir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(log_dir)
  end

  describe '#initialize' do
    it 'accepts custom log directory' do
      f = described_class.new(output, log_dir: log_dir)
      expect(f).to be_a(described_class)
    end

    it 'uses environment variable for log directory' do
      ENV['RSPEC_AI_LOGS'] = log_dir
      f = described_class.new(output)
      expect(f).to be_a(described_class)
      ENV.delete('RSPEC_AI_LOGS')
    end
  end

  describe '#start' do
    let(:notification) do
      double(
        'notification',
        count: 5
      )
    end

    it 'emits start event' do
      formatter.start(notification)
      output.rewind
      json = JSON.parse(output.read)

      expect(json['t']).to eq('start')
      expect(json['total']).to eq(5)
    end
  end

  describe '#example_passed' do
    let(:example) do
      double(
        'example',
        metadata: {
          file_path: 'spec/test_spec.rb',
          line_number: 15,
          block: nil
        },
        description: 'does something',
        example_group: example_group,
        execution_result: execution_result
      )
    end

    let(:example_group) do
      double(
        'example_group',
        description: 'TestClass',
        superclass: RSpec::Core::ExampleGroup
      )
    end

    let(:execution_result) do
      double('result', run_time: 0.012)
    end

    let(:notification) { double('notification', example: example) }

    it 'emits test event with pass status' do
      # Pass events only emitted in full mode
      ENV['RSPEC_AI_FULL'] = '1'
      formatter = described_class.new(output)
      formatter.start(double(count: 1))
      formatter.example_passed(notification)

      output.rewind
      lines = output.read.lines
      json = JSON.parse(lines.last)

      expect(json['t']).to eq('test')
      expect(json['s']).to eq('pass')
      expect(json['id']).to include('spec/test_spec.rb:15')
      expect(json['n']).to eq('TestClass > does something')
    end
  end

  describe '#example_failed' do
    let(:exception) do
      StandardError.new('something went wrong').tap do |e|
        e.set_backtrace(['spec/test_spec.rb:20:in `block`
'])
      end
    end

    let(:example) do
      double(
        'example',
        metadata: {
          file_path: 'spec/test_spec.rb',
          line_number: 15,
          block: nil
        },
        description: 'does something',
        example_group: example_group,
        execution_result: execution_result
      )
    end

    let(:example_group) do
      double(
        'example_group',
        description: 'TestClass',
        superclass: RSpec::Core::ExampleGroup
      )
    end

    let(:execution_result) do
      double('result', run_time: 0.045)
    end

    let(:notification) do
      double(
        'notification',
        example: example,
        exception: exception,
        formatted_backtrace: ['spec/test_spec.rb:20:in `block`']
      )
    end

    it 'emits test event with fail status' do
      formatter = described_class.new(output, log_dir: log_dir)
      formatter.start(double(count: 1))
      formatter.example_failed(notification)

      output.rewind
      lines = output.read.lines
      json = JSON.parse(lines.last)

      expect(json['t']).to eq('test')
      expect(json['s']).to eq('fail')
      expect(json['e']['type']).to eq('StandardError')
      expect(json['e']['msg']).to eq('something went wrong')
    end

    it 'creates failure log file' do
      formatter = described_class.new(output, log_dir: log_dir)
      formatter.start(double(count: 1))
      formatter.example_failed(notification)

      log_file = File.join(log_dir, 'test_spec_15.log')
      expect(File.exist?(log_file)).to be true
      expect(File.read(log_file)).to include('something went wrong')
    end
  end

  describe '#dump_summary' do
    let(:notification) do
      double(
        'notification',
        example_count: 3,
        failure_count: 1,
        pending_count: 1
      )
    end

    before do
      formatter.start(double(count: 3))
    end

    it 'emits done event with counts' do
      formatter.dump_summary(notification)
      output.rewind
      lines = output.read.lines
      json = JSON.parse(lines.last)

      expect(json['t']).to eq('done')
      expect(json['total']).to eq(3)
      # Counters start at 0 since we didn't actually run any tests
      expect(json['passed']).to eq(0)
      expect(json['failed']).to eq(0)
      expect(json['skipped']).to eq(0)
    end
  end

  describe '#short_name' do
    let(:example) do
      double(
        'example',
        metadata: { file_path: 'spec/test_spec.rb', line_number: 1, block: nil },
        description: 'does something',
        example_group: nested_group,
        execution_result: execution_result
      )
    end

    let(:nested_group) do
      parent = double(
        'parent_group',
        description: 'ParentContext',
        superclass: RSpec::Core::ExampleGroup
      )
      double(
        'example_group',
        description: 'ChildContext',
        superclass: parent
      )
    end

    let(:execution_result) do
      double('result', run_time: 0.005)
    end

    it 'builds hierarchical name' do
      # Pass events only emitted in full mode
      ENV['RSPEC_AI_FULL'] = '1'
      formatter = described_class.new(output)
      formatter.start(double(count: 1))
      notification = double('notification', example: example)
      formatter.example_passed(notification)

      output.rewind
      lines = output.read.lines
      json = JSON.parse(lines.last)

      expect(json['n']).to include('ParentContext')
      expect(json['n']).to include('ChildContext')
    end
  end

  describe 'error deduplication' do
    let(:exception1) do
      StandardError.new('database connection failed').tap do |e|
        e.set_backtrace(['spec/db_spec.rb:10'])
      end
    end

    let(:exception2) do
      StandardError.new('database connection failed').tap do |e|
        e.set_backtrace(['spec/api_spec.rb:20'])
      end
    end

    let(:example1) do
      double(
        'example1',
        metadata: { file_path: 'spec/db_spec.rb', line_number: 10, block: nil },
        description: 'connects to database',
        example_group: example_group,
        execution_result: execution_result
      )
    end

    let(:example2) do
      double(
        'example2',
        metadata: { file_path: 'spec/api_spec.rb', line_number: 20, block: nil },
        description: 'queries database',
        example_group: example_group,
        execution_result: execution_result
      )
    end

    let(:example_group) do
      double(
        'example_group',
        description: 'DB',
        superclass: RSpec::Core::ExampleGroup
      )
    end

    let(:execution_result) do
      double('result', run_time: 0.045)
    end

    let(:notification1) do
      double(
        'notification1',
        example: example1,
        exception: exception1,
        formatted_backtrace: ['spec/db_spec.rb:10']
      )
    end

    let(:notification2) do
      double(
        'notification2',
        example: example2,
        exception: exception2,
        formatted_backtrace: ['spec/api_spec.rb:20']
      )
    end

    around do |example|
      old_env = ENV['RSPEC_AI_DEDUP']
      example.run
      ENV['RSPEC_AI_DEDUP'] = old_env
    end

    it 'deduplicates identical errors when enabled' do
      ENV['RSPEC_AI_DEDUP'] = '1'
      formatter = described_class.new(output, log_dir: log_dir)
      formatter.start(double(count: 2))

      # First failure - full test event
      formatter.example_failed(notification1)
      
      # Second failure - should be dedup
      formatter.example_failed(notification2)

      output.rewind
      lines = output.read.lines

      # Skip start event, then first event should be full test event
      first = JSON.parse(lines[1])
      expect(first['t']).to eq('test')
      expect(first['s']).to eq('fail')

      # Second event should be dedup
      second = JSON.parse(lines[2])
      expect(second['t']).to eq('dedup')
      expect(second['sig']).to eq(first['e']['sig'])
      expect(second['first']).to eq('spec/db_spec.rb:10')
    end

    it 'does not deduplicate when disabled' do
      ENV['RSPEC_AI_DEDUP'] = nil
      formatter = described_class.new(output, log_dir: log_dir)
      formatter.start(double(count: 2))

      formatter.example_failed(notification1)
      formatter.example_failed(notification2)

      output.rewind
      lines = output.read.lines

      # Skip start event
      test_lines = lines[1..-1]
      expect(test_lines.length).to eq(2)
      test_lines.each do |line|
        json = JSON.parse(line)
        expect(json['t']).to eq('test')
      end
    end

    it 'emits dedup_summary for duplicates' do
      ENV['RSPEC_AI_DEDUP'] = '1'
      ENV['RSPEC_AI_FULL'] = '1'  # Need full mode for examples array
      formatter = described_class.new(output, log_dir: log_dir)
      formatter.start(double(count: 2))

      formatter.example_failed(notification1)
      formatter.example_failed(notification2)
      formatter.dump_summary(double(example_count: 2, failure_count: 2, pending_count: 0))

      output.rewind
      lines = output.read.lines

      # Find dedup_summary
      summary = lines.find { |l| l.include?('dedup_summary') }
      expect(summary).not_to be_nil

      json = JSON.parse(summary)
      expect(json['count']).to eq(2)
      expect(json['examples'].length).to eq(2)
    end
  end
end
