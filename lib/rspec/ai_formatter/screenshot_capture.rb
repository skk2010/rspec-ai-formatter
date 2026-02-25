# frozen_string_literal: true

module RSpec
  module AiFormatter
    # Captures Capybara screenshots on test failure
    module ScreenshotCapture
      def capture_screenshot(example)
        return nil unless capybara_available?
        return nil unless example.metadata[:type] == :feature || example.metadata[:type] == :system

        screenshot_path = take_screenshot
        return nil unless screenshot_path && File.exist?(screenshot_path)

        screenshot_path
      rescue StandardError
        nil
      end

      def copy_screenshot_to_logs(example, screenshot_path)
        return nil unless screenshot_path && @log_dir != File::NULL

        file = example.metadata[:file_path]
        line = example.metadata[:line_number]
        filename = "#{File.basename(file, '.rb')}_#{line}.png"
        dest_path = File.join(@log_dir, filename)

        FileUtils.cp(screenshot_path, dest_path)
        dest_path
      rescue StandardError
        nil
      end

      private

      def capybara_available?
        defined?(Capybara) && Capybara.respond_to?(:current_session)
      end

      def take_screenshot
        # Try different Capybara screenshot methods
        if Capybara.current_session.respond_to?(:save_screenshot)
          # Generate unique temp path
          temp_path = File.join(Dir.tmpdir, "rspec_ai_screenshot_#{Time.now.to_i}_#{rand(1000)}.png")
          Capybara.current_session.save_screenshot(temp_path)
          temp_path
        elsif Capybara.respond_to?(:save_screenshot)
          temp_path = File.join(Dir.tmpdir, "rspec_ai_screenshot_#{Time.now.to_i}_#{rand(1000)}.png")
          Capybara.save_screenshot(temp_path)
          temp_path
        end
      end
    end
  end
end
