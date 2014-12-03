module Px::Service
  module Client
    module Caching
      class Railtie < ::Rails::Railtie
        initializer "service.client.caching" do
          Px::Service::Client::Caching::LogSubscriber.attach_to :caching
        end
      end
    end
  end
end
