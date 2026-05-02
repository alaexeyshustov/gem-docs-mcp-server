# frozen_string_literal: true

require "json"
require "spec_helper"
require "gem_docs"

RSpec.describe GemDocs::Formatters::Json do
  describe ".for" do
    it "resolves the shared formatter instance by format" do
      expect(GemDocs::Formatters.for("json")).to be_a(described_class)
      expect(GemDocs::Formatters.for("text")).to be_a(GemDocs::Formatters::Text)
    end
  end

  describe "#error" do
    it "renders compact structured errors without empty fields" do
      formatter = described_class.new

      output = formatter.error(
        error: "not_found",
        message: "Gem 'missing-gem' is not installed",
        details: {}
      )

      expect(JSON.parse(output)).to eq(
        "error" => "not_found",
        "message" => "Gem 'missing-gem' is not installed"
      )
    end
  end

  describe "#list" do
    it "omits empty values from gem payloads while preserving required fields" do
      formatter = described_class.new

      output = formatter.list(
        gems: [
          { name: "rack", version: "3.1.0", doc_source: :yard, summary: "HTTP toolkit" },
          { name: "rbs", version: "3.4.0", doc_source: :source_only, summary: "" }
        ]
      )

      expect(JSON.parse(output)).to eq(
        [
          {
            "name" => "rack",
            "version" => "3.1.0",
            "doc_source" => "yard",
            "summary" => "HTTP toolkit"
          },
          {
            "name" => "rbs",
            "version" => "3.4.0",
            "doc_source" => "source_only"
          }
        ]
      )
    end
  end
end
