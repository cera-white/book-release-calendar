require "json"
require "date"
require "nokogiri"
require_relative "./html_parser"

class KodanshaParser < HtmlParser
  OMOI_VOLUMES_BASE = "https://www.omoi.com/series".freeze
  KODANSHA_API_BASE = "https://kodansha.us/wp-json/kodansha/v1".freeze
  RELEASE_FEED_URL = "https://kodansha.us/feed/release-calendar/".freeze
  WAYBACK_AVAILABILITY_URL = "https://archive.org/wayback/available".freeze
  JINA_READER_PREFIX = "https://r.jina.ai/".freeze

  SCHEMA_FORMATS = {
    "paperback" => "Paperback",
    "hardcover" => "Hardcover",
    "print" => "Paperback",
    "ebook" => "EBook",
    "digital" => "EBook"
  }.freeze

  PRINT_FEED_CATEGORIES = ["Print", "Print & Digital"].freeze
  DIGITAL_FEED_CATEGORIES = ["Digital", "Print & Digital"].freeze

  def initialize(series)
    super
    # Kodansha series pages 301 without a trailing slash.
    @uri.path = "#{@uri.path}/" unless @uri.path.end_with?("/")
  end

  def parse
    slug = series_slug
    format = @series["format"].to_s.downcase
    schema_format = SCHEMA_FORMATS[format]
    release_dates = build_release_date_index(format)

    volumes = volumes_from_omoi(slug).map do |v|
      release_date = release_dates[v[:url]]
      release_date ||= release_date_from_volume_sources(v[:url], schema_format)

      {
        volume: v[:volume],
        title: v[:title],
        release_date: release_date,
        url: v[:url]
      }
    end

    {
      **@series,
      volumes: volumes.compact.sort_by { |vol| vol[:volume] || 0 }
    }
  end

  private

  def series_slug
    parts = @uri.path.split("/").reject(&:empty?)
    raise "Could not determine Kodansha series slug from #{@uri}" unless parts[0] == "series" && parts[1]

    parts[1]
  end

  def volumes_from_omoi(slug)
    uri = URI("#{OMOI_VOLUMES_BASE}/#{slug}/volumes")
    doc = fetch_doc(uri)
    volumes = volumes_from_json_ld(doc, slug)
    raise "No volumes found for Kodansha series #{slug}" if volumes.empty?

    volumes
  end

  def volumes_from_json_ld(doc, slug)
    doc.css('script[type="application/ld+json"]').each do |script|
      data = JSON.parse(script.text)
      next unless data.is_a?(Hash) && data["@type"] == "ComicSeries"

      return Array(data["hasPart"]).filter_map do |part|
        next unless part.is_a?(Hash)

        title = part["name"].to_s.strip
        volume = part["position"] || extract_volume_number(title)
        next if title.empty? || volume.nil?

        {
          volume: volume,
          title: title,
          url: kodansha_volume_url(slug, volume)
        }
      end
    rescue JSON::ParserError
      next
    end

    []
  end

  def kodansha_volume_url(slug, volume)
    "https://kodansha.us/series/#{slug}/volume-#{volume}/"
  end

  def build_release_date_index(format)
    index = {}
    merge_api_release_dates(index, format)
    merge_rss_release_dates(index, format)
    index
  end

  def merge_api_release_dates(index, format)
    merge_new_releases(index, format)
    merge_release_calendar(index)
  end

  def merge_new_releases(index, format)
    body = fetch_text(URI("#{KODANSHA_API_BASE}/new-releases"))
    return unless body

    data = JSON.parse(body)["data"]
    return unless data.is_a?(Array)

    data.each do |item|
      next unless release_item_matches_format?(item, format)

      url = item["volume_url"].to_s.strip
      date = parse_date_or_nil(item["release_date"])
      index[url] = date if url && date
    end
  rescue JSON::ParserError
    nil
  end

  def merge_release_calendar(index)
    body = fetch_text(URI("#{KODANSHA_API_BASE}/release-calendar"))
    return unless body

    data = JSON.parse(body)["data"]
    return unless data.is_a?(Array)

    data.each do |week|
      week_date = parse_date_or_nil(week["tue_key"])
      next unless week_date

      Array(week["items"]).each do |item|
        url = item["volume_url"].to_s.strip
        index[url] ||= week_date if url
      end
    end
  rescue JSON::ParserError
    nil
  end

  def merge_rss_release_dates(index, format)
    body = fetch_text(URI(RELEASE_FEED_URL))
    return unless body

    doc = Nokogiri::XML(body)
    doc.css("item").each do |item|
      category = item.at_css("category")&.text.to_s.strip
      next unless rss_category_matches_format?(category, format)

      url = item.at_css("link")&.text.to_s.strip
      pub_date = item.at_css("pubDate")&.text.to_s.strip
      date = parse_date_or_nil(pub_date)
      index[url] ||= date if url && date
    end
  end

  def release_item_matches_format?(item, format)
    case format
    when "paperback", "hardcover", "print"
      item["has_print"] == true
    when "ebook", "digital"
      true
    else
      true
    end
  end

  def rss_category_matches_format?(category, format)
    case format
    when "paperback", "hardcover", "print"
      PRINT_FEED_CATEGORIES.include?(category)
    when "ebook", "digital"
      DIGITAL_FEED_CATEGORIES.include?(category)
    else
      true
    end
  end

  def release_date_from_volume_sources(volume_url, schema_format)
    return nil if schema_format.nil?

    uri = URI(volume_url)
    body = fetch_text(uri)
    if body
      date = release_date_from_volume_page(Nokogiri::HTML(body), schema_format)
      return date if date
    end

    date = release_date_from_wayback(volume_url, schema_format)
    return date if date

    release_date_from_jina_reader(volume_url, schema_format)
  end

  def release_date_from_wayback(volume_url, schema_format)
    snapshot_url = wayback_snapshot_url(volume_url)
    return nil unless snapshot_url

    body = fetch_text(URI(snapshot_url))
    return nil unless body

    release_date_from_volume_page(Nokogiri::HTML(body), schema_format)
  end

  def wayback_snapshot_url(original_url)
    query = URI.encode_www_form(url: original_url)
    body = fetch_text(URI("#{WAYBACK_AVAILABILITY_URL}?#{query}"))
    return nil unless body

    data = JSON.parse(body)
    closest = data.dig("archived_snapshots", "closest")
    return nil unless closest.is_a?(Hash) && closest["available"]

    snapshot_url = closest["url"].to_s.strip
    snapshot_url.sub("http://web.archive.org", "https://web.archive.org")
  rescue JSON::ParserError
    nil
  end

  def release_date_from_jina_reader(volume_url, schema_format)
    return nil if schema_format.nil?

    label = schema_format == "Paperback" ? "Print Release" : "Digital Release"
    reader_url = "#{JINA_READER_PREFIX}#{volume_url}"
    body = fetch_text(URI(reader_url))
    return nil unless body

    match = body.match(/#{Regexp.escape(label)}\s+(\d{1,2}\/\d{1,2}\/\d{4})/i)
    return nil unless match

    Date.strptime(match[1], "%m/%d/%Y")
  rescue ArgumentError
    nil
  end

  def release_date_from_volume_page(doc, schema_format)
    doc.css('script[type="application/ld+json"]').each do |script|
      data = JSON.parse(script.text)
      next unless data.is_a?(Hash) && data["@type"] == "Book"

      Array(data["workExample"]).each do |example|
        next unless example.is_a?(Hash)

        book_format = example["bookFormat"].to_s.split("/").last
        next unless book_format == schema_format

        date = parse_date_or_nil(example["datePublished"])
        return date if date
      end
    rescue JSON::ParserError
      next
    end

    nil
  end

  def parse_date_or_nil(raw)
    return nil if raw.nil?

    s = raw.to_s.strip
    return nil if s.empty? || s.start_with?("0001-01-01")

    Date.parse(s)
  rescue ArgumentError
    nil
  end
end
