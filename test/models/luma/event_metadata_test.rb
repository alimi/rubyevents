require "test_helper"

module Luma
  class EventMetadataTest < ActiveSupport::TestCase
    test "uses the date in the event's own timezone, not the UTC date" do
      # 00:00 UTC is still the previous evening in New York
      metadata = build(start_at: "2025-12-12T00:00:00.000Z", timezone: "America/New_York")

      assert_equal "2025-12-11", metadata.date
    end

    test "uses the UTC date when the timezones happen to agree" do
      metadata = build(start_at: "2026-08-13T23:00:00.000Z", timezone: "America/New_York")

      assert_equal "2026-08-13", metadata.date
    end

    test "titles the edition with the Luma name, verbatim" do
      metadata = build(name: "Bring Your Own Tokens Hack Night | B'more on Rails")

      assert_equal "Bring Your Own Tokens Hack Night | B'more on Rails", metadata.title
    end

    test "names the edition after the meetup and month" do
      metadata = build(start_at: "2026-08-13T23:00:00.000Z", meetup_name: "B'more on Rails")

      assert_equal "B'more on Rails - August 2026", metadata.event_name
    end

    test "names the edition by its local month, not the UTC one" do
      # 00:00 UTC on 1 January is still December in New York
      metadata = build(start_at: "2026-01-01T00:00:00.000Z", meetup_name: "B'more on Rails")

      assert_equal "B'more on Rails - December 2025", metadata.event_name
    end

    test "flattens the description and leads with the Luma url" do
      metadata = EventMetadata.new(payload: fixture("cja7x708"), meetup_name: "B'more on Rails")

      assert_match(/we're gonna have a Hack Night unlike any other/, metadata.description)
      assert_match(%r{Thanks to our sponsor EcoMap \(https://ecomap\.tech/\) for providing the space},
        metadata.description)
      assert_match(%r{\Ahttps://luma\.com/cja7x708}, metadata.description)
    end

    test "keeps the destination of a link alongside its text" do
      metadata = EventMetadata.new(payload: fixture("yh4b1tqi"), meetup_name: "B'more on Rails")

      assert_match(%r{installation guide \(https://www\.ruby-lang\.org/en/documentation/installation/\)},
        metadata.description)
      assert_match(%r{EcoMap \(https://ecomap\.tech/\)}, metadata.description)
    end

    test "keeps a link whose text also appears inside its url" do
      metadata = EventMetadata.new(payload: fixture("cbhwa7rj"), meetup_name: "B'more on Rails")

      assert_match(%r{code\.golf \(https://code\.golf\)}, metadata.description)
      assert_match(%r{tutorial \(https://code\.golf/tutorial\#ruby\)}, metadata.description)
      assert_match(%r{wiki \(https://code\.golf/wiki\)}, metadata.description)
    end

    test "does not repeat a link whose text is already the url" do
      metadata = EventMetadata.new(payload: fixture("yh4b1tqi"), meetup_name: "B'more on Rails")

      assert_no_match(%r{anti_harassment_policy\.md \(http}, metadata.description)
    end

    test "keeps the description's section headings" do
      metadata = EventMetadata.new(payload: fixture("h5b3rmif"), meetup_name: "B'more on Rails")

      assert_match(/^Lineup$/, metadata.description)
      assert_match(/^Sponsors$/, metadata.description)
    end

    test "has no talks when the listing has no lineup" do
      metadata = EventMetadata.new(payload: fixture("cja7x708"), meetup_name: "B'more on Rails")

      assert_empty metadata.talks
    end

    test "reads the talks out of the lineup" do
      metadata = EventMetadata.new(payload: fixture("h5b3rmif"), meetup_name: "B'more on Rails")

      assert_equal ["Rosanna Speller", "Gary Moore", "Matt Scilipoti"], metadata.talks.map(&:speaker)
      assert_equal "What time is it?", metadata.talks.first.title
      assert_match(/dealing with dates, times, and time zones/, metadata.talks.first.description)
    end

    test "keeps a title containing a dash intact" do
      metadata = build(lineup: ["Gary Moore - Comparing traditional ML - a deep dive"])

      assert_equal "Gary Moore", metadata.talks.first.speaker
      assert_equal "Comparing traditional ML - a deep dive", metadata.talks.first.title
    end

    test "ignores lineup prose that is not a talk" do
      # every lineup ends with an unbolded call for more speakers
      metadata = EventMetadata.new(payload: fixture("h5b3rmif"), meetup_name: "B'more on Rails")

      assert_equal 3, metadata.talks.length
      assert_no_match(/drop us a message/, metadata.talks.map(&:title).join)
    end

    test "refuses to guess when a lineup entry has no speaker separator" do
      metadata = build(lineup: ["Rosanna Speller — What time is it?"])

      error = assert_raises(EventMetadata::UnparseableLineup) { metadata.talks }
      assert_match(/Rosanna Speller/, error.message)
    end

    test "builds a slug from the title and the edition's month" do
      metadata = build(name: "B'more on Rails Presents: Your Talks!", start_at: "2025-12-12T00:00:00.000Z")

      assert_equal "b-more-on-rails-presents-your-talks-december-2025", metadata.slug
    end

    test "builds a slug that survives punctuation and emoji" do
      metadata = build(name: "B'more on Rails Goes Golfing 🏌️", start_at: "2026-05-14T23:00:00.000Z")

      assert_equal "b-more-on-rails-goes-golfing-may-2026", metadata.slug
    end

    test "exposes the luma url" do
      metadata = build(url: "cja7x708")

      assert_equal "https://luma.com/cja7x708", metadata.url
    end

    private

    def fixture(slug)
      JSON.parse(file_fixture("luma/#{slug}.json").read)
    end

    def build(start_at: "2026-08-13T23:00:00.000Z", timezone: "America/New_York",
      name: "Bring Your Own Tokens Hack Night | B'more on Rails", url: "cja7x708",
      meetup_name: "B'more on Rails", lineup: nil)
      payload = {
        "event" => {
          "name" => name,
          "start_at" => start_at,
          "timezone" => timezone,
          "url" => url
        },
        "description_mirror" => {"type" => "doc", "content" => lineup ? lineup_nodes(lineup) : []}
      }

      EventMetadata.new(payload: payload, meetup_name: meetup_name)
    end

    def lineup_nodes(bold_runs)
      heading = {"type" => "heading", "attrs" => {"level" => 2},
                 "content" => [{"type" => "text", "text" => "Lineup"}]}

      [heading] + bold_runs.map do |run|
        {"type" => "paragraph", "content" => [
          {"type" => "text", "text" => "#{run} ", "marks" => [{"type" => "bold"}]},
          {"type" => "text", "text" => "Some description."}
        ]}
      end
    end
  end
end
