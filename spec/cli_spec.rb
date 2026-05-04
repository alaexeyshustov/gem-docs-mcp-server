# frozen_string_literal: true

require "fileutils"
require "json"
require "stringio"
require "tmpdir"
require "yard"
require "spec_helper"
require "gem_docs"

RSpec.describe GemDocs::CLI do
  def build_fixture_spec(name:, gem_root:, version: "0.1.0", summary: "Fixture gem")
    Gem::Specification.new do |spec|
      spec.name = name
      spec.version = version
      spec.summary = summary
      spec.files = Dir.chdir(gem_root) { Dir["lib/**/*.rb"] }
      spec.require_paths = [ "lib" ]
    end.tap do |spec|
      spec.define_singleton_method(:full_gem_path) { gem_root }
      spec.define_singleton_method(:doc_dir) { File.join(gem_root, "doc") }
    end
  end

  def with_yard_fixture_gem(name:, version: "0.1.0", source:)
    Dir.mktmpdir do |tmpdir|
      gem_root = File.join(tmpdir, name)
      file = File.join(gem_root, "lib", "#{name}.rb")
      yardoc = File.join(gem_root, ".yardoc")
      FileUtils.mkdir_p(File.dirname(file))
      File.write(file, source)

      previous_yardoc = YARD::Registry.yardoc_file
      YARD::Registry.clear
      YARD.parse(file)
      YARD::Registry.save(false, yardoc)
      YARD::Registry.clear
      YARD::Registry.yardoc_file = previous_yardoc

      spec = build_fixture_spec(name: name, gem_root: gem_root, version: version)
      allow(GemDocs::DocRegistry).to receive(:gem_spec_for).with(name).and_return(spec)
      allow(GemDocs::DocRegistry).to receive(:gem_spec_for).with(name, version: version).and_return(spec)

      yield spec
    ensure
      YARD::Registry.clear
      YARD::Registry.yardoc_file = previous_yardoc
    end
  end

  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }

  it "renders dry-cli help for the top-level help flag" do
    status = described_class.start([ "--help" ], out: stdout, err: stderr)

    expect(status).to eq(0)
    expect(stderr.string).to eq("")
    expect(stdout.string).to include("Commands:")
    expect(stdout.string).to include("list")
    expect(stdout.string).to include("Show installed gems")
  end

  it "renders dry-cli command help for subcommands" do
    status = described_class.start([ "list", "--help" ], out: stdout, err: stderr)

    expect(status).to eq(0)
    expect(stderr.string).to eq("")
    expect(stdout.string).to include("Command:")
    expect(stdout.string).to include("Description:")
    expect(stdout.string).to include("Show installed gems")
  end

  it "returns dry-cli usage for unknown commands" do
    status = described_class.start([ "unknown" ], out: stdout, err: stderr)

    expect(status).to eq(1)
    expect(stdout.string).to eq("")
    expect(stderr.string).to include("Commands:")
    expect(stderr.string).to include("list")
  end

  it "dispatches registered commands through dry-cli" do
    stub_const("GemDocs::Commands::Search", Class.new(GemDocs::Commands::Base) do
      desc "Search gem documentation"
      argument :query, type: :string

      def call(query:, **)
        out.puts "searched #{query}"
        0
      end
    end)

    status = described_class.start([ "search", "rack" ], out: stdout, err: stderr)

    expect(status).to eq(0)
    expect(stderr.string).to eq("")
    expect(stdout.string).to eq("searched rack\n")
  end

  it "renders structured JSON for handled command errors" do
    stub_const("GemDocs::Commands::List", Class.new(GemDocs::Commands::Base) do
      desc "Show installed gems"

      def call(**)
        raise GemDocs::GemNotFound.new("missing-gem")
      end
    end)

    status = described_class.start([ "list", "--format", "json" ], out: stdout, err: stderr)

    expect(status).to eq(1)
    expect(stdout.string).to eq("")
    expect(JSON.parse(stderr.string)).to eq(
      "error" => "not_found",
      "message" => "Gem 'missing-gem' is not installed"
    )
  end

  it "renders unavailable errors with the shared JSON envelope" do
    stub_const("GemDocs::Commands::Lookup", Class.new(GemDocs::Commands::Base) do
      desc "Look up a constant or method"

      def call(**)
        raise GemDocs::DocUnavailable.new("missing-gem")
      end
    end)

    status = described_class.start([ "lookup", "--format", "json" ], out: stdout, err: stderr)

    expect(status).to eq(1)
    expect(stdout.string).to eq("")
    expect(JSON.parse(stderr.string)).to eq(
      "error" => "unavailable",
      "message" => "Documentation is unavailable for 'missing-gem'"
    )
  end

  it "renders structured JSON errors for summary lookup failures" do
    stub_const("GemDocs::Commands::Summary", Class.new(GemDocs::Commands::Base) do
      desc "Summarize a gem"

      def call(**)
        raise GemDocs::GemNotFound.new("missing-gem")
      end
    end)

    status = described_class.start([ "summary", "missing-gem", "--format", "json" ], out: stdout, err: stderr)

    expect(status).to eq(1)
    expect(stdout.string).to eq("")
    expect(JSON.parse(stderr.string)).to eq(
      "error" => "not_found",
      "message" => "Gem 'missing-gem' is not installed"
    )
  end

  it "renders structured JSON errors for classes lookup failures" do
    stub_const("GemDocs::Commands::Classes", Class.new(GemDocs::Commands::Base) do
      desc "List documented classes and modules"
      argument :gem_name, type: :string

      def call(**)
        raise GemDocs::GemNotFound.new("missing-gem")
      end
    end)

    status = described_class.start([ "classes", "missing-gem", "--format", "json" ], out: stdout, err: stderr)

    expect(status).to eq(1)
    expect(stdout.string).to eq("")
    expect(JSON.parse(stderr.string)).to eq(
      "error" => "not_found",
      "message" => "Gem 'missing-gem' is not installed"
    )
  end

  it "accepts --version for the summary command" do
    registry = instance_double(
      GemDocs::DocRegistry,
      load_gem: GemDocs::DocRegistry::LoadedGem.new(
        name: "faraday",
        version: "2.12.0",
        summary: "HTTP client",
        description: "HTTP client",
        path: "/tmp/faraday",
        doc_source: :yard,
        objects: []
      )
    )
    allow(GemDocs::DocRegistry).to receive(:new).and_return(registry)

    status = described_class.start([ "summary", "faraday", "--version", "2.12.0" ], out: stdout, err: stderr)

    expect(status).to eq(0)
    expect(stderr.string).to eq("")
    expect(registry).to have_received(:load_gem).with("faraday", version: "2.12.0")
  end

  it "renders structured JSON errors for ambiguous lookups" do
    with_yard_fixture_gem(name: "alpha", source: <<~RUBY) do |alpha_spec|
      module Alpha
        class Widget
          def call
          end
        end
      end
    RUBY
      with_yard_fixture_gem(name: "beta", source: <<~RUBY) do |beta_spec|
        module Beta
          class Widget
            def call
            end
          end
        end
      RUBY
        allow(Gem::Specification).to receive(:to_a).and_return([ alpha_spec, beta_spec ])

        status = described_class.start([ "lookup", "Widget#call", "--format", "json" ], out: stdout, err: stderr)

        expect(status).to eq(1)
        expect(stdout.string).to eq("")
        expect(JSON.parse(stderr.string)).to eq(
          "error" => "ambiguous",
          "message" => "Multiple matches found for 'Widget#call'",
          "candidates" => [ "Alpha::Widget#call", "Beta::Widget#call" ]
        )
      end
    end
  end

  it "renders structured JSON errors for missing lookup results" do
    with_yard_fixture_gem(name: "lookup_fixture", source: "module LookupFixture; end\n") do
      status = described_class.start(
        [ "lookup", "LookupFixture#missing", "--gem", "lookup_fixture", "--format", "json" ],
        out: stdout,
        err: stderr
      )

      expect(status).to eq(1)
      expect(stdout.string).to eq("")
      expect(JSON.parse(stderr.string)).to eq(
        "error" => "not_found",
        "message" => "No method matching 'LookupFixture#missing'"
      )
    end
  end
end
