module Px::Service::Client::Caching
  ##
  # Prints caching events to the log
  class LogSubscriber < ActiveSupport::LogSubscriber
    def get(event)
      payload = event.payload
      name  = color("  ServiceCache Get (#{event.duration.round(1)}ms)", GREEN, true)
      debug("#{name} #{payload[:policy_group]}[#{payload[:url]}]")
    end

    def store(event)
      payload = event.payload
      name  = color("  ServiceCache Store (#{event.duration.round(1)}ms)", GREEN, true)
      debug("#{name} #{payload[:expires_in].to_i}s => #{payload[:policy_group]}[#{payload[:url]}]")
    end

    def touch(event)
      payload = event.payload
      name  = color("  ServiceCache Touch (#{event.duration.round(1)}ms)", GREEN, true)
      debug("#{name} #{payload[:expires_in].to_i}s => #{payload[:policy_group]}[#{payload[:url]}]")
    end
  end
end
