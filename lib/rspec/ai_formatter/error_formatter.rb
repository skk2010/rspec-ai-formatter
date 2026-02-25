# frozen_string_literal: true

module RSpec
  module AiFormatter
    # Formats error details for output
    module ErrorFormatter
      def error_details(example, notification, log_path, sig = nil)
        exception = notification.exception
        return {} unless exception

        details = {
          type: error_class(exception),
          msg: truncate(error_message(exception), 200),
          loc: failure_location(example, exception)
        }

        details[:log] = log_path if log_path && @log_dir != File::NULL
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

      private

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
    end
  end
end
