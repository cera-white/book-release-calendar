#!/usr/bin/env ruby
require 'yaml'
require 'json'
require 'net/ftp'
require 'openssl'
require_relative './lib/parsers/yen_press_parser'
require_relative './lib/parsers/seven_seas_parser'
require_relative './lib/parsers/square_enix_parser'
require_relative './lib/parsers/kodansha_parser'
require_relative './lib/parsers/viz_parser'
require_relative './lib/parsers/random_house_parser'
require_relative './lib/ics_feed_builder'

file_path = 'config.yaml'
puts "Loading config from #{file_path}..."
config_data = YAML.safe_load_file(file_path)
puts "Config loaded."

series_list = []

puts "Getting series data..."
config_data['series'].each do |series|
  next if series['status'].to_s.downcase == 'complete'

  case series['publisher']
  when 'yen_press'
    parser = YenPressParser
  when 'seven_seas_entertainment'
    parser = SevenSeasParser
  when 'square_enix'
    parser = SquareEnixParser
  when 'kodansha_international'
    parser = KodanshaParser
  when 'viz_media'
    parser = VizParser
  when 'random_house_worlds'
    parser = RandomHouseParser
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
domain_name = "anigramsproductions.com"
builder = IcsFeedBuilder.new(domain: domain_name, calname: "Book Releases")
builder.write(calendar_file_name, series_list)
puts "Calendar generated at: #{calendar_file_name}"

ftp_host = ENV.fetch("FTP_HOST")
ftp_user = ENV.fetch("FTP_USERNAME")
ftp_pass = ENV.fetch("FTP_PASSWORD")

puts "Connecting to FTP host: #{ftp_host}..."

ctx = OpenSSL::SSL::SSLContext.new
ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
ctx.ca_file = "/etc/ssl/certs/ca-certificates.crt"

ftp = Net::FTP.new(
  ftp_host,
  port: 21,
  ssl: true,
  private_data_connection: true,
  ssl_context: ctx
)

ftp.debug_mode = true

ftp.passive = true
ftp.login(ftp_user, ftp_pass)

puts "Uploading release calendar..."
remote_path = "personal/calendars/#{calendar_file_name}"
ftp.putbinaryfile(calendar_file_name, remote_path)

ftp.close

final_path = "https://#{domain_name}/personal/calendars/#{calendar_file_name}"
puts "Done! Release calendar is now available at: #{final_path}"