# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "yard"
require "spec_helper"
require "gem_docs"

RSpec.describe GemDocs::DocRegistry do
  def build_fixture_spec(name, gem_root:, summary: "Fixture gem")
    Gem::Specification.new do |spec|
      spec.name = name
      spec.version = "0.1.0"
      spec.summary = summary
      spec.files = Dir.chdir(gem_root) { Dir["lib/**/*.rb"] }
      spec.require_paths = [ "lib" ]
    end.tap do |spec|
      spec.define_singleton_method(:full_gem_path) { gem_root }
      spec.define_singleton_method(:doc_dir) { File.join(gem_root, "doc") }
    end
  end

  def with_source_fixture_gem(name, source:)
    Dir.mktmpdir do |tmpdir|
      gem_root = File.join(tmpdir, name)
      FileUtils.mkdir_p(File.join(gem_root, "lib"))
      File.write(File.join(gem_root, "lib", "#{name}.rb"), source)
      spec = build_fixture_spec(name, gem_root: gem_root)

      allow(described_class).to receive(:gem_spec_for).with(name).and_return(spec)

      yield spec
    end
  end

  def with_empty_fixture_gem(name)
    Dir.mktmpdir do |tmpdir|
      gem_root = File.join(tmpdir, name)
      FileUtils.mkdir_p(gem_root)
      spec = build_fixture_spec(name, gem_root: gem_root)

      allow(described_class).to receive(:gem_spec_for).with(name).and_return(spec)

      yield spec
    end
  end

  def with_yard_fixture_gem(name, source:)
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

      spec = build_fixture_spec(name, gem_root: gem_root)
      allow(described_class).to receive(:gem_spec_for).with(name).and_return(spec)

      yield spec
    ensure
      YARD::Registry.clear
      YARD::Registry.yardoc_file = previous_yardoc
    end
  end

  describe "#load_gem" do
    it "falls back to Prism source parsing when structured docs are unavailable" do
      with_source_fixture_gem("source_only", source: <<~RUBY) do
        module SourceOnly
          class Widget
            def call(input)
            end
          end
        end
      RUBY
        registry = described_class.new

        loaded_gem = registry.load_gem("source_only")

        expect(loaded_gem.doc_source).to eq(:source_only)
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
        expect(registry.find_object("WellDocumented::Widget#call", gem_name: "well_documented")&.docstring)
          .to include("Performs work.")
      end
    end

    it "falls back to ri data when a gem has no .yardoc cache" do
      with_source_fixture_gem("rdoc_only", source: "# intentionally empty\n") do |spec|
        FileUtils.mkdir_p(spec.doc_dir)
        commands = []

        shell_runner = lambda do |command|
          commands << command

          case command.last
          when "-l"
            { stdout: "RdocOnly::Widget\n", stderr: "", success: true }
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
        expect(commands.count { |command| command.last == "RdocOnly::Widget" }).to eq(0)
        expect(object&.doc_source).to eq(:rdoc)
        expect(object&.docstring).to include("Calls through ri.")
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
    it "returns :yard when a gem has a .yardoc registry" do
      with_yard_fixture_gem("well_documented", source: "module WellDocumented; end\n") do
        registry = described_class.new

        expect(registry.doc_source_for("well_documented")).to eq(:yard)
      end
    end

    it "uses ri index availability without loading ri objects" do
      with_source_fixture_gem("rdoc_only", source: "# intentionally empty\n") do |spec|
        FileUtils.mkdir_p(spec.doc_dir)
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
