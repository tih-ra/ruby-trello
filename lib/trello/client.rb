require 'addressable/uri'

module Trello
  class Client
    include Authorization

    delegate *Configuration::CONFIGURABLE_ATTRIBUTES, to: :configuration
    delegate :credentials, to: :configuration

    def initialize(attrs = {})
      self.configuration.attributes = attrs
    end

    def get(path, params = {})
      uri = Addressable::URI.parse("https://api.trello.com/#{API_VERSION}#{path}")
      uri.query_values = params unless params.empty?
      invoke_verb(:get, uri)
    end

    def post(path, body = {})
      uri = Addressable::URI.parse("https://api.trello.com/#{API_VERSION}#{path}")
      invoke_verb(:post, uri, body)
    end

    def put(path, body = {})
      uri = Addressable::URI.parse("https://api.trello.com/#{API_VERSION}#{path}")
      invoke_verb(:put, uri, body)
    end

    def delete(path)
      uri = Addressable::URI.parse("https://api.trello.com/#{API_VERSION}#{path}")
      invoke_verb(:delete, uri)
    end

    # Finds given resource by id
    #
    # Examples:
    #   client.find(:board, "board1234")
    #   client.find(:member, "user1234")
    #   client.find(Board, "board1234")
    #   client.find(Member, "member1234")
    #
    def find(path, id)
      response = get("/#{path.to_s.pluralize}/#{id}")
      class_from_path(path).parse(response) do |data|
        data.client = self
      end
    end

    # Finds given resource by path with params
    def find_many(klass, path, params = {})
      response = get(path, params)
      klass.parse_many(response) do |data|
        data.client = self
      end
    end

    # Creates resource with given options (attributes)
    #
    # Examples:
    #   client.create(:member, options)
    #   client.create(:board, options)
    #   client.create(Member, options)
    #   client.create(Board, options)
    #
    def create(path, options)
      class_from_path(path).save(options) do |data|
        data.client = self
      end
    end

    def configure
      yield configuration if block_given?
    end

    def configuration
      @configuration ||= Configuration.new
    end

    def auth_policy
      @auth_policy ||= auth_policy_class.new(credentials)
    end

    private

    def invoke_verb(name, uri, body = nil)
      request = Request.new name, uri, {}, body
      response = TInternet.execute auth_policy.authorize(request)

      return '' unless response

      if response.code.to_i == 401 && response.body =~ /expired token/
        Trello.logger.error("[401 #{name.to_s.upcase} #{uri}]: Your access token has expired.")
        raise InvalidAccessToken, response.body
      end

      unless [200, 201].include? response.code
        Trello.logger.error("[#{response.code} #{name.to_s.upcase} #{uri}]: #{response.body}")
        raise Error, response.body
      end

      response.body
    end

    def auth_policy_class
      if configuration.oauth?
        OAuthPolicy
      elsif configuration.basic?
        BasicAuthPolicy
      else
        AuthPolicy
      end
    end

    def class_from_path(path_or_class)
      return path_or_class if path_or_class.is_a?(Class)
      Trello.const_get(path_or_class.to_s.singularize.camelize)
    end
  end
end
