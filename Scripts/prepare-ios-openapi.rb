#!/usr/bin/env ruby

require "yaml"

input_path, output_path = ARGV
abort "usage: prepare-ios-openapi.rb INPUT OUTPUT" unless input_path && output_path

document = YAML.safe_load(File.read(input_path), aliases: true)
removed_media_types = 0

visit = lambda do |value|
  case value
  when Hash
    content = value["content"]
    if content.is_a?(Hash)
      form_media_types = [
        "application/x-www-form-urlencoded",
        "multipart/form-data"
      ].select { |media_type| content.key?(media_type) }

      if form_media_types.any? && !content.key?("application/json")
        abort "cannot derive the iOS contract: a form request has no JSON variant"
      end

      form_media_types.each do |media_type|
        content.delete(media_type)
        removed_media_types += 1
      end
    end

    value.each_value { |child| visit.call(child) }
  when Array
    value.each { |child| visit.call(child) }
  end
end

visit.call(document)
File.write(output_path, YAML.dump(document))
warn "Prepared JSON-only iOS contract (removed #{removed_media_types} form media types)."
