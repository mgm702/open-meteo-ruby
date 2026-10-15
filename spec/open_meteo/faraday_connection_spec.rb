RSpec.describe(OpenMeteo::FaradayConnection) do
  subject(:connection) { described_class.new.connect }

  def retry_handler
    connection.builder.handlers.find { |handler| handler.klass == Faraday::Retry::Middleware }
  end

  def retry_options
    retry_handler.instance_variable_get(:@args).first
  end

  it "registers the retry middleware" do
    expect(retry_handler).not_to be(nil)
  end

  # faraday-retry defaults retry_statuses to [], which retries raised exceptions
  # only. Open-Meteo sheds load with 429 "Too many concurrent requests" and
  # wobbles with 503; both arrive as ordinary responses, so without this the
  # caller silently loses them.
  it "retries the statuses Open-Meteo uses to shed load" do
    expect(retry_options[:retry_statuses]).to include(429, 503)
  end

  # A concurrency rejection only clears once the in-flight request finishes, and
  # Open-Meteo answers in roughly 700ms. Retrying entirely inside that window
  # fails the same way every time, so the schedule has to outlast one response.
  it "spreads its attempts beyond a single upstream response time" do
    options = retry_options
    elapsed = (0...options[:max]).sum { |attempt| options[:interval] * (options[:backoff_factor]**attempt) }

    expect(elapsed).to be > 1.0
  end

  it "keeps any single wait bounded" do
    expect(retry_options[:max_interval]).to be_positive
  end
end
