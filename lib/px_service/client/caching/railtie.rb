module PxService
  module Client
    module Caching
      class Railtie < ::Rails::Railtie
        initializer "service.client.caching" do
          PxService::Client::Caching::LogSubscriber.attach_to :caching
        end
      end
    end
  end
end
