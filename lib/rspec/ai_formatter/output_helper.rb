# frozen_string_literal: true

module RSpec
  module AiFormatter
    # Handles output formatting and utility methods
    module OutputHelper
      def emit(hash)
        @output.puts(hash.to_json)
      end

      def emit_minimal_test(example, status, skip: nil)
        hash = {
          t: 'test',
          id: minimal_location(example),
          s: status
        }
        hash[:skip] = skip if skip
        emit(hash)
      end

      def execution_time_ms(example)
        result = example.execution_result
        return nil unless result.respond_to?(:run_time)

        (result.run_time * 1000).round
      end

      def timestamp
        Time.now.utc.iso8601(3)
      end

      def truncate(str, max)
        str = str.to_s
        return str if str.length <= max

        "#{str[0...max]}...[truncated #{str.length - max} chars]"
      end
    end
  end
end
