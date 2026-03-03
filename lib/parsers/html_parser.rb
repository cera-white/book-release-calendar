require "net/http"
require "uri"
require "nokogiri"

class HtmlParser
  def initialize(url)
    @uri = URI(url)
  end

  def fetch_doc(uri = @uri)
    req = Net::HTTP::Get.new(uri)

    resp = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: 15) do |http|
      http.request(req)
    end

    raise "HTTP #{resp.code}" unless resp.is_a?(Net::HTTPSuccess)
    Nokogiri::HTML(resp.body)
  end

  def parse
    fetch_doc(@uri)
  end
end