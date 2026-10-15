require "faraday"
require "faraday/retry"

module OpenMeteo
  ##
  # The Faraday connection
  class FaradayConnection
    # See https://github.com/lostisland/faraday-retry/tree/main#usage
    #
    # retry_statuses matters as much as max: faraday-retry defaults it to [], so
    # without it the middleware only retries raised exceptions and hands a 429
    # or 503 back as an ordinary response. Open-Meteo's free tier allows one
    # concurrent request per IP and answers the rest with 429 "Too many
    # concurrent requests", so a caller running jobs in parallel silently loses
    # those responses — in one observed day, 92 of 5,125 requests.
    #
    # The interval is 0.5s rather than 0.05s for the same reason. A concurrency
    # rejection only clears once the in-flight request finishes, and Open-Meteo
    # answers in roughly 700ms, so the original schedule (0.05s, 0.15s, 0.45s —
    # 0.65s in total) retried entirely inside the window that was still blocked
    # and every attempt failed the same way. 0.5s with a factor of 2 spreads the
    # attempts across ~3.5s instead, and interval_randomness keeps parallel
    # callers from retrying in lockstep. Retry-After is honoured automatically
    # when a server sends one.
    RETRY_OPTIONS = {
      max: 3,
      interval: 0.5,
      interval_randomness: 0.5,
      backoff_factor: 2,
      max_interval: 5,
      retry_statuses: [429, 503],
    }.freeze

    attr_reader :config

    def initialize(config: OpenMeteo::Client::Config.new)
      @config = config
    end

    def connect
      Faraday.new do |conn|
        conn.options[:timeout] = config.timeouts[:timeout]
        conn.options[:open_timeout] = config.timeouts[:open_timeout]

        conn.request :retry, RETRY_OPTIONS
        conn.response :logger, config.logger
      end
    end
  end
end
