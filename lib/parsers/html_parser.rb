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

    raise "HTTP #{resp.code}, Response: #{resp.inspect}" unless resp.is_a?(Net::HTTPSuccess)
    Nokogiri::HTML(resp.body)
  end

  def parse
    fetch_doc(@uri)
  end

  private

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