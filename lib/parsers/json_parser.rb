require "json"
require "net/http"
require "uri"

class JsonParser
  def initialize(series)
    @series = series
    @uri = URI(series['api_url'])
  end

  def fetch_json(uri)
    req = Net::HTTP::Get.new(uri)
    req["Accept"] = "application/json"

    resp = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: 15) do |http|
      http.request(req)
    end

    raise "HTTP #{resp.code}, Response: #{resp.inspect}" unless resp.is_a?(Net::HTTPSuccess)
    JSON.parse(resp.body)
  end

  def parse
    fetch_json(@uri)
  end
end