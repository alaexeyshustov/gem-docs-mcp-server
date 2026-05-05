# frozen_string_literal: true

require "json"
require "stringio"
require "spec_helper"
require "gem_docs"

RSpec.describe GemDocs::Commands::Lookup do
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

  it "does not treat suffix-only class name matches as ambiguous" do
    with_yard_fixture_gem(name: "alpha", source: <<~RUBY) do
      module Alpha
        class Record
        end

        class ActiveRecord
        end
      end
    RUBY
      status = command.call(path: "Record", gem: "alpha", format: "json")

      expect(status).to eq(0)
      expect(JSON.parse(stdout.string)).to include(
        "path" => "Alpha::Record",
        "gem" => "alpha"
      )
    end
  end

  it "does not match partial class name substrings within a segment" do
    with_yard_fixture_gem(name: "alpha", source: <<~RUBY) do
      module Alpha
        class Record
        end

        class RecordCallable
        end
      end
    RUBY
      status = command.call(path: "Record", gem: "alpha", format: "json")

      expect(status).to eq(0)
      expect(JSON.parse(stdout.string)).to include(
        "path" => "Alpha::Record",
        "gem" => "alpha"
      )
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

  it "prefers compressed non-obvious knowledge and reports the knowledge source" do
    with_yard_fixture_gem(name: "lookup_fixture", source: <<~RUBY) do
      module LookupFixture
        class Client
          # Performs the request.
          def call(input)
          end
        end
      end
    RUBY
      Dir.mktmpdir do |tmpdir|
        cache = GemDocs::ArtifactCache.new(path: File.join(tmpdir, "artifacts.sqlite3"))
        registry = GemDocs::DocRegistry.new(cache: cache)
        invalidation_key = registry.artifact_invalidation_key_for("lookup_fixture")

        registry.load_gem("lookup_fixture")
        cache.write_artifact(
          gem_name: "lookup_fixture",
          gem_version: "0.1.0",
          lookup_target: "LookupFixture::Client#call",
          artifact_kind: :compressed,
          payload: {
            "status" => "ready",
            "insights" => [
              {
                "title" => "Input is normalized",
                "detail" => "Leading and trailing whitespace is stripped before dispatch."
              }
            ],
            "source_artifact" => {
              "lookup_target" => "LookupFixture::Client#call",
              "artifact_kind" => "source",
              "artifact_version" => GemDocs::ArtifactCache::ARTIFACT_VERSIONS.fetch(:source),
              "invalidation_key" => invalidation_key,
              "payload_digest" => "digest"
            },
            "prompt_version" => 1
          },
          invalidation_key: invalidation_key
        )

        allow(command).to receive(:doc_registry).and_return(registry)

        status = command.call(
          path: "LookupFixture::Client#call",
          gem: "lookup_fixture",
          format: "json"
        )

        expect(status).to eq(0)
        expect(JSON.parse(stdout.string)).to include(
          "path" => "LookupFixture::Client#call",
          "knowledge_source" => "compressed",
          "non_obvious_insights" => [
            include(
              "title" => "Input is normalized",
              "detail" => "Leading and trailing whitespace is stripped before dispatch."
            )
          ]
        )
      end
    end
  end

  it "falls back to source knowledge when compressed knowledge is marked insufficient" do
    with_yard_fixture_gem(name: "lookup_fixture", source: <<~RUBY) do
      module LookupFixture
        class Client
          # Performs the request.
          def call(input)
          end
        end
      end
    RUBY
      Dir.mktmpdir do |tmpdir|
        cache = GemDocs::ArtifactCache.new(path: File.join(tmpdir, "artifacts.sqlite3"))
        registry = GemDocs::DocRegistry.new(cache: cache)
        invalidation_key = registry.artifact_invalidation_key_for("lookup_fixture")

        registry.load_gem("lookup_fixture")
        cache.write_artifact(
          gem_name: "lookup_fixture",
          gem_version: "0.1.0",
          lookup_target: "LookupFixture::Client#call",
          artifact_kind: :compressed,
          payload: {
            "status" => "insufficient",
            "reason" => "Only obvious API surface information was found.",
            "insights" => []
          },
          invalidation_key: invalidation_key
        )

        allow(command).to receive(:doc_registry).and_return(registry)

        status = command.call(
          path: "LookupFixture::Client#call",
          gem: "lookup_fixture",
          format: "json"
        )

        expect(status).to eq(0)
        payload = JSON.parse(stdout.string)

        expect(payload).to include(
          "path" => "LookupFixture::Client#call",
          "knowledge_source" => "source"
        )
        expect(payload).not_to have_key("non_obvious_insights")
      end
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
