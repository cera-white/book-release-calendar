# frozen_string_literal: true

require "date"
require "digest"
require "time"

# Generates an iCalendar (.ics) feed for manga/light novel release dates.
#
# - All-day events (DTSTART;VALUE=DATE / DTEND;VALUE=DATE)
# - Stable UIDs so Google Calendar subscriptions update events instead of duplicating them
# - Basic escaping + optional line folding for compatibility
#
# Input shape expected (example):
# series = {
#   "title" => "Villains Are Destined to Die",
#   "publisher" => "yen_press",
#   "format" => "paperback",
#   "volumes" => [
#     {"volume" => 1, "title" => "... Vol. 1", "release_date" => "2022-11-08", "url" => "https://..."},
#   ]
# }
#
# release_date may be a Date, or a String parseable by Date.parse, or nil.
class IcsFeedBuilder
  DEFAULT_CALNAME = "Book Releases"

  def initialize(domain:, calname: DEFAULT_CALNAME, prodid: nil)
    @domain = domain.strip
    @calname = calname
    @prodid = prodid || "-//Book Releases//ICS Feed//EN"
  end

  # series_list: Array<Hash> of series, each with "volumes" array
  # options:
  #   include_past: include releases in the past (default: true)
  #   include_nil_dates: include volumes with nil dates (default: false)
  #   tzid: not used for all-day events, but kept for future extension
  def build(series_list, include_past: true, include_nil_dates: false, tzid: nil)
    now_utc = Time.now.utc
    dtstamp = now_utc.strftime("%Y%m%dT%H%M%SZ")

    events = []

    series_list.each do |series|
      series_title = series[:title]
      publisher    = series[:publisher]
      format       = series[:format] || "unknown"

      series[:volumes].each do |v|
        vol_num = v[:volume]
        vol_title = v[:title] || default_volume_title(series_title, vol_num)
        url = v[:url]
        date = coerce_date(v[:release_date])

        next if date.nil? && !include_nil_dates
        next if !include_past && date && date < Date.today

        uid = build_uid(
          publisher: publisher,
          series_title: series_title,
          format: format,
          volume: vol_num
        )

        summary = "#{series_title} — Vol. #{vol_num} (#{format})"
        description = build_description(
          series_title: series_title,
          publisher: publisher,
          format: format,
          volume: vol_num,
          volume_title: vol_title,
          url: url
        )

        events << build_vevent(
          uid: uid,
          dtstamp: dtstamp,
          summary: summary,
          description: description,
          url: url,
          date: date
        )
      end
    end

    # Deterministic ordering keeps diffs stable (nice for debugging)
    events.sort_by! { |e| [e[:date] || Date.new(9999, 12, 31), e[:uid]] }

    assemble_calendar(dtstamp: dtstamp, events: events)
  end

  # Convenience helper: write to disk
  def write(path, series_list, **kwargs)
    content = build(series_list, **kwargs)
    File.write(path, content, mode: "wb")
    path
  end

  private

  def assemble_calendar(dtstamp:, events:)
    lines = []
    lines << "BEGIN:VCALENDAR"
    lines << "VERSION:2.0"
    lines << "PRODID:#{escape_text(@prodid)}"
    lines << "CALSCALE:GREGORIAN"
    lines << "METHOD:PUBLISH"
    lines << "X-WR-CALNAME:#{escape_text(@calname)}"
    lines << "X-WR-TIMEZONE:UTC"

    events.each do |ev|
      lines << "BEGIN:VEVENT"
      lines << "UID:#{escape_text(ev[:uid])}"
      lines << "DTSTAMP:#{dtstamp}"
      lines << "SUMMARY:#{escape_text(ev[:summary])}"
      lines << "DESCRIPTION:#{escape_text(ev[:description])}"
      lines << "URL:#{escape_text(ev[:url])}" if ev[:url] && !ev[:url].to_s.strip.empty?

      if ev[:date]
        # All-day event: DTEND is exclusive, so add 1 day.
        lines << "DTSTART;VALUE=DATE:#{ev[:date].strftime("%Y%m%d")}"
        lines << "DTEND;VALUE=DATE:#{(ev[:date] + 1).strftime("%Y%m%d")}"
      else
        # If you ever include nil dates, you could omit DTSTART/DTEND entirely,
        # but some clients dislike that. Better to skip nil dates by default.
      end

      lines << "END:VEVENT"
    end

    lines << "END:VCALENDAR"

    # Apply line folding (RFC 5545: 75 octets). Google is forgiving, but this helps.
    fold_lines(lines).join("\r\n") + "\r\n"
  end

  def build_vevent(uid:, dtstamp:, summary:, description:, url:, date:)
    { uid: uid, summary: summary, description: description, url: url, date: date }
  end

  def build_uid(publisher:, series_title:, format:, volume:)
    slug = slugify(series_title)
    vol = volume.nil? ? "vol_unknown" : format("vol_%03d", volume.to_i)

    # Your desired shape + domain suffix for global uniqueness:
    # release:publisher:series_slug:format:vol_001@yourdomain.com
    "release:#{publisher}:#{slug}:#{format}:#{vol}@#{@domain}"
  end

  def build_description(series_title:, publisher:, format:, volume:, volume_title:, url:)
    parts = []
    parts << "Series: #{series_title}"
    parts << "Volume: #{volume}" unless volume.nil?
    parts << "Title: #{volume_title}" if volume_title && !volume_title.to_s.strip.empty?
    parts << "Publisher: #{publisher}"
    parts << "Format: #{format}"
    parts << "URL: #{url}" if url && !url.to_s.strip.empty?
    parts.join("\n")
  end

  def default_volume_title(series_title, volume)
    if volume
      "#{series_title}, Vol. #{volume}"
    else
      series_title
    end
  end

  def coerce_date(val)
    return val if val.is_a?(Date)
    return nil if val.nil?

    s = val.to_s.strip
    return nil if s.empty?

    # If it's ISO datetime, Date.parse will handle it.
    Date.parse(s)
  rescue ArgumentError
    nil
  end

  # Lowercase, underscores, strip special chars, collapse underscores.
  # Also replaces '&' with 'and' for nicer slugs.
  def slugify(str)
    s = str.to_s.downcase
    s = s.tr("’'", "")            # remove apostrophes
    s = s.gsub("&", " and ")
    s = s.gsub(/[^a-z0-9]+/, "_") # non-alnum => _
    s = s.gsub(/_+/, "_")
    s = s.gsub(/\A_+|_+\z/, "")
    s
  end

  # iCalendar text escaping: backslash, comma, semicolon, and newlines
  def escape_text(str)
    s = str.to_s
    s = s.gsub("\\", "\\\\")
    s = s.gsub("\r\n", "\n").gsub("\r", "\n")
    s = s.gsub("\n", "\\n")
    s = s.gsub(",", "\\,")
    s = s.gsub(";", "\\;")
    s
  end

  # Fold lines to <= 75 bytes by inserting CRLF + single space.
  # This is a "good enough" implementation for UTF-8 in most cases.
  def fold_lines(lines, max_bytes: 75)
    lines.flat_map do |line|
      bytes = line.encode("UTF-8").bytes
      next [line] if bytes.length <= max_bytes

      chunks = []
      start = 0
      while start < bytes.length
        slice = bytes[start, max_bytes]
        chunks << slice.pack("C*").force_encoding("UTF-8")
        start += max_bytes
      end

      # first line as-is, continuations prefixed with a space
      [chunks[0]] + chunks[1..].map { |c| " #{c}" }
    end
  end
end

# ---- Example usage ----
#
# builder = IcsFeedBuilder.new(domain: "example.com", calname: "Manga Releases")
# builder.write("manga-releases.ics", series_list)