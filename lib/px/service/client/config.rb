module Px
  module Service
    module Client
      class << self
        DefaultConfig = Struct.new(:secret, :keyspan) do
          def initialize
            self.secret = DEFAULT_SECRET
            self.keyspan = DEFAULT_KEYSPAN
          end
        end

        def configure
          @config = DefaultConfig.new
          yield(@config) if block_given?
          @config
        end

        def config
          @config || configure
        end
      end
    end
  end
end
