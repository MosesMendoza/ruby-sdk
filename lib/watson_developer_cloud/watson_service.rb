# frozen_string_literal: true

require("json")
require("erb")
require("rubygems")
require("http")
require("stringio")
require_relative("./detailed_response.rb")
require_relative("./watson_api_exception.rb")
require_relative("./iam_token_manager.rb")
require_relative("./version.rb")
# require("httplog")
# HttpLog.configure do |config|
#   config.log_connect   = true
#   config.log_request   = true
#   config.log_headers   = true
#   config.log_data      = true
#   config.log_status    = true
#   config.log_response  = true
# end

# Class for interacting with the Watson API
class WatsonService
  include ERB::Util
  attr_accessor :url, :username, :password
  attr_reader :conn
  def initialize(vars)
    defaults = {
      vcap_services_name: nil,
      username: nil,
      password: nil,
      use_vcap_services: true,
      api_key: nil,
      x_watson_learning_opt_out: false,
      iam_api_key: nil,
      iam_access_token: nil,
      iam_url: nil
    }
    vars = defaults.merge(vars)
    @url = vars[:url]
    @api_key = vars[:api_key]
    @username = vars[:username]
    @password = vars[:password]
    @iam_api_key = vars[:iam_api_key]
    @iam_access_token = vars[:iam_access_token]
    @iam_url = vars[:iam_url]
    @token_manager = nil

    user_agent_string = "watson-apis-ruby-sdk-" + WatsonDeveloperCloud::VERSION
    user_agent_string += " " + ENV["_system_name"]
    user_agent_string += " " + ENV["_system_version"]
    user_agent_string += " " + ENV["RUBY_VERSION"]

    headers = {
      "User-Agent" => user_agent_string
    }
    headers["x-watson-learning-opt-out"] = true if vars[:x_watson_learning_opt_out]
    if vars[:use_vcap_services]
      @vcap_service_credentials = load_from_vcap_services(service_name: vars[:vcap_services_name])
      if !@vcap_service_credentials.nil? && @vcap_service_credentials.instance_of?(Hash)
        @url = @vcap_service_credentials["url"]
        @username = @vcap_service_credentials["username"] if @vcap_service_credentials.key?("username")
        @password = @vcap_service_credentials["password"] if @vcap_service_credentials.key?("password")
        @api_key = @vcap_service_credentials["apikey"] if @vcap_service_credentials.key?("apikey")
        @api_key = @vcap_service_credentials["api_key"] if @vcap_service_credentials.key?("api_key")
        @iam_api_key = @vcap_service_credentials["iam_api_key"] if @vcap_service_credentials.key?("iam_api_key")
        @iam_access_token = @vcap_service_credentials["iam_access_token"] if @vcap_service_credentials.key?("iam_access_token")
        @iam_url = @vcap_service_credentials["iam_url"] if @vcap_service_credentials.key?("iam_url")
      end
    end

    if !vars[:api_key].nil?
      _api_key(api_key: vars[:api_key])
    elsif !vars[:iam_access_token].nil? || !vars[:iam_api_key].nil?
      _token_manager(iam_api_key: vars[:iam_api_key], iam_access_token: vars[:iam_access_token], iam_url: vars[:iam_url])
    elsif !vars[:username].nil? && !vars[:password].nil?
      _set_username_and_password(username: vars[:username], password: vars[:password])
    end

    @conn = HTTP::Client.new(
      headers: headers
    ).timeout(
      :per_operation,
      read: 60,
      write: 60,
      connect: 60
    )
  end

  def load_from_vcap_services(service_name:)
    vcap_services = ENV["VCAP_SERVICES"]
    unless vcap_services.nil?
      services = JSON.parse(vcap_services)
      return services[service_name][0]["credentials"] if services.key?(service_name)
    end
    nil
  end

  def _set_username_and_password(username: nil, password: nil)
    @username = username unless username.nil?
    @password = password unless password.nil?
  end

  def add_default_headers(headers: {})
    raise TypeError unless headers.instance_of?(Hash)
    headers.each_pair { |k, v| @conn.default_options.headers.add(k, v) }
  end

  def _api_key(api_key:)
    @api_key = api_key unless api_key.nil?
  end

  def _token_manager(iam_api_key: nil, iam_access_token: nil, iam_url: nil)
    @iam_api_key = iam_api_key
    @iam_access_token = iam_access_token
    @iam_url = iam_url
    @token_manager = IAMTokenManager.new(iam_api_key: iam_api_key, iam_access_token: iam_access_token, iam_url: iam_url)
  end

  def _iam_access_token(iam_access_token:)
    @token_manager._access_token(iam_access_token) unless @token_manager.nil?
    @token_manager = IAMTokenManager.new(iam_access_token: iam_access_token) if @token_manager.nil?
    @iam_access_token = iam_access_token
  end

  def _iam_api_key(iam_api_key:)
    @token_manager._iam_api_key(iam_api_key: iam_api_key) unless @token_manager.nil?
    @token_manager = IAMTokenManager.new(iam_api_key: iam_api_key) if @token_manager.nil?
    @iam_api_key = iam_api_key
  end

  def _url(url:)
    @url = url
  end

  def request(args)
    defaults = { method: nil, url: nil, accept_json: false, headers: nil, params: nil, json: {}, data: nil }
    args = defaults.merge(args)
    args[:data].delete_if { |_k, v| v.nil? } if args[:data].instance_of?(Hash)
    if args[:data].respond_to?(:merge)
      args[:json] = args[:data].merge(args[:json]) unless args[:data].instance_of?(String)
    end
    args[:json] = args[:data] if args[:json].empty? || (args[:data].instance_of?(String) && !args[:data].empty?)
    args[:json].delete_if { |_k, v| v.nil? } if args[:json].instance_of?(Hash)
    args[:headers]["Accept"] = "application/json" if args[:accept_json]
    args[:headers]["Content-Type"] = "application/json" unless args[:headers].key?("Content-Type")
    args[:json] = args[:json].to_json if args[:json].instance_of?(Hash)
    args[:headers].delete_if { |_k, v| v.nil? } if args[:headers].instance_of?(Hash)
    args[:params].delete_if { |_k, v| v.nil? } if args[:params].instance_of?(Hash)
    args[:form].delete_if { |_k, v| v.nil? } if args.key?(:form)
    args.delete_if { |_, v| v.nil? }
    args[:headers].delete("Content-Type") if args.key?(:form) || args[:json].nil?

    conn = @conn
    if !@token_manager.nil?
      access_token = @token_manager._token
      args[:headers]["Authorization"] = "Bearer #{access_token}"
    elsif !@username.nil? && !@password.nil?
      conn = @conn.basic_auth(user: @username, pass: @password)
    end
    unless @api_key.nil?
      args[:params] = {} if args[:params].nil?
      args[:params]["apikey"] = @api_key if (@url + args[:url]).start_with?("https://gateway-a.watsonplatform.net/calls")
      args[:params]["api_key"] = @api_key unless (@url + args[:url]).start_with?("https://gateway-a.watsonplatform.net/calls")
    end

    if args.key?(:form)
      response = conn.follow.request(
        args[:method],
        HTTP::URI.parse(@url + args[:url]),
        headers: conn.default_options.headers.merge(HTTP::Headers.coerce(args[:headers])),
        params: args[:params],
        form: args[:form]
      )
    else
      response = conn.follow.request(
        args[:method],
        HTTP::URI.parse(@url + args[:url]),
        headers: conn.default_options.headers.merge(HTTP::Headers.coerce(args[:headers])),
        body: args[:json],
        params: args[:params]
      )
    end
    response[:http_version] = 1.1
    return DetailedResponse.new(response: response) if (200..299).cover?(response.code)
    raise WatsonApiException.new(response: response)
    # DetailedResponse.new(response: response)
  end
end
