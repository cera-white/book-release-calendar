require "nokogiri"
require "json"
require "date"
require_relative './html_parser'

class SevenSeasParser < HtmlParser
  def initialize(series)
    @series = series
    @uri = URI(series["series_url"])
  end

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
    # Seven Seas series pages list volumes as <a class="series-volume" ...>
    # and include "Release Date" inline in the same anchor. :contentReference[oaicite:1]{index=1}
    doc.css(".volumes-container a.series-volume").map do |a|
      title = a.at_css("h3")&.text&.strip
      href  = a["href"]

      next if title.nil? || title.empty? || href.nil? || href.empty?

      raw_date = extract_release_date_text_from_volume_anchor(a)
      {
        volume: extract_volume_number(title),
        title: title,
        release_date: parse_date_or_nil(raw_date),
        url: href.start_with?("http") ? href : URI.join(@uri, href).to_s
      }
    end.compact
  end

  def extract_release_date_text_from_volume_anchor(a)
    # Pattern in HTML: "<b>Release Date</b>: Sep 27, 2022" :contentReference[oaicite:2]{index=2}
    b = a.xpath(".//b[normalize-space()='Release Date']").first
    return nil unless b

    # Grab the text node right after the <b>Release Date</b>
    # Usually looks like ": Sep 27, 2022 "
    t = b.next_sibling&.text&.strip
    return nil if t.nil? || t.empty?

    t.sub(/\A:\s*/, "").strip
  end

  def parse_date_or_nil(raw_date)
    return nil if raw_date.nil? || raw_date.empty?
    Date.parse(raw_date)
  rescue ArgumentError
    nil
  end
end