#!/usr/bin/env ruby
require 'yaml'
require_relative './lib/parsers/yen_press_parser'

file_path = 'config.yaml'
config_data = YAML.load_file(file_path)

puts "--------Yen Press Example:--------"
yen_press_example = config_data['series'][0]
puts yen_press_example
puts "--------Output:--------"
puts YenPressParser.new(yen_press_example['series_url']).parse.to_json
puts "----------------------------------------------------"

