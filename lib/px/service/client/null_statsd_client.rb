module Px::Service::Client
  # Does nothing, gracefully
  class NullStatsdClient
    def increment(*args)
    end

    def gauge(*args)
    end

    def histogram(*args)
    end

    def time(*args)
      yield if block_given?
    end

    def timing(*args)
    end

    def set(*args)
    end

    def count(*args)
    end

    def batch(*args)
      yield(self) if block_given?
    end
  end
end
