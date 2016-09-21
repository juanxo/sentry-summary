require "nestful"
require "chronic"

module SentrySummary
  class Sentry
    attr_writer :token, :organization

    def initialize(&block)
      block.call(self)
    end

    def issues(project, since = nil)
      paginate("projects/#{@organization}/#{project}/issues/", since) do |issue|
        Issue.build(issue)
      end
    end

    def latest_samples(project)
      issues(project).map do |issue|
        dto = request(:get, "issues/#{issue.id}/events/latest/").merge(issue_id: issue.id)
        Event.build(dto)
      end
    end

    def events(issue, since = nil)
      paginate("/issues/#{issue}/events/", since) do |event|
        Event.build(event.merge(issue_id: issue))
      end
    end

    private

    def request(method, path, parameters = {})
      response = Nestful::Request.new("#{base_url}/#{path}",
        method: method,
        auth_type: :bearer,
        password: @token,
        params: parameters
      ).execute

      links = response.headers["Link"].split(",").map do |link|
        Link.build(link)
      end

      next_link = links.find { |link| link.rel == :next && link.results? }

      Response.new(JSON.parse(response.body, symbolize_names: true), next_link)
    end

    def base_url
      "https://app.getsentry.com/api/0"
    end

    def paginate(path, since, &block)
      since ||= "24 hours ago"
      since = Chronic.parse(since)

      items = []
      cursor = nil

      begin
        response = request(:get, path, cursor: cursor)
        new_items = response.body.map(&block)

        items_in_time_range = new_items.select { |item| item.date >= since }
        items.concat(items_in_time_range)

        cursor = response.cursor
      end while response.next? && new_items.count == items_in_time_range.count

      items
    end
  end

  class Response
    attr_reader :body

    def initialize(body, next_link)
      @body = body
      @next_link = next_link
    end

    def cursor
      @next_link && @next_link.cursor
    end

    def next?
      !cursor.nil?
    end
  end

  class Link
    attr_reader :rel, :cursor

    def initialize(rel, cursor, results)
      @rel = rel.to_sym
      @cursor = cursor
      @results = results
    end

    def results?
      @results == "true"
    end

    def self.build(link)
      match = link.strip.match(/^<[^>]+>\s*((?:;\s*(?:[^;]+))*)$/)

      parameters = match[1]

      parameters = parameters.scan(/;\s*([^;]+)/).map(&:first)

      parameters = parameters.map do |parameter|
        parameter.scan(/^([^=]+)="([^"]+)"$/).first
      end.to_h

      Link.new(parameters["rel"], parameters["cursor"], parameters["results"])
    end
  end

  class Issue
    attr_reader :id, :title, :date, :metadata, :count

    def initialize(id, title, date, metadata, count)
      @id = id
      @title = title
      @date = DateTime.parse(date).to_time
      @metadata = metadata
      @count = count
    end

    def self.build(dto)
      Issue.new(dto[:id], dto[:title], dto[:lastSeen], dto[:metadata], dto[:count].to_i)
    end
  end

  class Event
    attr_reader :id, :issue_id, :date, :route, :metadata

    def initialize(id, issue_id, date, route, metadata)
      @id = id
      @issue_id = issue_id
      @date = DateTime.parse(date).to_time
      @route = route
      @metadata = metadata
    end

    def self.build(dto)
      Event.new(dto[:id], dto[:issue_id], dto[:dateCreated], dto[:context][:Route], dto[:metadata])
    end
  end

end
