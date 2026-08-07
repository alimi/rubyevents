# Imports one B'more on Rails meetup edition from its Luma listing.
#
# start this script with the rails runner command
# $ bin/rails runner scripts/import_bmore_on_rails_event.rb https://luma.com/cja7x708
#
# Each edition is one entry in videos.yml - see docs/ADDING_MEETUPS.md. Re-running
# with the same edition updates that entry rather than adding a second one.
#
# The import itself lives in lib/bmore_on_rails.

url = ARGV[0]

if url.blank?
  puts "Please provide a Luma event url, e.g. https://luma.com/cja7x708"
  exit 1
end

puts "Imported #{BmoreOnRails::EventImport.new(url).import!}"
