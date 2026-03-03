#!/usr/bin/env ruby
require 'yaml'
require_relative './lib/parsers/yen_press_parser'

file_path = 'config.yaml'
config_data = YAML.safe_load_file(file_path)

puts "--------Yen Press Example:--------"
yen_press_example = config_data['series'][0]
puts yen_press_example
puts "--------Output:--------"
puts YenPressParser.new(yen_press_example).parse.to_json
puts "----------------------------------------------------"

puts "--------Seven Seas Example:--------"
seven_seas_example = config_data['series'][2]
puts seven_seas_example
puts "--------Output:--------"
puts "----------------------------------------------------"