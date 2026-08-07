# Imports one B'more on Rails meetup edition from its Luma listing.
#
# Each edition is one entry in videos.yml - see docs/ADDING_MEETUPS.md. Re-running
# with the same edition updates that entry rather than adding a second one.
#
# Run it with scripts/import_bmore_on_rails_event.rb.

# TalkGenerator is excluded from autoloading, so it is required rather than
# referenced. LumaClient and LumaEventMetadata sit alongside this file and are
# autoloaded, so requiring them would define them outside Zeitwerk's tracking.
require "generators/talk/talk_generator"

module BmoreOnRails
  # TalkGenerator writes the entry, but it derives ids from the title, which gives
  # "b-more-on-rails-august-2026-bmore-on-rails-meetup". Meetups elsewhere in data/
  # are keyed "{event-slug}-{date}" instead, which the talk id validator allows by
  # exempting meetups from the Talk::StaticID convention. So the id is rewritten
  # once the generator is done, and handed back on later runs so the generator
  # updates the existing entry rather than appending a second one.
  class EventImport
    SERIES_SLUG = "bmore-on-rails"
    EVENT_SLUG = "bmore-on-rails-meetup"
    MEETUP_NAME = "B'more on Rails"

    # Providers this script owns. Anything else on an entry was set by hand.
    MANAGED_PROVIDERS = ["scheduled", "not_recorded"].freeze

    def initialize(url, destination_root: Rails.root)
      @url = url
      @destination_root = destination_root
    end

    def import!
      known_ids = existing_ids

      atomically do
        generate(id: id.presence_in(known_ids))

        normalize_generated_entry(known_ids) unless known_ids.include?(id)
        update_recording_status
        ensure_slug
        ensure_luma_resource
        report_missing_speakers
      end

      id
    end

    # "bmore-on-rails-meetup-2026-08-13"
    def id
      @id ||= "#{EVENT_SLUG}-#{metadata.date}"
    end

    private

    # videos.yml is built up a piece at a time - the generator appends the entry,
    # then each pass below fills in part of it - so a run that stops partway
    # leaves the file half written. That is not merely untidy: the generator
    # names the entry after its title, and it is only renamed to the meetup
    # convention once the generator is done. Stop in between and the entry is
    # stranded under a name no later run looks for. Worse, the generator hands
    # that same name back on the next run and takes its "already exists" path,
    # so every re-run finds its work apparently done and quietly changes
    # nothing, while the import still reports the id it never wrote.
    #
    # So the file is put back exactly as it was unless the whole run finishes.
    # Every pass here is idempotent, so throwing away finished work costs only
    # a re-run, and "untouched" is a state the next run can always recover from
    # - which "half applied" is not. `ensure` rather than `rescue` so that an
    # interrupt at the terminal rolls back too.
    def atomically
      original = File.exist?(videos_file_path) ? File.read(videos_file_path) : nil
      completed = false

      yield

      completed = true
    ensure
      restore(original) unless completed
    end

    def restore(original)
      if original
        File.write(videos_file_path, original)
      elsif File.exist?(videos_file_path)
        File.delete(videos_file_path)
      end
    end

    def metadata
      @metadata ||= LumaEventMetadata.new(
        payload: LumaClient.new.event(@url),
        meetup_name: MEETUP_NAME
      )
    end

    def generate(id: nil)
      options = [
        "--event-series", SERIES_SLUG,
        "--event", EVENT_SLUG,
        "--title", metadata.title,
        "--date", metadata.date,
        "--description", metadata.description
      ]
      options.push("--id", id) if id

      TalkGenerator.start(options, destination_root: @destination_root)
    end

    # The generator names the new entry itself, so it is whichever id appeared
    # while it ran. It also fills in a "TODO" speaker, which an edition with no
    # talks should not carry - an empty `talks` container says the same thing
    # without inventing a speaker, and is what other meetups use for editions
    # like this. Entries must have exactly one of `talks` or `speakers`.
    #
    # `event_name` is meetup-only and the generator has no option for it, so it
    # is filled in here too. Key order is left to `yerba apply`.
    def normalize_generated_entry(known_ids)
      file = videos_file
      generated_id = (file.ids - known_ids).first
      return if generated_id.blank?

      entry = file.find_by(id: generated_id)
      entry["id"] = id
      entry["video_id"] = id
      entry["event_name"] = metadata.event_name
      entry.delete("speakers")
      entry["talks"] = metadata.talks.map { |talk| talk_attributes(talk) }
      entry["video_provider"] = "children" if metadata.talks.any?
      file.save!
    end

    def talk_attributes(talk)
      talk_id = "#{talk.speaker.parameterize}-#{id}"

      {
        "id" => talk_id,
        "title" => talk.title,
        "event_name" => metadata.event_name,
        "date" => metadata.date,
        "video_provider" => recording_status,
        "video_id" => talk_id,
        "description" => talk.description,
        "speakers" => [talk.speaker]
      }
    end

    # An edition that has not happened yet is scheduled; once its date passes,
    # nothing was ever recorded. Re-running after the date flips it over. Any
    # other provider was chosen by hand - a recording that turned up later, say -
    # so those are left alone. A talk night's status lives on its talks, and the
    # edition itself stays a plain container.
    def update_recording_status
      file = videos_file
      entry = file.find_by(id: id)
      return if entry.nil?

      child_talks = child_talks_of(entry)
      nodes = child_talks.any? ? child_talks : [entry]
      managed = nodes.select { |node| node.value_at("video_provider").in?(MANAGED_PROVIDERS) }
      return if managed.empty?

      managed.each { |node| node["video_provider"] = recording_status }
      file.save!
    end

    def recording_status
      upcoming? ? "scheduled" : "not_recorded"
    end

    # An empty `talks` sequence still reads as present, so ask for the items.
    def child_talks_of(entry)
      entry["talks"]&.each&.to_a || []
    end

    def upcoming?
      Date.parse(metadata.date) >= Date.current
    end

    # A pinned slug is the first candidate the site considers, so it settles the
    # url outright instead of letting collisions be resolved by seeding order.
    # Only ever written when absent: a url that is already public should not move
    # because a title was reworded on Luma.
    def ensure_slug
      file = videos_file
      entry = file.find_by(id: id)
      return if entry.nil? || entry.value_at("slug").present?

      entry["slug"] = metadata.slug
      file.save!
    end

    # The listing is where people RSVP, so it gets a resource of its own rather
    # than only the trailing url in the description. Added if absent rather than
    # rewritten, so resources added by hand survive a re-run.
    def ensure_luma_resource
      file = videos_file
      entry = file.find_by(id: id)
      return if entry.nil?

      resources = entry["additional_resources"]&.each&.to_a || []
      return if resources.any? { |resource| resource.value_at("url") == metadata.url }

      entry["additional_resources"] = resources.map(&:to_h) + [{
        "name" => "Luma",
        "title" => "RSVP on Luma",
        "url" => metadata.url,
        "type" => "link"
      }]
      file.save!
    end

    # Talks are written once and never rewritten, so a lineup that changed after
    # the first import - or a speaker who cancelled on the night and was left on
    # the listing - shows up here instead of being reconciled automatically.
    # Luma holds the plan; the file holds what actually happened.
    def report_missing_speakers
      entry = videos_file.find_by(id: id)
      return if entry.nil?

      recorded = child_talks_of(entry).flat_map { |talk| talk["speakers"].to_a }
      missing = metadata.talks.map(&:speaker) - recorded
      return if missing.empty?

      puts "On Luma but not in #{File.basename(videos_file_path)} for #{id}: #{missing.join(", ")}"
    end

    def existing_ids
      File.exist?(videos_file_path) ? videos_file.ids : []
    end

    def videos_file
      Static::VideosFile.new(videos_file_path)
    end

    def videos_file_path
      File.join(@destination_root.to_s, "data", SERIES_SLUG, EVENT_SLUG, "videos.yml")
    end
  end
end
