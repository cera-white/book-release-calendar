require "json"
require "date"
require_relative './html_parser'

class KodanshaParser < HtmlParser
  SCHEMA_FORMATS = {
    "paperback" => "Paperback",
    "hardcover" => "Hardcover",
    "print" => "Paperback",
    "ebook" => "EBook",
    "digital" => "EBook"
  }.freeze

  def initialize(series)
    super
    # Kodansha series pages 301 without a trailing slash.
    @uri.path = "#{@uri.path}/" unless @uri.path.end_with?("/")
  end

  def parse
    series_doc = super
    format = @series["format"].to_s.downcase
    schema_format = SCHEMA_FORMATS[format]

    volumes = extract_volume_links(series_doc).map do |v|
      volume_doc = fetch_doc(URI(v[:url]))
      {
        volume: v[:volume],
        title: v[:title],
        release_date: release_date_from_volume_page(volume_doc, schema_format),
        url: v[:url]
      }
    end

    {
      **@series,
      volumes: volumes.compact.sort_by { |v| v[:volume] || 0 }
    }
  end

  private

  def extract_volume_links(doc)
    volumes = volumes_from_json_ld(doc)
    return volumes unless volumes.empty?

    volumes_from_anchors(doc)
  end

  def volumes_from_json_ld(doc)
    doc.css('script[type="application/ld+json"]').each do |script|
      data = JSON.parse(script.text)
      next unless data.is_a?(Hash) && data["@type"] == "ComicSeries"

      return Array(data["hasPart"]).filter_map do |part|
        next unless part.is_a?(Hash)

        url = part["url"].to_s.strip
        title = part["name"].to_s.strip
        next if url.empty? || title.empty?

        {
          volume: part["position"] || extract_volume_number(title),
          title: title,
          url: url
        }
      end
    rescue JSON::ParserError
      next
    end

    []
  end

  def volumes_from_anchors(doc)
    seen = {}
    doc.css('a[href*="/volume-"]').filter_map do |a|
      href = a["href"].to_s.strip
      next if href.empty? || href.include?("#")

      url = href.start_with?("http") ? href : URI.join(@uri, href).to_s
      next if seen[url]

      title = a.text.gsub(/\s+/, " ").strip
      title = File.basename(URI(url).path) if title.empty?
      seen[url] = true

      {
        volume: extract_volume_number(title) || extract_volume_number(url),
        title: title,
        url: url
      }
    end
  end

  def release_date_from_volume_page(doc, schema_format)
    return nil if schema_format.nil?

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
