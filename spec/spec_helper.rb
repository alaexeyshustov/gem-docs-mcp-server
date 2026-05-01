# frozen_string_literal: true

require "open3"
require "pathname"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.example_status_persistence_file_path = ".rspec_status"
  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end
end
