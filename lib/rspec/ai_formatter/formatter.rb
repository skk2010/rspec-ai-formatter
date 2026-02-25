# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'time'
require_relative 'log_writer'
require_relative 'error_formatter'
require_relative 'location_helper'
require_relative 'output_helper'
require_relative 'screenshot_capture'

module RSpec
  module AiFormatter
    # AI-friendly formatter for RSpec
    # Outputs compact NDJSON with references to detailed logs
    class Formatter
      include LogWriter
      include ErrorFormatter
      include LocationHelper
      include OutputHelper
      include ScreenshotCapture

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

        # Capture Capybara screenshot if available
        screenshot_path = capture_screenshot(ex)
        screenshot_log_path = copy_screenshot_to_logs(ex, screenshot_path) if screenshot_path

        # Calculate signature for deduplication
        sig = error_signature(exception) if @deduplicate || ENV['RSPEC_AI_SIGNATURES'] == '1'

        if @deduplicate && sig && @error_signatures.key?(sig)
          handle_duplicate_error(ex, sig)
        else
          handle_first_error(ex, notification, log_path, sig, screenshot_log_path)
        end
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
      end

      def dump_summary(notification)
        total_time = ((Time.now - @suite_start) * 1000).round

        emit_dedup_summaries if @deduplicate && duplicates_exist?

        emit_summary(total_time, notification)
        write_index_file
      end

      private

      def handle_duplicate_error(example, sig)
        @error_signatures[sig][:count] += 1
        @error_signatures[sig][:examples] << test_location(example)

        emit(
          t: 'dedup',
          sig: sig,
          id: test_location(example),
          n: short_name(example),
          first: @error_signatures[sig][:first],
          ts: timestamp
        )
      end

      def handle_first_error(example, notification, log_path, sig, screenshot_path = nil)
        # First occurrence of this error
        if @deduplicate && sig
          @error_signatures[sig] = {
            count: 1,
            first: test_location(example),
            examples: [test_location(example)],
            type: error_class(notification.exception),
            msg: truncate(error_message(notification.exception), 100)
          }
        end

        emit(
          t: 'test',
          id: test_location(example),
          n: short_name(example),
          s: 'fail',
          time: execution_time_ms(example),
          e: error_details(example, notification, log_path, sig, screenshot_path),
          ts: timestamp
        )
      end

      def duplicates_exist?
        @error_signatures.any? { |_, v| v[:count] > 1 }
      end

      def emit_dedup_summaries
        @error_signatures.each do |sig, data|
          next if data[:count] <= 1

          emit(build_dedup_summary(sig, data))
        end
      end

      def build_dedup_summary(sig, data)
        if @minimal
          { t: 'dedup_summary', sig: sig, count: data[:count], first: data[:first] }
        else
          {
            t: 'dedup_summary',
            sig: sig,
            type: data[:type],
            msg: data[:msg],
            count: data[:count],
            first: data[:first],
            examples: data[:examples],
            ts: timestamp
          }
        end
      end

      def emit_summary(total_time, notification)
        summary = {
          t: 'done',
          passed: @passed_count,
          failed: @failure_count,
          skipped: @pending_count,
          total: notification.example_count,
          time: total_time
        }
        summary[:ts] = timestamp unless @minimal
        emit(summary)
      end
    end
  end
end

# Register with RSpec
if defined?(RSpec::Core::Formatters)
  RSpec::Core::Formatters.register(
    RSpec::AiFormatter::Formatter,
    :start,
    :example_started,
    :example_passed,
    :example_failed,
    :example_pending,
    :dump_summary
  )
end
