# This is based on this code: https://github.com/bitherder/stitch

require 'fiber'

module PxService
  module Client
    class Future
      class AlreadyCompletedError < StandardError; end

      ##
      # Create a new future.
      # * If klass is given, you can invoke methods on the future that belong to that
      #   class, which will block automatically until the future has a value.
      # * If a block is given, it is executed and the future is automatically completed
      #   with the block's return value
      def initialize(klass = nil)
        @klass = klass || self.class
        @completed = false
        @pending_calls = []

        if block_given?
          Fiber.new{
            begin
              complete(yield)
            rescue Exception => ex
              complete(ex)
            end
          }.resume
        end
      end

      def complete(value)
        raise AlreadyCompletedError.new if @completed

        @value = value
        @completed = true
        @pending_calls.each do |pending_call|
          if value.kind_of?(Exception)
            pending_call[:fiber].resume(value)
          else
            result = nil
            begin
              if pending_call[:method]
                result = value.send(pending_call[:method], *pending_call[:args])
              else
                result = value
              end
            rescue Exception => ex
              result = ex
            end
            pending_call[:fiber].resume(result)
          end
        end
      end

      def value
        if @completed
          @value
        else
          wait_for_value(nil)
        end
      end

      def completed?
        @completed
      end

      def method_missing(method, *args)
        super unless respond_to_missing?(method)

        if @completed
          raise @value if @value.kind_of?(Exception)
          @value.send(method, *args)
        else
          result = wait_for_value(method, *args)
          raise result if result.kind_of?(Exception)
          result
        end
      end

      def respond_to_missing?(method, include_private = false)
        return false unless @klass

        if include_private
          @klass.instance_methods.include?(method)
        else
          @klass.public_instance_methods.include?(method)
        end
      end

      private

      def wait_for_value(method, *args)
        # TODO: check for root fiber
        @pending_calls << { fiber: Fiber.current, method: method, args: args }
        Fiber.yield
      end
    end
  end
end
