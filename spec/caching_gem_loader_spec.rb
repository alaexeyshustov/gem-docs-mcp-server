# frozen_string_literal: true

require "tmpdir"
require "spec_helper"
require "gem_docs"

RSpec.describe GemDocs::CachingGemLoader do
  def build_loaded_gem(spec, source:)
    registry = GemDocs::DocRegistry.new(cache: false)
    objects = registry.send(:load_source_objects, spec)
    registry.send(:build_source_loaded_gem, spec, objects: objects, doc_source: source)
  end

  describe "#load" do
    it "hydrates cached loaded gems from the artifact cache" do
      with_source_fixture_gem("cached_fixture", source: "module CachedFixture; end\n") do |spec|
        cached_gem = build_loaded_gem(spec, source: :source_only)
        hydrated_gem = instance_double(GemDocs::DocRegistry::LoadedGem, doc_source: :source_only)
        base_loader = instance_double(GemDocs::GemLoader)
        invalidation_key_provider = double("invalidation key provider", call: "digest-v1")

        Dir.mktmpdir do |tmpdir|
          cache = GemDocs::ArtifactCache.new(path: File.join(tmpdir, "artifacts.sqlite3"))
          cache.write_loaded_gem(cached_gem, invalidation_key: "digest-v1")

          allow(base_loader).to receive(:resolve_spec!).with("cached_fixture", version: nil).and_return(spec)
          allow(base_loader).to receive(:load)

          loader = described_class.new(
            loader: base_loader,
            cache: cache,
            invalidation_key_provider: invalidation_key_provider,
            loaded_gem_hydrator: lambda do |resolved_spec, loaded_gem|
              expect(resolved_spec).to eq(spec)
              expect(loaded_gem.name).to eq("cached_fixture")
              hydrated_gem
            end
          )

          expect(loader.load("cached_fixture")).to equal(hydrated_gem)
          expect(base_loader).not_to have_received(:load)
        end
      end
    end

    it "persists loaded gems on cache misses" do
      with_source_fixture_gem("cache_miss_fixture", source: <<~RUBY) do |spec|
        module CacheMissFixture
          class Widget
            def call(input)
            end
          end
        end
      RUBY
        loaded_gem = build_loaded_gem(spec, source: :source_only)
        base_loader = instance_double(GemDocs::GemLoader)
        invalidation_key_provider = double("invalidation key provider", call: "digest-v1")

        Dir.mktmpdir do |tmpdir|
          cache = GemDocs::ArtifactCache.new(path: File.join(tmpdir, "artifacts.sqlite3"))
          allow(base_loader).to receive(:resolve_spec!).with("cache_miss_fixture", version: nil).and_return(spec)
          allow(base_loader).to receive(:load).with("cache_miss_fixture", version: nil, spec: spec).and_return(loaded_gem)

          loader = described_class.new(
            loader: base_loader,
            cache: cache,
            invalidation_key_provider: invalidation_key_provider
          )

          expect(loader.load("cache_miss_fixture")).to eq(loaded_gem)
          cached_gem = cache.fetch_loaded_gem(
            gem_name: "cache_miss_fixture",
            gem_version: "0.1.0",
            invalidation_key: "digest-v1"
          )
          expect(cached_gem&.doc_source).to eq(:source_only)
          expect(cached_gem&.objects&.map(&:path)).to include(
            "CacheMissFixture",
            "CacheMissFixture::Widget",
            "CacheMissFixture::Widget#call"
          )
        end
      end
    end

    it "ignores stale snapshots when the invalidation key changes" do
      with_source_fixture_gem("stale_cache_fixture", source: "module StaleCacheFixture; end\n") do |spec|
        stale_gem = build_loaded_gem(spec, source: :source_only)
        fresh_gem = build_loaded_gem(spec, source: :none)
        base_loader = instance_double(GemDocs::GemLoader)
        invalidation_key_provider = double("invalidation key provider", call: "digest-v2")

        Dir.mktmpdir do |tmpdir|
          cache = GemDocs::ArtifactCache.new(path: File.join(tmpdir, "artifacts.sqlite3"))
          cache.write_loaded_gem(stale_gem, invalidation_key: "digest-v1")

          allow(base_loader).to receive(:resolve_spec!).with("stale_cache_fixture", version: nil).and_return(spec)
          allow(base_loader).to receive(:load).with("stale_cache_fixture", version: nil, spec: spec).and_return(fresh_gem)

          loader = described_class.new(
            loader: base_loader,
            cache: cache,
            invalidation_key_provider: invalidation_key_provider
          )

          expect(loader.load("stale_cache_fixture")).to eq(fresh_gem)
          expect(base_loader).to have_received(:load).once
        end
      end
    end

    it "rebuilds when cached snapshots are corrupted" do
      with_source_fixture_gem("corrupt_cache_fixture", source: "module CorruptCacheFixture; end\n") do |spec|
        rebuilt_gem = build_loaded_gem(spec, source: :source_only)
        base_loader = instance_double(GemDocs::GemLoader)
        invalidation_key_provider = double("invalidation key provider", call: "digest-v1")

        Dir.mktmpdir do |tmpdir|
          cache_path = File.join(tmpdir, "artifacts.sqlite3")
          cache = GemDocs::ArtifactCache.new(path: cache_path)
          cache.write_loaded_gem(rebuilt_gem, invalidation_key: "digest-v1")

          SQLite3::Database.new(cache_path).tap do |database|
            database.execute(
              "UPDATE documentation_artifacts SET payload = ? WHERE gem_name = ?",
              "{",
              "corrupt_cache_fixture"
            )
          ensure
            database.close
          end

          allow(base_loader).to receive(:resolve_spec!).with("corrupt_cache_fixture", version: nil).and_return(spec)
          allow(base_loader).to receive(:load).with("corrupt_cache_fixture", version: nil, spec: spec).and_return(rebuilt_gem)

          loader = described_class.new(
            loader: base_loader,
            cache: cache,
            invalidation_key_provider: invalidation_key_provider
          )

          expect(loader.load("corrupt_cache_fixture")).to eq(rebuilt_gem)
          expect(base_loader).to have_received(:load).once
        end
      end
    end
  end

  describe "#detect_source" do
    it "reads the doc source from cached snapshots" do
      with_source_fixture_gem("cached_source_fixture", source: "module CachedSourceFixture; end\n") do |spec|
        cached_gem = build_loaded_gem(spec, source: :source_only)
        base_loader = instance_double(GemDocs::GemLoader)
        invalidation_key_provider = double("invalidation key provider", call: "digest-v1")

        Dir.mktmpdir do |tmpdir|
          cache = GemDocs::ArtifactCache.new(path: File.join(tmpdir, "artifacts.sqlite3"))
          cache.write_loaded_gem(cached_gem, invalidation_key: "digest-v1")

          allow(base_loader).to receive(:detect_source)

          loader = described_class.new(
            loader: base_loader,
            cache: cache,
            invalidation_key_provider: invalidation_key_provider
          )

          expect(loader.detect_source(spec)).to eq(:source_only)
          expect(base_loader).not_to have_received(:detect_source)
        end
      end
    end
  end

  describe "#invalidation_key_for" do
    it "returns nil when invalidation key generation fails" do
      invalidation_key_provider = double("invalidation key provider")
      loader = described_class.new(
        loader: instance_double(GemDocs::GemLoader),
        cache: nil,
        invalidation_key_provider: invalidation_key_provider,
        loaded_gem_hydrator: ->(_spec, loaded_gem) { loaded_gem }
      )
      spec = double("spec", full_gem_path: "/tmp/missing", version: "0.1.0")

      allow(invalidation_key_provider).to receive(:call).and_raise(Errno::ENOENT)

      expect(loader.invalidation_key_for(spec)).to be_nil
    end
  end
end
