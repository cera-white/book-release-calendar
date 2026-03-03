require "nokogiri"
require "json"
require "date"
require_relative './html_parser'

# class SquareEnixParser < HtmlParser
#   def initialize(series)
#     @series = series
#     @uri = URI(series['series_url'])
#   end

#   def parse
#     series_doc = super

#     File.write('series_html_content.html', series_doc)

#     series_doc
#   end
# end

class SquareEnixParser < HtmlParser
  def parse
    series_doc = super
    volumes = extract_volume_links(series_doc)

    volumes = volumes.map do |v|
      product_url = URI.join(@uri, v[:url])
      product_doc = fetch_doc(product_url)

      {
        volume: extract_volume_number(v[:title]),
        title: v[:title],
        release_date: extract_release_date(product_doc),
        url: product_url.to_s,
      }
    end

    {
      **@series,
      volumes: volumes
    }
  end

  private

  def extract_volume_links(doc)
    # Series page volume cards are anchors pointing at /en-us/product/<isbn>
    # with the title text in a nested <div class="p-1">Title</div>.
    doc.css("a[href^='/en-us/product/']").map do |a|
      title = a.at_css("div.p-1")&.text&.strip
      href  = a["href"]

      next if title.nil? || title.empty? || href.nil? || href.empty?
      { title: title, url: href }
    end.compact.uniq { |v| v[:url] }
  end

  def extract_release_date(doc)
    # Product pages include a field like: "release date:December 8, 2020" :contentReference[oaicite:4]{index=4}
    # We’ll locate an element whose *text* starts with "release date:" (case-insensitive)
    node = doc.xpath(
      "//*[starts-with(translate(normalize-space(.), " \
      "'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), 'release date:')]"
    ).first

    return nil unless node

    raw = node.text.strip
    raw_date = raw.sub(/\Arelease date:\s*/i, "").strip
    return nil if raw_date.empty?

    Date.parse(raw_date)
  rescue ArgumentError
    nil
  end
end