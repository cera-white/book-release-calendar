require "nokogiri"
require "json"
require "date"
require_relative './html_parser'

class YenPressParser < HtmlParser
  def parse
    series_doc = super
    volumes = extract_volume_links(series_doc)

    volumes.map do |v|
      title_doc_url = URI.join(@uri, v[:url])
      title_doc = fetch_doc(title_doc_url)
      {
        title: v[:title],
        release_date: extract_release_date(title_doc),
        url: title_doc_url.to_s
      }
    end
  end
end