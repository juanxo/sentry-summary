require "similar_text"

module SentrySummary
  class Aggregator
    def initialize(client)
      @client = client
    end

    def events_by_route(since = "24 hours ago")
      issues = client.issues("api", since)

      issues.each_with_object({}) do |issue, hash|
        events = client.events(issue.id)

        events.each do |event|
          hash[event.route] ||= {}

          closest_title = closest_title(hash[event.route].keys, event.metadata[:value])
          hash[event.route][closest_title] = (hash[event.route][closest_title] || 0) + 1
        end

        hash
      end
    end

    def events_by_type(since = "24 hours ago")
      issues = client.issues("api", since)

      issues.each_with_object({}) do |issue, hash|
        events = client.events(issue.id)

        events.each do |event|
          type = event.metadata[:value]
          type = closest_title(hash.keys, type)
          hash[type] ||= {}

          hash[type][event.route] = (hash[type][event.route] || 0) + 1
        end

        hash
      end
    end

    private

    def closest_title(titles, candidate)
      closest_title = titles.max_by { |title| title.similar(candidate) }

      return candidate unless closest_title && closest_title.similar(candidate) > 80

      closest_title
    end

    def client
      @client
    end
  end
end
