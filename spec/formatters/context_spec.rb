# frozen_string_literal: true

require "json"
require "spec_helper"
require "gem_docs"

RSpec.describe GemDocs::Formatters::Context do
  let(:gems) do
    [
      {
        name: "rack",
        version: "3.1.0",
        summary: "HTTP toolkit",
        doc_source: :yard,
        classes: [ "Rack::Builder", "Rack::Request" ],
        entry_points: [ "Rack::Builder.new" ]
      },
      {
        name: "undocumented",
        version: "0.1.0",
        summary: "",
        doc_source: :none,
        classes: [],
        entry_points: []
      }
    ]
  end

  describe ".for" do
    it "returns the shared formatter implementation for each supported output" do
      expect(described_class.for("claude")).to be_a(GemDocs::Formatters::Context::Claude)
      expect(described_class.for("cursor")).to be_a(GemDocs::Formatters::Context::Cursor)
      expect(described_class.for("windsurf")).to be_a(GemDocs::Formatters::Context::Windsurf)
      expect(described_class.for("copilot")).to be_a(GemDocs::Formatters::Context::Copilot)
      expect(described_class.for("json")).to be_a(GemDocs::Formatters::Context::Json)
    end
  end

  it "renders compact Claude context for documented gems only" do
    output = described_class.for("claude").call(gems: gems)

    expect(output).to include("# Gem documentation context")
    expect(output).to include("## rack (3.1.0)")
    expect(output).to include("- Classes: Rack::Builder, Rack::Request")
    expect(output).not_to include("undocumented")
  end

  it "renders compact JSON context for documented gems only" do
    output = described_class.for("json").call(gems: gems)

    expect(JSON.parse(output)).to eq(
      "gems" => [
        {
          "name" => "rack",
          "version" => "3.1.0",
          "summary" => "HTTP toolkit",
          "doc_source" => "yard",
          "classes" => [ "Rack::Builder", "Rack::Request" ],
          "entry_points" => [ "Rack::Builder.new" ]
        }
      ]
    )
  end

  it "omits the gems key when every gem is undocumented" do
    output = described_class.for("json").call(
      gems: [
        {
          name: "undocumented",
          version: "0.1.0",
          summary: "",
          doc_source: :none,
          classes: [],
          entry_points: []
        }
      ]
    )

    expect(JSON.parse(output)).to eq({})
  end

  it "keeps Claude output compact for larger projects" do
    large_project = Array.new(20) do |index|
      {
        name: "gem-#{index}",
        version: "1.0.#{index}",
        summary: "A" * 250,
        doc_source: :yard,
        classes: Array.new(12) { |class_index| "Gem#{index}::Class#{class_index}" },
        entry_points: Array.new(5) { |entry_index| "Gem#{index}::Class#{entry_index}#call" }
      }
    end

    output = described_class.for("claude").call(gems: large_project)

    expect(output).to include("- Summary:")
    expect(output).to include("- Entry points:")
    expect(output.bytesize).to be < 10_000
  end
end
