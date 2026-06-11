require "json"
require "date"
require "net/http"
require_relative './json_parser'

class KodanshaParser < JsonParser
  SCHEMA_FORMATS = {
    "paperback" => "Paperback",
    "hardcover" => "Hardcover",
    "print" => "Paperback",
    "ebook" => "EBook",
    "digital" => "EBook"
  }.freeze

  def parse
    data = fetch_json(@uri)
    format = @series["format"].to_s.downcase

    volumes = data.map do |item|
      readable_url = item["readableUrl"]
      readable = item["readable"] || {}

      {
        volume: item["volumeNumber"],
        title: item["name"],
        release_date: release_date_for_format(readable_url, readable, format),
        url: build_public_volume_url(readable_url)
      }
    end

    {
      **@series,
      volumes: volumes.compact.sort_by { |v| v[:volume] || 0 }
    }
  end

  private

  def release_date_for_format(readable_url, readable, format)
    schema_format = SCHEMA_FORMATS[format]
    if schema_format && readable_url && !readable_url.to_s.strip.empty?
      date = release_date_from_product_page(readable_url, schema_format)
      return date if date
    end

    fallback_release_date(readable, format)
  end

  def fallback_release_date(readable, format)
    case format
    when "ebook", "digital"
      parse_date_or_nil(readable["digitalReleaseDate"] || readable["releaseDate"])
    when "paperback", "hardcover", "print"
      parse_date_or_nil(readable["printReleaseDate"] || readable["releaseDate"])
    else
      parse_date_or_nil(readable["releaseDate"])
    end
  end

  def release_date_from_product_page(readable_url, schema_format)
    html = fetch_product_page(readable_url)
    return nil if html.nil? || html.empty?

    html.scan(%r{<script type="application/ld\+json"[^>]*>(.*?)</script>}m) do |match|
      data = JSON.parse(match[0])
      next unless data["@type"] == "Book"

      Array(data["workExample"]).each do |example|
        book_format = example["bookFormat"].to_s.split("/").last
        next unless book_format == schema_format

        date = parse_date_or_nil(example["datePublished"])
        return date if date
      end
    end

    nil
  rescue JSON::ParserError
    nil
  end

  def fetch_product_page(readable_url)
    uri = URI("https://kodansha.us/product/#{readable_url}/")
    5.times do
      req = Net::HTTP::Get.new(uri)
      req["User-Agent"] = "Mozilla/5.0 (compatible; BookReleaseCalendar/1.0)"

      resp = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 15) do |http|
        http.request(req)
      end

      return resp.body if resp.is_a?(Net::HTTPSuccess)

      if resp.is_a?(Net::HTTPRedirection)
        uri = URI(resp["location"])
        next
      end

      break
    end

    nil
  end

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