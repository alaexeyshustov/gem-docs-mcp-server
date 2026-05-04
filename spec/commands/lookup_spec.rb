# frozen_string_literal: true

require "fileutils"
require "json"
require "stringio"
require "tmpdir"
require "yard"
require "spec_helper"
require "gem_docs"

RSpec.describe GemDocs::Commands::Lookup do
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

  def with_source_fixture_gem(name:, version: "0.1.0", source:)
    Dir.mktmpdir do |tmpdir|
      gem_root = File.join(tmpdir, name)
      file = File.join(gem_root, "lib", "#{name}.rb")
      FileUtils.mkdir_p(File.dirname(file))
      File.write(file, source)

      spec = build_fixture_spec(name: name, gem_root: gem_root, version: version)
      allow(GemDocs::DocRegistry).to receive(:gem_spec_for).with(name).and_return(spec)
      allow(GemDocs::DocRegistry).to receive(:gem_spec_for).with(name, version: version).and_return(spec)

      yield spec
    end
  end

  let(:stdout) { StringIO.new }
  let(:command) { described_class.new }

  before do
    allow(command).to receive(:out).and_return(stdout)
  end

  it "renders a JSON lookup payload for a documented instance method" do
    with_yard_fixture_gem(name: "lookup_fixture", source: <<~RUBY) do
      module LookupFixture
        class Client
          # Performs the request.
          #
          # @param input [String] The lookup input.
          # @return [String]
          # @example
          #   LookupFixture::Client.new.call("demo")
          def call(input)
          end
        end
      end
    RUBY
      status = command.call(
        path: "LookupFixture::Client#call",
        gem: "lookup_fixture",
        format: "json"
      )

      expect(status).to eq(0)
      payload = JSON.parse(stdout.string)

      expect(payload).to include(
        "path" => "LookupFixture::Client#call",
        "name" => "call",
        "kind" => "instance_method",
        "gem" => "lookup_fixture",
        "version" => "0.1.0",
        "doc_source" => "yard",
        "signature" => "def call(input)",
        "visibility" => "public",
        "docstring" => "Performs the request.",
        "tags" => {
          "param" => [
            {
              "name" => "input",
              "types" => [ "String" ],
              "text" => "The lookup input."
            }
          ],
          "return" => [
            {
              "types" => [ "String" ]
            }
          ],
          "example" => [ "LookupFixture::Client.new.call(\"demo\")" ]
        },
        "aliases" => []
      )
      expect(payload.fetch("source_location")).to match(%r{/lookup_fixture/lib/lookup_fixture\.rb:\d+\z})
    end
  end

  it "renders readable text output with signature, params, and examples" do
    with_yard_fixture_gem(name: "lookup_fixture", source: <<~RUBY) do
      module LookupFixture
        class Client
          # Performs the request.
          #
          # @param input [String] The lookup input.
          # @return [String] The processed response.
          # @example
          #   LookupFixture::Client.new.call("demo")
          def call(input)
          end
        end
      end
    RUBY
      status = command.call(
        path: "LookupFixture::Client#call",
        gem: "lookup_fixture",
        format: "text"
      )

      expect(status).to eq(0)
      expect(stdout.string).to include("LookupFixture::Client#call  [lookup_fixture 0.1.0 · yard]")
      expect(stdout.string).to include("def call(input)")
      expect(stdout.string).to include("Params:")
      expect(stdout.string).to include("input  String  The lookup input.")
      expect(stdout.string).to include("Returns:  String  The processed response.")
      expect(stdout.string).to include("Example:")
      expect(stdout.string).to include("LookupFixture::Client.new.call(\"demo\")")
    end
  end

  it "scopes fuzzy lookup resolution to the requested gem" do
    with_yard_fixture_gem(name: "alpha", source: <<~RUBY) do |alpha_spec|
      module Alpha
        class Widget
          # Alpha implementation.
          def call
          end
        end
      end
    RUBY
      with_yard_fixture_gem(name: "beta", source: <<~RUBY) do |beta_spec|
        module Beta
          class Widget
            # Beta implementation.
            def call
            end
          end
        end
      RUBY
        allow(Gem::Specification).to receive(:to_a).and_return([ alpha_spec, beta_spec ])

        status = command.call(path: "Widget#call", gem: "beta", format: "json")

        expect(status).to eq(0)
        expect(JSON.parse(stdout.string)).to include(
          "path" => "Beta::Widget#call",
          "gem" => "beta",
          "docstring" => "Beta implementation."
        )
      end
    end
  end

  it "preserves empty source-only docstrings in JSON output" do
    with_source_fixture_gem(name: "source_only", source: <<~RUBY) do
      module SourceOnly
        class Widget
          def call(input)
          end
        end
      end
    RUBY
      status = command.call(path: "SourceOnly::Widget#call", gem: "source_only", format: "json")

      expect(status).to eq(0)
      expect(JSON.parse(stdout.string)).to include(
        "path" => "SourceOnly::Widget#call",
        "gem" => "source_only",
        "doc_source" => "source_only",
        "signature" => "SourceOnly::Widget#call(input)",
        "docstring" => "",
        "aliases" => []
      )
    end
  end

  it "falls back to Ruby core ri lookups when no gem match exists" do
    registry = GemDocs::DocRegistry.new(
      shell_runner: lambda do |lookup_command|
        if lookup_command == [ "ri", "--no-pager", "--", "String#gsub" ]
          {
            stdout: "String#gsub(pattern, replacement)\n\nSubstitutes occurrences.\n",
            stderr: "",
            success: true
          }
        else
          { stdout: "", stderr: "missing", success: false }
        end
      end
    )
    allow(command).to receive(:doc_registry).and_return(registry)
    allow(Gem::Specification).to receive(:to_a).and_return([])

    status = command.call(path: "String#gsub", format: "json")

    expect(status).to eq(0)
    expect(JSON.parse(stdout.string)).to include(
      "path" => "String#gsub",
      "gem" => "ruby",
      "version" => RUBY_VERSION,
      "doc_source" => "rdoc",
      "signature" => "String#gsub(pattern, replacement)",
      "docstring" => "Substitutes occurrences."
    )
  end
end
