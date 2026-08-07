# Reads a public Luma event listing.
#
# Luma has no public event API, but the listing page is server rendered by
# Next.js and carries the whole event as JSON in a __NEXT_DATA__ script tag,
# so no key or browser is needed to read it.
module BmoreOnRails
  class LumaClient < ApplicationClient
    class UnexpectedResponse < Error; end

    BASE_URI = "https://luma.com"
    EMBEDDED_DATA = %r{<script id="__NEXT_DATA__" type="application/json">(?<json>.*?)</script>}m

    def event(slug_or_url)
      slug = slug_or_url.to_s.split("/").last
      body = get("/#{slug}").body
      json = body[EMBEDDED_DATA, :json]

      raise UnexpectedResponse, "No event data found at #{base_uri}/#{slug}" if json.blank?

      JSON.parse(json).dig("props", "pageProps", "initialData", "data") ||
        raise(UnexpectedResponse, "Event data at #{base_uri}/#{slug} was not in the expected shape")
    end

    private

    def content_type
      "text/html"
    end
  end
end
