require_relative './html_parser'

class VizParser < HtmlParser
  # def parse
  #   series_doc = super

  #   File.write('series_html_content.html', series_doc)

  #   series_doc
  # end

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
    doc.css(".shelf article a.color-off-black[href]").map do |link|
      title = link.text&.strip
      href  = link["href"]&.strip
      next if title.nil? || title.empty? || href.nil? || href.empty?
      { title: title, url: href }
    end.compact.uniq { |v| v[:url] }
  end

  def extract_release_date(doc)
    # Strategy 1:
    # Look for a label/value pair where the label text is "Release Date" or "Release date"
    label = doc.xpath("//*[normalize-space()='Release Date' or normalize-space()='Release date']").first
    if label
      value_el = label.xpath("following-sibling::*[1]").first

      if value_el.nil? || value_el.text.strip.empty?
        parent = label.parent
        value_el = parent&.xpath("./*[position()=2]")&.first
      end

      raw_date = value_el&.text&.strip
      parsed = safe_parse_date(raw_date)
      return parsed if parsed
    end

    # Strategy 2:
    # Search for common product-detail rows where a label and value are grouped together.
    # This is intentionally flexible because VIZ markup may vary.
    doc.css("*").each do |node|
      text = node.text.to_s.strip
      next unless text.match?(/\ARelease\s+Date\z/i)

      sibling = node.xpath("following-sibling::*[1]").first
      parsed = safe_parse_date(sibling&.text&.strip)
      return parsed if parsed

      parent = node.parent
      if parent
        children = parent.element_children
        idx = children.index(node)
        if idx && children[idx + 1]
          parsed = safe_parse_date(children[idx + 1].text&.strip)
          return parsed if parsed
        end
      end
    end

    # Strategy 3:
    # Sometimes the date may appear in structured metadata or generic text blocks.
    possible_dates = doc.xpath("//text()")
      .map(&:text)
      .map(&:strip)
      .reject(&:empty?)
      .select { |t| t.match?(/\A[A-Z][a-z]{2,8}\s+\d{1,2},\s+\d{4}\z/) }

    possible_dates.each do |raw_date|
      parsed = safe_parse_date(raw_date)
      return parsed if parsed
    end

    nil
  end

  def safe_parse_date(raw_date)
    return nil if raw_date.nil? || raw_date.empty?
    Date.parse(raw_date)
  rescue ArgumentError
    nil
  end
end