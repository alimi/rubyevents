# Extracts the metadata for a single Luma event listing.
#
# Luma serves the listing as a ProseMirror document embedded in the page, so
# the description arrives as a node tree rather than text. The start time is
# always UTC, which is a day ahead of the local date for any evening meetup
# west of Greenwich, so dates are always resolved in the event's own timezone.
module BmoreOnRails
  class LumaEventMetadata
    class UnparseableLineup < StandardError; end

    BASE_URL = "https://luma.com"
    LINEUP_HEADING = /\Alineup\z/i
    SPEAKER_SEPARATOR = " - "

    Talk = Struct.new(:speaker, :title, :description, keyword_init: true)

    def initialize(payload:, meetup_name:)
      @payload = payload
      @meetup_name = meetup_name
    end

    def date
      starts_at.to_date.iso8601
    end

    # Luma listings are named per edition ("Open Hack Night | B'more on Rails"),
    # so the name carries more than a generated title would and is kept as is.
    def title
      event["name"]
    end

    # The label for this edition of the meetup. Meetups are a single Event
    # covering every edition, so this is what tells the two apart in the UI.
    def event_name
      "#{@meetup_name} - #{starts_at.strftime("%B %Y")}"
    end

    # Editions repeat their titles - "B'more on Rails Presents: Your Talks!"
    # comes round every few months - so the month is part of the slug. Left to
    # itself the site would resolve the clash by appending the event name or
    # the language, picking a rung by whichever edition it saw first.
    def slug
      "#{title} #{starts_at.strftime("%B %Y")}".parameterize
    end

    # RubyEvents is the archive; Luma is where the event actually lives and
    # where people RSVP, so the listing url leads.
    def description
      [url, flattened_description].compact_blank.join("\n\n")
    end

    def url
      "#{BASE_URL}/#{event["url"]}"
    end

    # Talk nights list their speakers under a "Lineup" heading, one paragraph
    # per talk, opening with a bold "Speaker - Title" run followed by the talk
    # description. The bold run is what marks a paragraph as a talk: every
    # lineup also ends with unbolded prose asking for more speakers.
    def talks
      @talks ||= lineup_paragraphs.filter_map do |node|
        headline = bold_text(node).strip
        next if headline.blank?

        speaker, title = headline.split(SPEAKER_SEPARATOR, 2)

        if title.blank?
          raise UnparseableLineup,
            "Could not tell the speaker from the title in #{url}: #{headline.inspect}. " \
            "Lineup entries are expected to read \"Speaker#{SPEAKER_SEPARATOR}Title\"."
        end

        Talk.new(speaker: speaker.strip, title: title.strip, description: plain_text(node).strip)
      end
    end

    private

    def event
      @payload["event"] || {}
    end

    def starts_at
      Time.parse(event["start_at"]).in_time_zone(event["timezone"])
    end

    def flattened_description
      blocks(@payload["description_mirror"]).join("\n\n")
    end

    # Each top level node of the document becomes one block of text. Only the
    # blocks are stripped - inline runs carry the spacing that separates them
    # from their neighbours, so trimming them would run the words together.
    def blocks(node)
      Array(node&.dig("content")).filter_map { |child| text_of(child).strip.presence }
    end

    def text_of(node)
      case node
      when Hash then [linked_text(node), *node["content"]&.map { |child| text_of(child) }].join
      when Array then node.map { |child| text_of(child) }.join
      end.to_s
    end

    # Descriptions are stored as plain text, so a link's destination has to sit
    # next to its label or it is lost - "installation guide" on its own is no
    # use to anyone. Bare urls are left alone rather than repeated, and the
    # site turns them into links when it renders the description.
    def linked_text(node)
      text = node["text"].to_s
      href = Array(node["marks"]).find { |mark| mark["type"] == "link" }&.dig("attrs", "href")

      return text if text.blank? || href.blank? || text.strip.start_with?("http")

      "#{text.strip} (#{href})#{" " if text.end_with?(" ")}"
    end

    # The paragraphs between the "Lineup" heading and whatever heading follows.
    def lineup_paragraphs
      nodes = Array(@payload.dig("description_mirror", "content"))
      start = nodes.index { |node| node["type"] == "heading" && text_of(node).strip.match?(LINEUP_HEADING) }
      return [] if start.nil?

      nodes[(start + 1)..].take_while { |node| node["type"] != "heading" }
    end

    def bold_text(node)
      runs_of(node, bold: true)
    end

    def plain_text(node)
      runs_of(node, bold: false)
    end

    def runs_of(node, bold:)
      Array(node["content"]).filter_map { |run|
        marks = Array(run["marks"]).map { |mark| mark["type"] }
        run["text"] if marks.include?("bold") == bold
      }.join
    end
  end
end
