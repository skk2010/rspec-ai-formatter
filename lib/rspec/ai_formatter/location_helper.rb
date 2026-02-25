# frozen_string_literal: true

module RSpec
  module AiFormatter
    # Handles location and naming for test examples
    module LocationHelper
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

      def minimal_location(example)
        # Minimal format: no ./ prefix, no end line, just file:start_line
        meta = example.metadata
        file = meta[:file_path].to_s.sub(%r{^\./}, '')
        line = meta[:line_number]
        "#{file}:#{line}"
      end

      def short_name(example)
        # Build hierarchical name from example groups
        parts = example_groups(example).map(&:description)
        parts << example.description

        # Compact: skip empty descriptions, limit length
        parts.reject(&:empty?).join(' > ').slice(0, 200)
      end

      private

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
          line + 10
        end
      rescue StandardError
        nil
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
    end
  end
end
