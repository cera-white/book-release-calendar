#!/usr/bin/env ruby
require 'yaml'
require 'json'
require_relative './lib/parsers/yen_press_parser'
require_relative './lib/parsers/seven_seas_parser'
require_relative './lib/parsers/square_enix_parser'
require_relative './lib/parsers/kodansha_parser'
require_relative './lib/ics_feed_builder'

file_path = 'config.yaml'
puts "Loading config from #{file_path}..."
config_data = YAML.safe_load_file(file_path)
puts "Config loaded."

series_list = []

puts "Getting series data..."
config_data['series'].each do |series|
  case series['publisher']
  when 'yen_press'
    parser = YenPressParser
  when 'seven_seas_entertainment'
    parser = SevenSeasParser
  when 'square_enix'
    parser = SquareEnixParser
  when 'kodansha_international'
    parser = KodanshaParser
  else
    parser = nil
  end

  next if parser.nil?

  puts "Parsing series #{series['title']} from #{series['publisher']}..."
  series_list.push(
    JSON.parse(
      JSON.dump(parser.new(series).parse),
      symbolize_names: true
    )
  )
end
puts "Done getting series data."

puts "Building release calendar..."
calendar_file_name = "book-releases.ics"
builder = IcsFeedBuilder.new(domain: "anigramsproductions.com", calname: "Book Releases")
builder.write(calendar_file_name, series_list)
puts "Calendar generated at: #{calendar_file_name}"