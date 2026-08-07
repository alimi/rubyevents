require "test_helper"

class BmoreOnRails::EventImportTest < ActiveSupport::TestCase
  setup do
    @destination = Dir.mktmpdir("bmore_on_rails", Rails.root.join("tmp").to_s)

    # The talk id validator only exempts meetups from the Talk::StaticID
    # naming convention when it can see the event is one.
    FileUtils.mkdir_p(File.dirname(videos_file_path))
    FileUtils.cp(
      Rails.root.join("data/bmore-on-rails/bmore-on-rails-meetup/event.yml"),
      File.dirname(videos_file_path)
    )
  end

  teardown { FileUtils.remove_entry(@destination) }

  test "gives the edition an id matching the meetup convention" do
    import("cja7x708")

    assert_equal ["bmore-on-rails-meetup-2026-08-13"], videos_file.ids
  end

  test "keeps video_id in step with the id" do
    import("cja7x708")

    assert_equal "bmore-on-rails-meetup-2026-08-13", entry["video_id"]
  end

  test "titles the edition with the Luma name" do
    import("cja7x708")

    assert_equal "Bring Your Own Tokens Hack Night | B'more on Rails", entry["title"]
  end

  test "names the edition after the meetup and month" do
    import("cja7x708")

    assert_equal "B'more on Rails - August 2026", entry["event_name"]
  end

  test "keeps the edition name when imported again" do
    import("cja7x708")
    import("cja7x708")

    assert_equal "B'more on Rails - August 2026", entry["event_name"]
  end

  test "marks an upcoming edition as scheduled" do
    # cja7x708 is 2026-08-13
    travel_to(Date.new(2026, 8, 1)) { import("cja7x708") }

    assert_equal "scheduled", entry["video_provider"]
  end

  test "marks an edition happening today as scheduled" do
    travel_to(Date.new(2026, 8, 13)) { import("cja7x708") }

    assert_equal "scheduled", entry["video_provider"]
  end

  test "marks a past edition as not recorded" do
    travel_to(Date.new(2026, 8, 14)) { import("cja7x708") }

    assert_equal "not_recorded", entry["video_provider"]
  end

  test "flips an edition to not recorded once its date has passed" do
    travel_to(Date.new(2026, 8, 1)) { import("cja7x708") }
    travel_to(Date.new(2026, 9, 1)) { import("cja7x708") }

    assert_equal 1, videos_file.count
    assert_equal "not_recorded", entry["video_provider"]
  end

  test "leaves a recording provider set by hand alone" do
    travel_to(Date.new(2026, 8, 1)) { import("cja7x708") }

    file = videos_file
    file.find_by(id: "bmore-on-rails-meetup-2026-08-13")["video_provider"] = "youtube"
    file.save!

    travel_to(Date.new(2026, 9, 1)) { import("cja7x708") }

    assert_equal "youtube", entry["video_provider"]
  end

  test "makes a talk night a container for its talks" do
    travel_to(Date.new(2026, 1, 1)) { import("h5b3rmif") }

    assert_equal "children", entry["video_provider"]
    assert_equal 3, entry["talks"].to_a.length
  end

  test "records each talk with its speaker" do
    travel_to(Date.new(2026, 1, 1)) { import("h5b3rmif") }

    talk = entry["talks"].each.first

    assert_equal "rosanna-speller-bmore-on-rails-meetup-2025-12-11", talk.value_at("id")
    assert_equal "rosanna-speller-bmore-on-rails-meetup-2025-12-11", talk.value_at("video_id")
    assert_equal "What time is it?", talk.value_at("title")
    assert_equal ["Rosanna Speller"], talk["speakers"].to_a
    assert_equal "2025-12-11", talk.value_at("date")
    assert_equal "B'more on Rails - December 2025", talk.value_at("event_name")
    assert_match(/dealing with dates, times, and time zones/, talk.value_at("description"))
  end

  test "marks the talks of a past night as not recorded" do
    travel_to(Date.new(2026, 1, 1)) { import("h5b3rmif") }

    assert_equal ["not_recorded"], entry["talks"].each.map { |t| t.value_at("video_provider") }.uniq
  end

  test "marks the talks of an upcoming night as scheduled" do
    travel_to(Date.new(2025, 12, 1)) { import("h5b3rmif") }

    assert_equal ["scheduled"], entry["talks"].each.map { |t| t.value_at("video_provider") }.uniq
  end

  test "flips a night's talks to not recorded once its date has passed" do
    travel_to(Date.new(2025, 12, 1)) { import("h5b3rmif") }
    travel_to(Date.new(2026, 1, 1)) { import("h5b3rmif") }

    assert_equal ["not_recorded"], entry["talks"].each.map { |t| t.value_at("video_provider") }.uniq
  end

  test "never rewrites talks that are already recorded in the file" do
    travel_to(Date.new(2026, 1, 1)) { import("h5b3rmif") }

    file = videos_file
    talk = file.find_by(id: "rosanna-speller-bmore-on-rails-meetup-2025-12-11")
    talk["title"] = "What time is it? Timezones in Rails"
    file.save!

    travel_to(Date.new(2026, 2, 1)) { import("h5b3rmif") }

    assert_equal "What time is it? Timezones in Rails",
      videos_file.find_by(id: "rosanna-speller-bmore-on-rails-meetup-2025-12-11").value_at("title")
  end

  test "reports speakers on Luma that are missing from the file" do
    travel_to(Date.new(2026, 1, 1)) { import("h5b3rmif") }

    # Matt cancelled on the night, so his talk comes back out of the file
    file = videos_file
    file.document.root.each.first["talks"].delete_at(2)
    file.save!

    out, _err = capture_io { travel_to(Date.new(2026, 2, 1)) { import("h5b3rmif") } }

    assert_match(/Matt Scilipoti/, out)
  end

  test "says nothing about speakers when the lineup matches" do
    travel_to(Date.new(2026, 1, 1)) { import("h5b3rmif") }
    out, _err = capture_io { travel_to(Date.new(2026, 2, 1)) { import("h5b3rmif") } }

    assert_no_match(/Rosanna Speller/, out)
  end

  test "pins a slug so identically titled editions cannot collide" do
    import("cja7x708")

    assert_equal "bring-your-own-tokens-hack-night-b-more-on-rails-august-2026", entry["slug"].to_s
  end

  test "adds a slug to an edition imported before slugs were pinned" do
    import("cja7x708")

    file = videos_file
    file.document.root.each.first.delete("slug")
    file.save!

    import("cja7x708")

    assert_equal "bring-your-own-tokens-hack-night-b-more-on-rails-august-2026", entry["slug"].to_s
  end

  test "never changes a slug once it has one" do
    import("cja7x708")

    file = videos_file
    file.document.root.each.first["slug"] = "hack-night"
    file.save!

    import("cja7x708")

    assert_equal "hack-night", entry["slug"].to_s
  end

  test "links back to the Luma listing as a resource" do
    import("cja7x708")

    resource = entry["additional_resources"].each.first

    assert_equal "https://luma.com/cja7x708", resource.value_at("url")
    assert_equal "RSVP on Luma", resource.value_at("title")
    assert_equal "link", resource.value_at("type")
  end

  test "leads the description with the Luma link" do
    import("cja7x708")

    assert_match(%r{\Ahttps://luma\.com/cja7x708}, entry["description"].to_s)
  end

  test "does not add the Luma link twice when imported again" do
    import("cja7x708")
    import("cja7x708")

    assert_equal 1, entry["additional_resources"].each.to_a.length
  end

  test "adds the Luma link to an edition imported before it was a resource" do
    import("cja7x708")

    file = videos_file
    file.document.root.each.first.delete("additional_resources")
    file.save!

    import("cja7x708")

    assert_equal "https://luma.com/cja7x708", entry["additional_resources"].each.first.value_at("url")
  end

  test "leaves resources added by hand alone" do
    import("cja7x708")

    file = videos_file
    file.document.root.each.first["additional_resources"] << {
      "name" => "Photos", "url" => "https://example.com/photos", "type" => "photos"
    }
    file.save!

    import("cja7x708")

    urls = entry["additional_resources"].each.map { |r| r.value_at("url") }

    assert_includes urls, "https://example.com/photos"
    assert_equal 2, urls.length
  end

  test "leaves out the generator's TODO speaker placeholder" do
    import("cja7x708")

    assert_not entry.key?("speakers"), "expected no speakers on an edition with no talks"
  end

  test "records the edition as a container with no talks" do
    import("cja7x708")

    assert_equal [], entry["talks"].to_a
  end

  test "keeps the edition free of speakers when imported again" do
    import("cja7x708")
    import("cja7x708")

    assert_not entry.key?("speakers")
    assert_equal [], entry["talks"].to_a
  end

  test "carries the description and a link back to Luma" do
    import("cja7x708")

    assert_match(/Hack Night unlike any other/, entry["description"])
    assert_match(%r{https://luma\.com/cja7x708}, entry["description"])
  end

  test "updates the edition in place when imported again" do
    import("cja7x708")
    import("cja7x708")

    assert_equal 1, videos_file.count
    assert_equal ["bmore-on-rails-meetup-2026-08-13"], videos_file.ids
  end

  test "picks up changes made on Luma when imported again" do
    import("cja7x708")
    import("cja7x708", description_text: "We moved to a bigger room.")

    assert_equal 1, videos_file.count
    assert_match(/We moved to a bigger room\./, entry["description"])
  end

  test "keeps separate editions separate" do
    import("cja7x708")
    import("h5b3rmif")

    assert_equal 2, videos_file.count
    assert_equal ["bmore-on-rails-meetup-2026-08-13", "bmore-on-rails-meetup-2025-12-11"].sort,
      videos_file.top_level_talks.map { |talk| talk.value_at("id") }.sort
  end

  test "produces an entry that passes the data validators" do
    import("cja7x708")

    errors = Static::Validators::Validator.video_validator_classes.flat_map do |validator|
      validator.new(file_path: videos_file_path).errors
    end

    assert_empty errors, errors.map { |e| e.to_h["message"] }.join(", ")
  end

  private

  def videos_file_path
    File.join(@destination, "data/bmore-on-rails/bmore-on-rails-meetup/videos.yml")
  end

  def videos_file
    Static::VideosFile.new(videos_file_path)
  end

  def entry
    videos_file.document.root.each.first
  end

  def import(slug, description_text: nil)
    stub_listing(slug, description_text: description_text)
    BmoreOnRails::EventImport.new("https://luma.com/#{slug}", destination_root: @destination).import!
  end

  def stub_listing(slug, description_text: nil)
    payload = JSON.parse(file_fixture("luma/#{slug}.json").read)

    if description_text
      payload["description_mirror"] = {
        "type" => "doc",
        "content" => [{"type" => "paragraph", "content" => [{"type" => "text", "text" => description_text}]}]
      }
    end

    body = <<~HTML
      <script id="__NEXT_DATA__" type="application/json">
      {"props":{"pageProps":{"initialData":{"data":#{payload.to_json}}}}}
      </script>
    HTML

    stub_request(:get, "https://luma.com/#{slug}").to_return(body: body)
  end
end
