require "nokogiri"
require "json"
require "date"
require_relative './html_parser'

class YenPressParser < HtmlParser
  def initialize(series)
    @series = series
    @uri = URI(series['series_url'])
  end

  def parse
    series_doc = super
    volumes = extract_volume_links(series_doc)

    volumes = volumes.map do |v|
      title_doc_url = URI.join(@uri, v[:url])
      title_doc = fetch_doc(title_doc_url)
      {
        volume: extract_volume_number(v[:title]),
        title: v[:title],
        release_date: extract_release_date(title_doc),
        url: title_doc_url.to_s,
      }
    end

    {
      **@series,
      volumes: volumes
    }
  end

  private

  def extract_volume_links(doc)
    container = doc.at_css("#volumes-list")
    return [] unless container

    container.css("a.hovered-shadow").map do |a|
      title = a.at_css("p span")&.text&.strip
      href  = a["href"]
      next if title.nil? || title.empty? || href.nil? || href.empty?
      { title: title, url: href }
    end.compact
  end

  def extract_release_date(doc)
    # Find an element whose text is exactly "Release Date"
    label = doc.xpath("//*[normalize-space()='Release Date']").first
    return nil unless label

    # In Yen Press title pages, the value is typically the next element sibling
    # e.g., <div>Release Date</div><div>Nov 18, 2025</div>
    value_el = label.xpath("following-sibling::*[1]").first

    # If they wrap it differently (common), walk up to a container and grab the next block
    if value_el.nil? || value_el.text.strip.empty?
      container = label.parent
      value_el = container&.xpath("./*[position()=2]")&.first
    end

    raw_date = value_el&.text&.strip
    return nil if raw_date.nil? || raw_date.empty?

    parsed_date = Date.parse(raw_date)

    parsed_date
  rescue ArgumentError
    nil
  end

  def extract_volume_number(title)
    return nil if title.nil?

    t = title.strip

    # Most common: "Vol. 8" / "Vol 8" / "Volume 8"
    if (m = t.match(/\bvol(?:ume)?\.?\s*(\d{1,3})\b/i))
      return m[1].to_i
    end

    # Sometimes: "Book 8" / "Bk. 8"
    if (m = t.match(/\b(?:book|bk)\.?\s*(\d{1,3})\b/i))
      return m[1].to_i
    end

    # Sometimes: "#8" (less common for volumes, more for issues/chapters)
    if (m = t.match(/(?:^|[^\d])#\s*(\d{1,3})\b/))
      return m[1].to_i
    end

    nil
  end
end