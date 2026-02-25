# frozen_string_literal: true

require 'json'
require 'fileutils'

module RSpec
  module AiFormatter
    # AI-friendly formatter for RSpec
    # Outputs compact NDJSON with references to detailed logs
    class Formatter
      RSpec::Core::Formatters.register self,
        :start,
        :example_started,
        :example_passed,
        :example_failed,
        :example_pending,
        :dump_summary

      def initialize(output, log_dir: nil)
        @output = output
        @log_dir = log_dir || ENV.fetch('RSPEC_AI_LOGS', 'tmp/rspec_logs')
        @start_time = nil
        @suite_start = nil
        @failure_count = 0
        @pending_count = 0
        @passed_count = 0
        @test_index = []
        @github_actions = ENV['GITHUB_ACTIONS'] == 'true'
        @deduplicate = ENV['RSPEC_AI_DEDUP'] == '1'
        @minimal = ENV['RSPEC_AI_FULL'] != '1'
        @error_signatures = {}
      end

      def start(notification)
        @suite_start = Time.now

        setup_log_directory

        emit(
          t: 'start',
          total: notification.count,
          ts: timestamp
        )
      end

      def example_started(notification); end

      def example_passed(notification)
        @passed_count += 1
        return if @minimal

        ex = notification.example
        emit(
          t: 'test',
          id: test_location(ex),
          n: short_name(ex),
          s: 'pass',
          time: execution_time_ms(ex),
          ts: timestamp
        )
      end

      def example_failed(notification)
        @failure_count += 1
        ex = notification.example
        exception = notification.exception
        log_path = write_failure_log(ex, notification)

        # Calculate signature for deduplication
        sig = error_signature(exception) if @deduplicate || ENV['RSPEC_AI_SIGNATURES'] == '1'

        if @deduplicate && sig && @error_signatures.key?(sig)
          # This is a duplicate error - emit lightweight dedup event
          @error_signatures[sig][:count] += 1
          @error_signatures[sig][:examples] << test_location(ex)

          emit(
            t: 'dedup',
            sig: sig,
            id: test_location(ex),
            n: short_name(ex),
            first: @error_signatures[sig][:first],
            ts: timestamp
          )
        else
          # First occurrence of this error
          if @deduplicate && sig
            @error_signatures[sig] = {
              count: 1,
              first: test_location(ex),
              examples: [test_location(ex)],
              type: error_class(exception),
              msg: truncate(error_message(exception), 100)
            }
          end

          emit(
            t: 'test',
            id: test_location(ex),
            n: short_name(ex),
            s: 'fail',
            time: execution_time_ms(ex),
            e: error_details(ex, notification, log_path, sig),
            ts: timestamp
          )
        end

        emit_github_error(ex, notification) if @github_actions
      end

      def example_pending(notification)
        @pending_count += 1
        ex = notification.example
        reason = skip_reason(ex)

        if @minimal
          emit_minimal_test(ex, 'skip', skip: reason)
        else
          emit(
            t: 'test',
            id: test_location(ex),
            n: short_name(ex),
            s: 'skip',
            time: execution_time_ms(ex),
            skip: reason,
            ts: timestamp
          )
        end

        emit_github_warning(ex, reason) if @github_actions
      end

      def dump_summary(notification)
        total_time = ((Time.now - @suite_start) * 1000).round

        # Emit dedup summary if there are duplicates
        if @deduplicate && @error_signatures.any? { |_, v| v[:count] > 1 }
          @error_signatures.each do |sig, data|
            next if data[:count] <= 1

            if @minimal
              emit(
                t: 'dedup_summary',
                sig: sig,
                count: data[:count],
                first: data[:first]
              )
            else
              emit(
                t: 'dedup_summary',
                sig: sig,
                type: data[:type],
                msg: data[:msg],
                count: data[:count],
                first: data[:first],
                examples: data[:examples],
                ts: timestamp
              )
            end
          end
        end

        if @minimal
          emit(
            t: 'done',
            passed: @passed_count,
            failed: @failure_count,
            skipped: @pending_count,
            total: notification.example_count,
            time: total_time
          )
        else
          emit(
            t: 'done',
            passed: @passed_count,
            failed: @failure_count,
            skipped: @pending_count,
            total: notification.example_count,
            time: total_time,
            ts: timestamp
          )
        end

        write_index_file
      end

      private

      def emit_minimal_test(example, status, skip: nil)
        hash = {
          t: 'test',
          id: minimal_location(example),
          s: status
        }
        hash[:skip] = skip if skip
        emit(hash)
      end

      def minimal_location(example)
        # Minimal format: no ./ prefix, no end line, just file:start_line
        meta = example.metadata
        file = meta[:file_path].to_s.sub(/^\.\//, '')
        line = meta[:line_number]
        "#{file}:#{line}"
      end

      def emit_github_error(example, notification)
        exception = notification.exception
        return unless exception

        file = example.metadata[:file_path]
        line = example.metadata[:line_number]
        
        # Try to find exact line from backtrace
        if exception.backtrace
          trace_line = exception.backtrace.find { |l| l.include?(file) }
          if trace_line
            parts = trace_line.split(':')
            line = parts[1] if parts[1]&.match?(/^\d+$/)
          end
        end

        msg = truncate(error_message(exception), 200)
        @output.puts("::error file=#{file},line=#{line}::#{msg}")
      end

      def emit_github_warning(example, reason)
        file = example.metadata[:file_path]
        line = example.metadata[:line_number]
        msg = "Skipped: #{truncate(reason || 'pending', 200)}"
        @output.puts("::warning file=#{file},line=#{line}::#{msg}")
      end

      def setup_log_directory
        return if @log_dir == '/dev/null' || @log_dir.nil?

        FileUtils.mkdir_p(@log_dir)
        # Clean old logs if needed
        if ENV['RSPEC_AI_CLEAN'] == '1'
          FileUtils.rm_rf(Dir.glob(File.join(@log_dir, '*.log')))
        end
      end

      def test_location(example)
        meta = example.metadata
        file = meta[:file_path]
        line = meta[:line_number]
        # Try to get end line from source location
        end_line = detect_end_line(example)

        if end_line && end_line > line
          "#{file}:#{line}-#{end_line}"
        else
          "#{file}:#{line}"
        end
      end

      def detect_end_line(example)
        # Get block source location end if available
        block = example.metadata[:block]
        return nil unless block.respond_to?(:source_location)

        loc = block.source_location
        return nil unless loc.is_a?(Array) && loc.length >= 2

        # Try to get end location from proc/method
        if block.respond_to?(:source_location_end)
          block.source_location_end&.last
        else
          # Fallback: estimate based on next example or simple heuristic
          line = loc.last
          # Rough estimate: typical test is 5-15 lines
          # This is imperfect but better than nothing
          line + 10
        end
      rescue StandardError
        nil
      end

      def short_name(example)
        # Build hierarchical name from example groups
        parts = example_groups(example).map(&:description)
        parts << example.description

        # Compact: skip empty descriptions, limit length
        parts.reject(&:empty?).join(' > ').slice(0, 200)
      end

      def example_groups(example, groups = [])
        group = example.example_group
        while group && group != RSpec::Core::ExampleGroup
          groups.unshift(group) unless group.description.empty?
          group = group.superclass
          break if group == RSpec::Core::ExampleGroup
        end
        groups
      end

      def execution_time_ms(example)
        result = example.execution_result
        return nil unless result.respond_to?(:run_time)

        (result.run_time * 1000).round
      end

      def error_details(example, notification, log_path, sig = nil)
        exception = notification.exception
        return {} unless exception

        details = {
          type: error_class(exception),
          msg: truncate(error_message(exception), 200),
          loc: failure_location(example, exception)
        }

        details[:log] = log_path if log_path && @log_dir != '/dev/null'
        details[:sig] = sig if sig

        # Add diff for expectation failures
        if exception.respond_to?(:expected) && exception.respond_to?(:actual)
          details[:diff] = generate_diff(exception.expected, exception.actual)
        end

        details
      end

      def error_class(exception)
        exception.class.name.split('::').last
      rescue StandardError
        'Error'
      end

      def error_message(exception)
        msg = exception.message.to_s
        # Clean up RSpec expectation messages
        msg.gsub(/\e\[\d+m/, '') # Strip ANSI codes
      rescue StandardError
        'Unknown error'
      end

      def error_signature(exception)
        # Create a hash of the error type + normalized message
        # Useful for grouping similar failures
        sig = "#{error_class(exception)}:#{error_message(exception)[0..50]}"
        require 'digest'
        Digest::MD5.hexdigest(sig)[0..7]
      end

      def failure_location(example, exception)
        # Find the most relevant location in the test file
        example_file = example.metadata[:file_path]

        if exception.backtrace
          # Find first line in the test file
          test_line = exception.backtrace.find { |l| l.include?(example_file) }
          return test_line.split(':')[0..1].join(':') if test_line
        end

        # Fallback to example location
        "#{example_file}:#{example.metadata[:line_number]}"
      end

      def skip_reason(example)
        result = example.execution_result
        return nil unless result.respond_to?(:pending_message)

        result.pending_message
      end

      def write_failure_log(example, notification)
        return nil if @log_dir == '/dev/null'

        file = example.metadata[:file_path]
        line = example.metadata[:line_number]
        filename = "#{File.basename(file, '.rb')}_#{line}.log"
        log_path = File.join(@log_dir, filename)

        File.open(log_path, 'w') do |f|
          f.puts("=" * 80)
          f.puts("TEST: #{short_name(example)}")
          f.puts("LOCATION: #{file}:#{line}")
          f.puts("STATUS: FAIL")
          f.puts("TIME: #{execution_time_ms(example)}ms")
          f.puts("=" * 80)
          f.puts

          exception = notification.exception
          if exception
            f.puts("ERROR: #{error_class(exception)}")
            f.puts("MESSAGE:")
            f.puts(error_message(exception))
            f.puts

            if exception.respond_to?(:expected) && exception.respond_to?(:actual)
              f.puts("EXPECTED:")
              f.puts(inspect_value(exception.expected))
              f.puts
              f.puts("ACTUAL:")
              f.puts(inspect_value(exception.actual))
              f.puts
            end

            f.puts("BACKTRACE:")
            exception.backtrace&.first(20)&.each { |l| f.puts(l) }
          end

          f.puts
          f.puts("=" * 80)
          f.puts("FULL OUTPUT:")
          f.puts("=" * 80)

          # Capture any output from the test
          if notification.respond_to?(:formatted_backtrace)
            f.puts(notification.formatted_backtrace.join("\n"))
          end
        end

        @test_index << {
          test: short_name(example),
          location: "#{file}:#{line}",
          log: log_path,
          status: 'fail'
        }

        log_path
      end

      def write_index_file
        return if @log_dir == '/dev/null' || @test_index.empty?

        index_path = File.join(@log_dir, 'index.json')
        File.write(index_path, JSON.pretty_generate(@test_index))
      end

      def generate_diff(expected, actual)
        # Simple diff generation
        return nil if expected.nil? || actual.nil?

        exp_str = inspect_value(expected)
        act_str = inspect_value(actual)

        return nil if exp_str == act_str

        # Return truncated diff
        {
          expected: truncate(exp_str, 500),
          actual: truncate(act_str, 500)
        }
      end

      def inspect_value(value)
        case value
        when String
          value
        when Hash, Array
          JSON.generate(value)
        else
          value.inspect
        end
      rescue StandardError
        value.to_s
      end

      def truncate(str, max)
        str = str.to_s
        return str if str.length <= max

        "#{str[0...max]}...[truncated #{str.length - max} chars]"
      end

      def timestamp
        Time.now.utc.iso8601(3)
      end

      def emit(hash)
        @output.puts(hash.to_json)
      end
    end
  end
end

# Register with RSpec
RSpec::Core::Formatters.register(
  RSpec::AiFormatter::Formatter,
  :start,
  :example_started,
  :example_passed,
  :example_failed,
  :example_pending,
  :dump_summary
) if defined?(RSpec::Core::Formatters)
