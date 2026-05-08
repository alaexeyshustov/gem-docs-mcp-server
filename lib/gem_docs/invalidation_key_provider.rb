# frozen_string_literal: true

require "digest"

module GemDocs
  class InvalidationKeyProvider
    def initialize(file_resolver:, yardoc_resolver:)
      @file_resolver = file_resolver
      @yardoc_resolver = yardoc_resolver
    end

    def call(spec)
      digest = Digest::SHA256.new
      digest << "schema:#{GemDocs::ArtifactCache::SCHEMA_VERSION}\n"
      digest << "gem:#{spec.name}\n"
      digest << "version:#{spec.version}\n"
      digest << "path:#{spec.full_gem_path}\n"

      artifact_files_for(spec).sort.each do |file|
        stat = File.stat(file)
        digest << "file:#{file.delete_prefix("#{spec.full_gem_path}/")}\n"
        digest << "size:#{stat.size}\n"
        digest << "mtime:#{stat.mtime.to_r}\n"
      end

      digest.hexdigest
    end

    private

    def artifact_files_for(spec)
      files = @file_resolver.call(spec)
      yardoc = @yardoc_resolver.call(spec)
      files << yardoc if File.file?(yardoc)
      files.uniq
    end
  end
end
