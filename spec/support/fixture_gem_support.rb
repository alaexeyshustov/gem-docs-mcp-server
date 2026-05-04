# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "yard"

module FixtureGemSupport
  FIXTURE_ROOT = File.expand_path("../fixtures/gems", __dir__)

  def build_fixture_spec(name = nil, gem_root:, summary: "Fixture gem", version: "0.1.0", **kwargs)
    name ||= kwargs.fetch(:name)

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

  def with_fixture_gem(fixture_name, name: fixture_name, summary: "Fixture gem", version: "0.1.0", yard: false)
    Dir.mktmpdir do |tmpdir|
      gem_root = File.join(tmpdir, name)
      FileUtils.mkdir_p(gem_root)
      FileUtils.cp_r(File.join(fixture_path_for(fixture_name), "."), gem_root)
      build_yard_registry(gem_root) if yard

      yield build_fixture_spec(name: name, gem_root: gem_root, summary: summary, version: version)
    end
  end

  def with_source_fixture_gem(name = nil, source:, summary: "Fixture gem", version: "0.1.0", **kwargs)
    name ||= kwargs.fetch(:name)

    Dir.mktmpdir do |tmpdir|
      gem_root = File.join(tmpdir, name)
      FileUtils.mkdir_p(File.join(gem_root, "lib"))
      File.write(File.join(gem_root, "lib", "#{name}.rb"), source)
      spec = build_fixture_spec(name: name, gem_root: gem_root, summary: summary, version: version)
      stub_gem_spec_lookup(name, version, spec)

      yield spec
    end
  end

  def with_empty_fixture_gem(name, summary: "Fixture gem", version: "0.1.0")
    Dir.mktmpdir do |tmpdir|
      gem_root = File.join(tmpdir, name)
      FileUtils.mkdir_p(gem_root)
      spec = build_fixture_spec(name: name, gem_root: gem_root, summary: summary, version: version)
      stub_gem_spec_lookup(name, version, spec)

      yield spec
    end
  end

  def with_yard_fixture_gem(name = nil, source:, summary: "Fixture gem", version: "0.1.0", **kwargs)
    name ||= kwargs.fetch(:name)

    with_source_fixture_gem(name, source: source, summary: summary, version: version) do |spec|
      build_yard_registry(spec.full_gem_path)
      yield spec
    end
  end

  def stub_fixture_gem(
    fixture_name,
    registry_class: GemDocs::DocRegistry,
    name: fixture_name,
    summary: "Fixture gem",
    version: "0.1.0",
    yard: false
  )
    with_fixture_gem(fixture_name, name: name, summary: summary, version: version, yard: yard) do |spec|
      allow(registry_class).to receive(:gem_spec_for).with(name).and_return(spec)
      allow(registry_class).to receive(:gem_spec_for).with(name, version: version).and_return(spec)

      yield spec
    end
  end

  private

  def fixture_path_for(name)
    File.join(FIXTURE_ROOT, name.to_s)
  end

  def stub_gem_spec_lookup(name, version, spec)
    allow(GemDocs::DocRegistry).to receive(:gem_spec_for).with(name).and_return(spec)
    allow(GemDocs::DocRegistry).to receive(:gem_spec_for).with(name, version: version).and_return(spec)
  end

  def build_yard_registry(gem_root)
    previous_yardoc = YARD::Registry.yardoc_file
    YARD::Registry.clear
    Dir.glob(File.join(gem_root, "lib/**/*.rb")).sort.each { |file| YARD.parse(file) }
    YARD::Registry.save(false, File.join(gem_root, ".yardoc"))
  ensure
    YARD::Registry.clear
    YARD::Registry.yardoc_file = previous_yardoc
  end
end

RSpec.configure do |config|
  config.include FixtureGemSupport
end
