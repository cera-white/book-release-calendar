require "json"
require "date"
require "cgi"
require "net/http"
require "uri"
require_relative "./html_parser"

class SevenSeasParser < HtmlParser
  API_BASE = "https://sevenseasentertainment.com/wp-json/wp/v2".freeze
  RELEASE_SCHEDULE_URL = "https://sevenseasentertainment.com/release-dates/".freeze
  JINA_READER_PREFIX = "https://r.jina.ai/".freeze

  class << self
    def release_schedule_index
      @release_schedule_index ||= build_release_schedule_index
    end

    def reset_release_schedule_index!
      @release_schedule_index = nil
    end

    private

    def build_release_schedule_index
      body = new({ "series_url" => RELEASE_SCHEDULE_URL }).send(:fetch_text, URI(RELEASE_SCHEDULE_URL))
      return {} unless body

      index = {}
      body.scan(%r{(\d{4}-\d{2}-\d{2})</td>.*?/books/([^/]+)/}m) do |date_str, book_slug|
        index[book_slug] = Date.parse(date_str)
      rescue ArgumentError
        next
      end
      index
    end
  end

  def parse
    slug = series_slug
    prefix = volume_slug_prefix(slug)
    schedule = self.class.release_schedule_index

    volumes = discover_volumes(prefix).map do |book|
      release_date = schedule[book[:slug]]
      release_date ||= release_date_from_jina(book[:url])

      {
        volume: book[:volume],
        title: book[:title],
        release_date: release_date,
        url: book[:url]
      }
    end

    {
      **@series,
      volumes: volumes.sort_by { |v| v[:volume] || 0 }
    }
  end

  private

  def series_slug
    parts = @uri.path.split("/").reject(&:empty?)
    raise "Could not determine Seven Seas series slug from #{@uri}" unless parts[0] == "series" && parts[1]

    parts[1]
  end

  def volume_slug_prefixes(slug)
    if slug.end_with?("-manga")
      ["#{slug}-vol-"]
    else
      ["#{slug}-vol-", "#{slug}-manga-vol-"]
    end
  end

  def volume_slug_prefix(slug)
    volume_slug_prefixes(slug).each do |prefix|
      return prefix if fetch_book_record("#{prefix}1")
    end

    raise "No Seven Seas volumes found for series slug #{slug}"
  end

  def discover_volumes(prefix)
    volumes = []
    n = 1

    loop do
      book = fetch_book_record("#{prefix}#{n}")
      break unless book

      volumes << book.merge(volume: n)
      n += 1
    end

    volumes
  end

  def fetch_book_record(volume_slug)
    query = URI.encode_www_form(slug: volume_slug)
    body = fetch_json_text(URI("#{API_BASE}/books?#{query}"))
    return nil unless body

    data = JSON.parse(body)
    return nil unless data.is_a?(Array) && data.any?

    book = data.first
    {
      slug: book["slug"].to_s,
      title: decode_html_entities(book.dig("title", "rendered").to_s),
      url: book["link"].to_s
    }
  rescue JSON::ParserError
    nil
  end

  def decode_html_entities(text)
    return text if text.empty?

    CGI.unescapeHTML(text)
  end

  def fetch_json_text(uri)
    sleep(rand(0.5..1.5))

    req = Net::HTTP::Get.new(uri)
    req["User-Agent"] = USER_AGENT
    req["Accept"] = "application/json"

    resp = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: 15) do |http|
      http.request(req)
    end

    return nil unless resp.is_a?(Net::HTTPSuccess)

    resp.body
  rescue StandardError
    nil
  end

  def release_date_from_jina(book_url, retries: 2)
    retries.times do
      body = fetch_text(URI("#{JINA_READER_PREFIX}#{book_url}"))
      next unless body

      match = body.match(/Release Date:\**\s*([A-Za-z]+\s+\d{1,2},\s+\d{4})/i)
      next unless match

      return Date.parse(match[1])
    end

    nil
  rescue ArgumentError
    nil
  end
end
