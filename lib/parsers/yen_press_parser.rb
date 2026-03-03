require "nokogiri"
require "json"
require "date"
require_relative './html_parser'

class YenPressParser < HtmlParser
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
end