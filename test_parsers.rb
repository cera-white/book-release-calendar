#!/usr/bin/env ruby
require 'yaml'
require_relative './lib/parsers/yen_press_parser'
require_relative './lib/parsers/seven_seas_parser'
require_relative './lib/parsers/square_enix_parser'
require_relative './lib/parsers/kodansha_parser'

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
puts SevenSeasParser.new(seven_seas_example).parse.to_json
puts "----------------------------------------------------"

puts "--------Square Enix Example:--------"
square_enix_example = config_data['series'][3]
puts square_enix_example
puts "--------Output:--------"
puts SquareEnixParser.new(square_enix_example).parse.to_json
puts "----------------------------------------------------"

puts "--------Kodansha Example:--------"
kodansha_example = config_data['series'][5]
puts kodansha_example
puts "--------Output:--------"
puts KodanshaParser.new(kodansha_example).parse.to_json
puts "----------------------------------------------------"
