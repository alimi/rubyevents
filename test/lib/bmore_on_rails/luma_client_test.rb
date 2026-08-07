require "test_helper"

module BmoreOnRails
  class LumaClientTest < ActiveSupport::TestCase
    test "returns the event data embedded in the listing page" do
      stub_listing("cja7x708")

      payload = LumaClient.new.event("cja7x708")

      assert_equal "Bring Your Own Tokens Hack Night | B'more on Rails", payload.dig("event", "name")
      assert_equal "2026-08-13T23:00:00.000Z", payload.dig("event", "start_at")
      assert_equal "America/New_York", payload.dig("event", "timezone")
      assert payload["description_mirror"].present?
    end

    test "accepts a full url instead of a slug" do
      stub_listing("cja7x708")

      payload = LumaClient.new.event("https://luma.com/cja7x708")

      assert_equal "cja7x708", payload.dig("event", "url")
    end

    test "raises when the listing has no embedded event data" do
      stub_request(:get, "https://luma.com/nope").to_return(body: "<html><body>nothing here</body></html>")

      assert_raises(LumaClient::UnexpectedResponse) { LumaClient.new.event("nope") }
    end

    private

    def stub_listing(slug)
      payload = file_fixture("luma/#{slug}.json").read
      body = <<~HTML
        <html><body>
        <script id="__NEXT_DATA__" type="application/json">
        {"props":{"pageProps":{"initialData":{"kind":"event","data":#{payload}}}}}
        </script>
        </body></html>
      HTML

      stub_request(:get, "https://luma.com/#{slug}").to_return(body: body)
    end
  end
end
