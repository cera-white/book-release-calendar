require "json"
require_relative './html_parser'

class RandomHouseParser < HtmlParser
  # def parse
  #   series_doc = super

  #   File.write('series_html_content.html', series_doc)

  #   series_doc
  # end

  def parse
    doc = super
    volumes = extract_volumes(doc)

    {
      **@series,
      volumes: volumes
    }
  end

  private

  def extract_volumes(doc)
    json_ld_objects(doc).flat_map do |obj|
      extract_books_from_json_ld(obj)
    end
      .select { |book| likely_volume?(book) }
      .map do |book|
        title = book["name"]&.strip
        url   = book["url"]&.strip

        {
          volume: extract_volume_number(title) || safe_integer(book["volumeNumber"]),
          title: title,
          release_date: safe_parse_date(book["datePublished"]),
          url: url
        }
      end
      .reject { |v| v[:title].nil? || v[:title].empty? || v[:url].nil? || v[:url].empty? }
      .uniq { |v| v[:url] }
      .sort_by { |v| [v[:volume] || 9999, v[:title]] }
  end

  def json_ld_objects(doc)
    doc.css('script[type="application/ld+json"]').flat_map do |script|
      raw = script.text.to_s.strip
      next [] if raw.empty?

      parsed = JSON.parse(raw)
      parsed.is_a?(Array) ? parsed : [parsed]
    rescue JSON::ParserError
      []
    end
  end

  def extract_books_from_json_ld(obj)
    case obj
    when Array
      obj.flat_map { |item| extract_books_from_json_ld(item) }
    when Hash
      type = obj["@type"]

      if publication_volume?(type)
        [obj]
      else
        # Walk nested hashes/arrays because PRH sometimes nests Book objects
        obj.values.flat_map { |value| extract_books_from_json_ld(value) }
      end
    else
      []
    end
  end

  def publication_volume?(type)
    case type
    when Array
      type.any? { |t| t.to_s == "PublicationVolume" || t.to_s == "Book" }
    else
      type.to_s == "PublicationVolume"
    end
  end

  def likely_volume?(book)
    title = book["name"].to_s
    volume_num = book["volumeNumber"]

    return true if volume_num
    return true if extract_volume_number(title)

    false
  end

  def safe_parse_date(raw_date)
    return nil if raw_date.nil? || raw_date.to_s.strip.empty?
    Date.parse(raw_date.to_s)
  rescue ArgumentError
    nil
  end

  def safe_integer(value)
    return nil if value.nil?
    Integer(value)
  rescue ArgumentError, TypeError
    nil
  end
end