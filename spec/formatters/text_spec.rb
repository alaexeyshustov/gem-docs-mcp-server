# frozen_string_literal: true

require "spec_helper"
require "gem_docs"

RSpec.describe GemDocs::Formatters::Text do
  describe "#list" do
    it "renders aligned gem rows for CLI output" do
      formatter = described_class.new

      output = formatter.list(
        gems: [
          { name: "rack", version: "3.1.0", doc_source: :yard, summary: "HTTP toolkit" },
          { name: "rbs", version: "3.4.0", doc_source: :source_only, summary: "" }
        ]
      )

      expect(output.lines).to eq(
        [
          "NAME  VERSION  DOC SOURCE   SUMMARY\n",
          "rack  3.1.0    yard         HTTP toolkit\n",
          "rbs   3.4.0    source_only\n"
        ]
      )
    end
  end
end
