module Px
  module Service
    ##
    # Any external service should have its exceptions inherit from this class
    # so that controllers can handle them all nicely with "service is down" pages or whatnot
    class ServiceBaseError < StandardError
      attr_accessor :status

      def initialize(message, status)
        self.status = status
        super(message)
      end
    end

    ##
    # Indicates something was wrong with the request (ie, not a service failure, but an error on the caller's
    # part).  Corresponds to HTTP status 4xx responses
    class ServiceRequestError < ServiceBaseError
    end

    ##
    # Indicates something went wrong during request processing (a service or network error occurred)
    # Corresponds to HTTP status 5xx responses.
    # Services should catch other network/transport errors and raise this exception instead.
    class ServiceError < ServiceBaseError
    end
  end
end
