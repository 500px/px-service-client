require 'bundler/setup'
Bundler.setup

require 'service/client'
require 'timecop'

RSpec.configure do |config|
  config.before(:each) do

  end

  config.after(:each) do
    Timecop.return
  end
end
