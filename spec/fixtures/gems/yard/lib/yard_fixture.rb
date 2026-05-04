# frozen_string_literal: true

module YardFixture
  class Widget
    # Performs work.
    #
    # @param input [String] Input value.
    # @return [String]
    # @example
    #   YardFixture::Widget.new.call("demo")
    def call(input)
      input
    end
  end
end
