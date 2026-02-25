# frozen_string_literal: true

module RSpec
  module AiFormatter
    # Handles writing failure logs to disk
    module LogWriter
      def write_failure_log(example, notification)
        return nil if @log_dir == File::NULL

        file = example.metadata[:file_path]
        line = example.metadata[:line_number]
        filename = "#{File.basename(file, '.rb')}_#{line}.log"
        log_path = File.join(@log_dir, filename)

        File.open(log_path, 'w') { |f| write_log_content(f, example, notification) }

        @test_index << {
          test: short_name(example),
          location: "#{file}:#{line}",
          log: log_path,
          status: 'fail'
        }

        log_path
      end

      def write_index_file
        return if @log_dir == File::NULL || @test_index.empty?

        index_path = File.join(@log_dir, 'index.json')
        File.write(index_path, JSON.pretty_generate(@test_index))
      end

      def setup_log_directory
        return if @log_dir == File::NULL || @log_dir.nil?

        FileUtils.mkdir_p(@log_dir)
        return unless ENV['RSPEC_AI_CLEAN'] == '1'

        FileUtils.rm_rf(Dir.glob(File.join(@log_dir, '*.log')))
      end

      private

      def write_log_content(file, example, notification)
        file.puts('=' * 80)
        file.puts("TEST: #{short_name(example)}")
        file.puts("LOCATION: #{example.metadata[:file_path]}:#{example.metadata[:line_number]}")
        file.puts('STATUS: FAIL')
        file.puts("TIME: #{execution_time_ms(example)}ms")
        file.puts('=' * 80)
        file.puts

        write_exception_details(file, notification.exception)
        file.puts
        file.puts('=' * 80)
        file.puts('FULL OUTPUT:')
        file.puts('=' * 80)

        return unless notification.respond_to?(:formatted_backtrace)

        file.puts(notification.formatted_backtrace.join("\n"))
      end

      def write_exception_details(file, exception)
        return unless exception

        file.puts("ERROR: #{error_class(exception)}")
        file.puts('MESSAGE:')
        file.puts(error_message(exception))
        file.puts

        return unless exception.respond_to?(:expected) && exception.respond_to?(:actual)

        file.puts('EXPECTED:')
        file.puts(inspect_value(exception.expected))
        file.puts
        file.puts('ACTUAL:')
        file.puts(inspect_value(exception.actual))
        file.puts

        file.puts('BACKTRACE:')
        exception.backtrace&.first(20)&.each { |l| file.puts(l) }
      end
    end
  end
end
