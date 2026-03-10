require "json"
require "date"
require_relative './json_parser'

class KodanshaParser < JsonParser
  def parse
    data = fetch_json(@uri)

    volumes = data.map do |item|
      # item["readable"]["releaseDate"] is like "2025-05-27T00:00:00"
      raw_release = item.dig("readable", "releaseDate")

      {
        volume: item["volumeNumber"],
        title: item["name"],
        release_date: parse_date_or_nil(raw_release),
        url: build_public_volume_url(item["readableUrl"])
      }
    end

    {
      **@series,
      volumes: volumes.compact.sort_by { |v| v[:volume] || 0 }
    }
  end

  private

  def parse_date_or_nil(raw)
    return nil if raw.nil?
    s = raw.to_s.strip
    return nil if s.empty? || s.start_with?("0001-01-01") # shows up in some nested chapter readables

    # We only care about the date, not the time
    Date.parse(s)
  rescue ArgumentError
    nil
  end

  def build_public_volume_url(readable_url)
    return nil if readable_url.nil? || readable_url.to_s.strip.empty?

    "https://kodansha.us/product/#{readable_url}"
  end
end