require 'bundler/setup'
Bundler.setup

require 'px/service/client'
require 'timecop'
require 'vcr'

##
# VCR config
VCR.configure do |c|
  c.cassette_library_dir = 'spec/vcr'
  c.hook_into :typhoeus, :webmock
  c.allow_http_connections_when_no_cassette = true
  c.configure_rspec_metadata!
end

RSpec.configure do |config|
  config.before(:each) do
    Typhoeus::Expectation.clear
  end

  config.after(:each) do
    Timecop.return
  end
end
