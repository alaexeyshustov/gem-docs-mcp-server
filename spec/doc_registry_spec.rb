# frozen_string_literal: true

require "tmpdir"
require "spec_helper"
require "gem_docs"

RSpec.describe GemDocs::DocRegistry do
  describe "#load_gem" do
    it "loads the shared local YARD fixture through the shared helper" do
      stub_fixture_gem("yard", name: "yard_fixture", yard: true) do
        registry = described_class.new

        loaded_gem = registry.load_gem("yard_fixture")

        expect(loaded_gem.doc_source).to eq(:yard)
        expect(registry.find_object("YardFixture::Widget#call", gem_name: "yard_fixture")&.docstring)
          .to include("Performs work.")
      end
    end

    it "falls back to Prism source parsing when structured docs are unavailable" do
      stub_fixture_gem("source_only", registry_class: described_class) do
        registry = described_class.new

        loaded_gem = registry.load_gem("source_only")

        expect(loaded_gem.doc_source).to eq(:source_only)
        expect(loaded_gem.entry_points).to eq([])
        expect(registry.find_object("SourceOnly::Widget#call", gem_name: "source_only")&.signature)
          .to eq("SourceOnly::Widget#call(input)")
      end
    end

    it "loads a .yardoc registry and caches the normalized gem entry" do
      with_yard_fixture_gem("well_documented", source: <<~RUBY) do
        module WellDocumented
          class Widget
            # Performs work.
            #
            # @param input [String]
            # @return [String]
            def call(input)
            end
          end
        end
      RUBY
        registry = described_class.new

        first_load = registry.load_gem("well_documented")
        second_load = registry.load_gem("well_documented")

        expect(first_load.doc_source).to eq(:yard)
        expect(second_load).to equal(first_load)
        expect(first_load.entry_points).to include("WellDocumented::Widget#call")
        expect(registry.find_object("WellDocumented::Widget#call", gem_name: "well_documented")&.docstring)
          .to include("Performs work.")
      end
    end

    it "loads a requested gem version when provided" do
      Dir.mktmpdir do |tmpdir|
        gem_root = File.join(tmpdir, "versioned-gem")
        FileUtils.mkdir_p(File.join(gem_root, "lib"))
        spec = build_fixture_spec("versioned-gem", gem_root: gem_root, version: "1.2.3")

        allow(described_class).to receive(:gem_spec_for).with("versioned-gem", version: "1.2.3").and_return(spec)

        registry = described_class.new

        expect(registry.load_gem("versioned-gem", version: "1.2.3").version).to eq("1.2.3")
      end
    end

    it "allows persistent caching to be disabled explicitly" do
      with_source_fixture_gem("cache_toggle_fixture", source: "module CacheToggleFixture; end\n") do
        expect(GemDocs::ArtifactCache).not_to receive(:default)

        registry = described_class.new(cache: false)

        expect(registry.load_gem("cache_toggle_fixture").doc_source).to eq(:source_only)
      end
    end

    it "reuses persisted documentation artifacts across registry instances" do
      with_source_fixture_gem("persistent_fixture", source: <<~RUBY) do
        module PersistentFixture
          class Widget
            def call(input)
            end
          end
        end
      RUBY
        Dir.mktmpdir do |tmpdir|
          cache_path = File.join(tmpdir, "artifacts.sqlite3")
          first_registry = described_class.new(cache: GemDocs::ArtifactCache.new(path: cache_path))

          first_registry.load_gem("persistent_fixture")

          second_registry = described_class.new(cache: GemDocs::ArtifactCache.new(path: cache_path))
          expect(second_registry).not_to receive(:build_loaded_gem)

          loaded_gem = second_registry.load_gem("persistent_fixture")

          expect(loaded_gem.doc_source).to eq(:source_only)
          expect(second_registry.find_object("PersistentFixture::Widget#call", gem_name: "persistent_fixture")&.signature)
            .to eq("PersistentFixture::Widget#call(input)")
        end
      end
    end

    it "persists per-entry source artifacts for offline compression" do
      with_source_fixture_gem("compression_source_fixture", source: <<~RUBY) do
        module CompressionSourceFixture
          class Widget
            def call(input)
            end
          end
        end
      RUBY
        Dir.mktmpdir do |tmpdir|
          cache = GemDocs::ArtifactCache.new(path: File.join(tmpdir, "artifacts.sqlite3"))
          registry = described_class.new(cache: cache)

          registry.load_gem("compression_source_fixture")

          artifacts = registry.source_artifacts_for("compression_source_fixture")

          expect(artifacts.map { |artifact| artifact.fetch(:lookup_target) }).to include(
            "CompressionSourceFixture",
            "CompressionSourceFixture::Widget",
            "CompressionSourceFixture::Widget#call"
          )
          expect(artifacts.find { |artifact| artifact.fetch(:lookup_target) == "CompressionSourceFixture::Widget#call" })
            .to include(
              payload: include(
                "path" => "CompressionSourceFixture::Widget#call",
                "signature" => "CompressionSourceFixture::Widget#call(input)",
                "doc_source" => "source_only"
              )
            )
        end
      end
    end

    it "backfills missing per-entry source artifacts from cached gem snapshots" do
      with_source_fixture_gem("compression_source_fixture", source: <<~RUBY) do
        module CompressionSourceFixture
          class Widget
            def call(input)
            end
          end
        end
      RUBY
        Dir.mktmpdir do |tmpdir|
          cache_path = File.join(tmpdir, "artifacts.sqlite3")
          cache = GemDocs::ArtifactCache.new(path: cache_path)
          initial_registry = described_class.new(cache: cache)

          initial_registry.load_gem("compression_source_fixture")

          SQLite3::Database.new(cache_path).tap do |database|
            database.execute(
              "DELETE FROM documentation_artifacts WHERE gem_name = ? AND lookup_target != ?",
              "compression_source_fixture",
              GemDocs::ArtifactCache::GEM_LOOKUP_TARGET
            )
          ensure
            database.close
          end

          rebuilt_registry = described_class.new(cache: GemDocs::ArtifactCache.new(path: cache_path))
          artifacts = rebuilt_registry.source_artifacts_for("compression_source_fixture")

          expect(artifacts.map { |artifact| artifact.fetch(:lookup_target) }).to include(
            "CompressionSourceFixture",
            "CompressionSourceFixture::Widget",
            "CompressionSourceFixture::Widget#call"
          )
        end
      end
    end

    it "invalidates persisted documentation artifacts when gem contents change" do
      with_source_fixture_gem("mutable_fixture", source: <<~RUBY) do |spec|
        module MutableFixture
          class Widget
            def call(input)
            end
          end
        end
      RUBY
        Dir.mktmpdir do |tmpdir|
          cache_path = File.join(tmpdir, "artifacts.sqlite3")
          first_registry = described_class.new(cache: GemDocs::ArtifactCache.new(path: cache_path))

          expect(first_registry.find_object("MutableFixture::Widget#call", gem_name: "mutable_fixture")&.signature)
            .to eq("MutableFixture::Widget#call(input)")

          File.write(File.join(spec.full_gem_path, "lib", "mutable_fixture.rb"), <<~RUBY)
            module MutableFixture
              class Widget
                def call(input, retries: 0)
                end
              end
            end
          RUBY

          second_registry = described_class.new(cache: GemDocs::ArtifactCache.new(path: cache_path))

          expect(second_registry.find_object("MutableFixture::Widget#call", gem_name: "mutable_fixture")&.signature)
            .to eq("MutableFixture::Widget#call(input, retries: ?)")
        end
      end
    end

    it "rebuilds from source when a persisted cache entry is corrupted" do
      with_source_fixture_gem("corrupt_cache_fixture", source: <<~RUBY) do |spec|
        module CorruptCacheFixture
          class Widget
            def call(input)
            end
          end
        end
      RUBY
        Dir.mktmpdir do |tmpdir|
          cache_path = File.join(tmpdir, "artifacts.sqlite3")
          cache = GemDocs::ArtifactCache.new(path: cache_path)
          registry = described_class.new(cache: cache)
          invalidation_key = registry.send(:artifact_invalidation_key, spec)

          cache.write_artifact(
            gem_name: "corrupt_cache_fixture",
            gem_version: "0.1.0",
            lookup_target: GemDocs::ArtifactCache::GEM_LOOKUP_TARGET,
            artifact_kind: :source,
            payload: { "name" => "bad" },
            invalidation_key: invalidation_key
          )

          SQLite3::Database.new(cache_path).tap do |database|
            database.execute(
              "UPDATE documentation_artifacts SET payload = ? WHERE gem_name = ?",
              "{",
              "corrupt_cache_fixture"
            )
          ensure
            database.close
          end

          rebuilt_registry = described_class.new(cache: cache)

          expect(rebuilt_registry.find_object("CorruptCacheFixture::Widget#call", gem_name: "corrupt_cache_fixture")&.signature)
            .to eq("CorruptCacheFixture::Widget#call(input)")
        end
      end
    end

    it "treats invalidation key read failures as cache misses" do
      with_source_fixture_gem("invalidation_failure_fixture", source: <<~RUBY) do |spec|
        module InvalidationFailureFixture
          class Widget
            def call(input)
            end
          end
        end
      RUBY
        source_path = File.join(spec.full_gem_path, "lib", "invalidation_failure_fixture.rb")
        allow(File).to receive(:stat).and_call_original
        allow(File).to receive(:stat).with(source_path).and_raise(Errno::ENOENT, source_path)

        registry = described_class.new(cache: GemDocs::ArtifactCache.new(path: File.join(spec.full_gem_path, "cache.sqlite3")))

        expect(registry.find_object("InvalidationFailureFixture::Widget#call", gem_name: "invalidation_failure_fixture")&.signature)
          .to eq("InvalidationFailureFixture::Widget#call(input)")
      end
    end

    it "falls back to ri data when a gem has no .yardoc cache" do
      stub_fixture_gem("rdoc_only", registry_class: described_class) do |spec|
        commands = []

        shell_runner = lambda do |command|
          commands << command

          case command.last
          when "-l"
            { stdout: "RdocOnly::Widget\nRdocOnly::Widget#call\n", stderr: "", success: true }
          when "RdocOnly::Widget"
            { stdout: "class RdocOnly::Widget\n\nThe primary RDoc class.\n", stderr: "", success: true }
          when "RdocOnly::Widget#call"
            { stdout: "RdocOnly::Widget#call\n\nCalls through ri.\n", stderr: "", success: true }
          else
            { stdout: "", stderr: "Not found", success: false }
          end
        end

        registry = described_class.new(shell_runner: shell_runner)

        loaded_gem = registry.load_gem("rdoc_only")
        object = registry.find_object("RdocOnly::Widget#call", gem_name: "rdoc_only")

        expect(loaded_gem.doc_source).to eq(:rdoc)
        expect(commands.count { |command| command.last == "RdocOnly::Widget" }).to eq(1)
        expect(commands.count { |command| command.last == "RdocOnly::Widget#call" }).to eq(1)
        expect(object&.doc_source).to eq(:rdoc)
        expect(object&.docstring).to include("Calls through ri.")
      end
    end

    it "rebuilds cached rdoc gems with lazy ri lookups across registry instances" do
      stub_fixture_gem("rdoc_only", registry_class: described_class) do
        Dir.mktmpdir do |tmpdir|
          cache_path = File.join(tmpdir, "artifacts.sqlite3")
          commands = []

          shell_runner = lambda do |command|
            commands << command

            case command.last
            when "-l"
              { stdout: "RdocOnly::Widget\nRdocOnly::Widget#call\n", stderr: "", success: true }
            when "RdocOnly::Widget"
              { stdout: "class RdocOnly::Widget\n\nThe primary RDoc class.\n", stderr: "", success: true }
            when "RdocOnly::Widget#call"
              { stdout: "RdocOnly::Widget#call\n\nCalls through ri.\n", stderr: "", success: true }
            else
              { stdout: "", stderr: "Not found", success: false }
            end
          end

          first_registry = described_class.new(
            shell_runner: shell_runner,
            cache: GemDocs::ArtifactCache.new(path: cache_path)
          )
          first_registry.load_gem("rdoc_only")

          commands.clear

          second_registry = described_class.new(
            shell_runner: shell_runner,
            cache: GemDocs::ArtifactCache.new(path: cache_path)
          )
          object = second_registry.find_object("RdocOnly::Widget#call", gem_name: "rdoc_only")

          expect(object&.doc_source).to eq(:rdoc)
          expect(object&.docstring).to include("Calls through ri.")
          expect(commands.map(&:last)).to include("RdocOnly::Widget#call")
          expect(commands.map(&:last)).not_to include("-l")
        end
      end
    end

    it "persists hydrated ri object payloads for offline compression" do
      stub_fixture_gem("rdoc_only", registry_class: described_class) do
        Dir.mktmpdir do |tmpdir|
          cache = GemDocs::ArtifactCache.new(path: File.join(tmpdir, "artifacts.sqlite3"))

          shell_runner = lambda do |command|
            case command.last
            when "-l"
              { stdout: "RdocOnly::Widget\nRdocOnly::Widget#call\n", stderr: "", success: true }
            when "RdocOnly::Widget"
              { stdout: "class RdocOnly::Widget\n\nThe primary RDoc class.\n", stderr: "", success: true }
            when "RdocOnly::Widget#call"
              { stdout: "RdocOnly::Widget#call\n\nCalls through ri.\n", stderr: "", success: true }
            else
              { stdout: "", stderr: "Not found", success: false }
            end
          end

          registry = described_class.new(shell_runner: shell_runner, cache: cache)

          registry.load_gem("rdoc_only")
          artifacts = registry.source_artifacts_for("rdoc_only")

          expect(artifacts.find { |artifact| artifact.fetch(:lookup_target) == "RdocOnly::Widget#call" }).to include(
            payload: include(
              "doc_source" => "rdoc",
              "signature" => "RdocOnly::Widget#call",
              "docstring" => "Calls through ri."
            )
          )
        end
      end
    end

    it "caches missing ri lookups so they do not rerun external commands" do
      with_source_fixture_gem("rdoc_cache", source: "# intentionally empty\n") do |spec|
        FileUtils.mkdir_p(spec.doc_dir)
        lookup_count = 0

        shell_runner = lambda do |command|
          case command.last
          when "-l"
            { stdout: "RdocCache::Widget\n", stderr: "", success: true }
          when "RdocCache::Widget#missing"
            lookup_count += 1
            { stdout: "", stderr: "Not found", success: false }
          else
            { stdout: "class RdocCache::Widget\n", stderr: "", success: true }
          end
        end

        registry = described_class.new(shell_runner: shell_runner)

        2.times do
          expect(registry.find_object("RdocCache::Widget#missing", gem_name: "rdoc_cache")).to be_nil
        end

        expect(lookup_count).to eq(1)
      end
    end

    it "falls back to source parsing when ri cannot be executed" do
      with_source_fixture_gem("ri_missing", source: <<~RUBY) do |spec|
        module RiMissing
          class Widget
            def call
            end
          end
        end
      RUBY
        FileUtils.mkdir_p(spec.doc_dir)

        registry = described_class.new(
          shell_runner: lambda do |_command|
            raise Errno::ENOENT, "ri"
          end
        )

        loaded_gem = registry.load_gem("ri_missing")

        expect(loaded_gem.doc_source).to eq(:source_only)
        expect(registry.find_object("RiMissing::Widget#call", gem_name: "ri_missing")&.signature)
          .to eq("RiMissing::Widget#call()")
      end
    end

    it "returns :none when no documentation or Ruby source files are available" do
      with_empty_fixture_gem("empty_fixture") do
        registry = described_class.new

        loaded_gem = registry.load_gem("empty_fixture")

        expect(loaded_gem.doc_source).to eq(:none)
        expect(loaded_gem.objects).to eq([])
      end
    end

    it "raises GemDocs::GemNotFound for missing gems" do
      allow(described_class).to receive(:gem_spec_for).with("missing-gem").and_return(nil)

      registry = described_class.new

      expect { registry.load_gem("missing-gem") }.to raise_error(GemDocs::GemNotFound)
    end

    it "wraps broken YARD registries in GemDocs::RegistryError" do
      with_yard_fixture_gem("broken_yard", source: "module BrokenYard; end\n") do
        allow(YARD::Registry).to receive(:load!).and_raise(StandardError, "boom")

        registry = described_class.new

        expect { registry.load_gem("broken_yard") }
          .to raise_error(GemDocs::RegistryError, /Failed to load YARD registry: boom/)
      end
    end
  end

  describe "#doc_source_for" do
    it "reuses cached versioned loads for doc source lookups" do
      Dir.mktmpdir do |tmpdir|
        gem_root = File.join(tmpdir, "versioned-gem")
        FileUtils.mkdir_p(File.join(gem_root, "lib"))
        File.write(File.join(gem_root, "lib", "versioned-gem.rb"), "module VersionedGem; end\n")
        spec = build_fixture_spec("versioned-gem", gem_root: gem_root, version: "1.2.3")

        expect(described_class).to receive(:gem_spec_for).with("versioned-gem", version: "1.2.3").once.and_return(spec)

        registry = described_class.new
        registry.load_gem("versioned-gem", version: "1.2.3")

        expect(registry.doc_source_for("versioned-gem", version: "1.2.3")).to eq(:source_only)
      end
    end

    it "keeps cached doc sources separate for different gem versions" do
      Dir.mktmpdir do |tmpdir|
        first_root = File.join(tmpdir, "multi-version-1")
        second_root = File.join(tmpdir, "multi-version-2")
        FileUtils.mkdir_p(first_root)
        FileUtils.mkdir_p(File.join(second_root, "lib"))
        File.write(File.join(second_root, "lib", "multi-version.rb"), "module MultiVersion; end\n")

        first_spec = build_fixture_spec("multi-version", gem_root: first_root, version: "1.0.0")
        second_spec = build_fixture_spec("multi-version", gem_root: second_root, version: "2.0.0")
        registry = described_class.new

        expect(registry.doc_source_for("multi-version", version: "1.0.0", spec: first_spec)).to eq(:none)
        expect(registry.doc_source_for("multi-version", version: "2.0.0", spec: second_spec)).to eq(:source_only)
      end
    end

    it "returns :yard when a gem has a .yardoc registry" do
      with_yard_fixture_gem("well_documented", source: "module WellDocumented; end\n") do
        registry = described_class.new

        expect(registry.doc_source_for("well_documented")).to eq(:yard)
      end
    end

    it "uses ri index availability without loading ri objects" do
      stub_fixture_gem("rdoc_only", registry_class: described_class) do |spec|
        commands = []

        shell_runner = lambda do |command|
          commands << command

          case command.last
          when "-l"
            { stdout: "RdocOnly::Widget\n", stderr: "", success: true }
          else
            raise "unexpected command: #{command.inspect}"
          end
        end

        registry = described_class.new(shell_runner: shell_runner)

        expect(registry.doc_source_for("rdoc_only")).to eq(:rdoc)
        expect(commands).to eq([ [ "ri", "--no-pager", "--no-standard-docs", "-d", spec.doc_dir, "-l" ] ])
      end
    end

    it "returns :source_only when Ruby source defines documentable objects" do
      with_source_fixture_gem("source_only", source: <<~RUBY) do
        module SourceOnly
          class Widget
            def call
            end
          end
        end
      RUBY
        registry = described_class.new

        expect(registry.doc_source_for("source_only")).to eq(:source_only)
      end
    end

    it "returns :none when Ruby files do not define documentable objects" do
      with_source_fixture_gem("empty_source", source: "# intentionally empty\n") do
        registry = described_class.new

        expect(registry.doc_source_for("empty_source")).to eq(:none)
      end
    end
  end

  describe "#find_object" do
    it "walks inherited namespaces to resolve inherited instance methods" do
      with_source_fixture_gem("inheritance_fixture", source: <<~RUBY) do
        module InheritanceFixture
          class Parent
            def base_call(token)
            end
          end

          class Child < Parent
          end
        end
      RUBY
        registry = described_class.new

        object = registry.find_object("InheritanceFixture::Child#base_call", gem_name: "inheritance_fixture")

        expect(object&.path).to eq("InheritanceFixture::Parent#base_call")
        expect(object&.signature).to eq("InheritanceFixture::Parent#base_call(token)")
      end
    end

    it "resolves class methods and constants from Prism source parsing" do
      with_source_fixture_gem("lookup_fixture", source: <<~RUBY) do
        module LookupFixture
          class Widget
            VERSION = "1.0.0"

            def self.build(name:, **options)
            end
          end
        end
      RUBY
        registry = described_class.new

        method_object = registry.find_object("LookupFixture::Widget.build", gem_name: "lookup_fixture")
        constant_object = registry.find_object("LookupFixture::Widget::VERSION", gem_name: "lookup_fixture")

        expect(method_object&.signature).to eq("LookupFixture::Widget.build(name:, **options)")
        expect(constant_object&.kind).to eq(:constant)
      end
    end

    it "treats methods inside class << self as class methods" do
      with_source_fixture_gem("singleton_fixture", source: <<~RUBY) do
        module SingletonFixture
          class Widget
            class << self
              def build(name)
              end
            end
          end
        end
      RUBY
        registry = described_class.new

        object = registry.find_object("SingletonFixture::Widget.build", gem_name: "singleton_fixture")

        expect(object&.kind).to eq(:class_method)
        expect(object&.signature).to eq("SingletonFixture::Widget.build(name)")
      end
    end

    it "passes ri object lookups after an end-of-options marker" do
      with_source_fixture_gem("rdoc_flags", source: "# intentionally empty\n") do |spec|
        FileUtils.mkdir_p(spec.doc_dir)
        commands = []

        shell_runner = lambda do |command|
          commands << command

          case command.last
          when "-l"
            { stdout: "Flagged::Widget\n", stderr: "", success: true }
          when "-Flagged"
            { stdout: "class -Flagged\n", stderr: "", success: true }
          else
            { stdout: "", stderr: "Not found", success: false }
          end
        end

        registry = described_class.new(shell_runner: shell_runner)

        registry.find_object("-Flagged", gem_name: "rdoc_flags")

        lookup_command = commands.find { |command| command.last == "-Flagged" }
        expect(lookup_command).to include("--")
        expect(lookup_command.index("--")).to be < lookup_command.index("-Flagged")
      end
    end
  end

  describe "#classes_for" do
    it "returns class and module entries in alphabetical order" do
      with_source_fixture_gem("class_listing", source: <<~RUBY) do
        module ClassListing
          module Utilities
          end

          class Widget
            def call
            end
          end
        end
      RUBY
        registry = described_class.new

        classes = registry.classes_for("class_listing")

        expect(classes.map(&:path)).to eq([
          "ClassListing",
          "ClassListing::Utilities",
          "ClassListing::Widget"
        ])
        expect(classes.map(&:kind)).to eq([ :module, :module, :class ])
      end
    end
  end

  describe "private helpers" do
    it "returns a failed response when a command is unavailable" do
      response = described_class.new.send(:run_command, [ "missing-ri-command" ])

      expect(response[:success]).to eq(false)
      expect(response[:error]).to be_a(Errno::ENOENT)
    end
  end
end
