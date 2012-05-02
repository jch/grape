require 'eventmachine'

module Grape
  # Streaming APIs
  #
  # @example
  # class API < Grape::API
  #   get '/delay', stream: true do
  #     status 202
  #     EM.add_periodic_timer(1) {
  #       flush "hello world\n"
  #     }
  #     EM.add_timer(3) {
  #       flush "that's all folks!\n"
  #       close
  #     }
  #   end
  # end
  #
  # Caveats:
  #
  # Status and headers are sent immediately after endpoint is evaluated, values set in
  # post endpoint middleware will be ignored.
  module Streaming
    def streaming?
      # TODO: would prefer to pass in the endpoint instance and access through that
      options[:route_options][:stream]
    end

    # Declare a callback to run before connection is closed
    def streaming_callback(&blk)
      @before_close_callback = blk
    end

    # Returns a rack compatible response.
    #
    # @param blk [Block]
    #   for non-streaming requests: block to evaluate for response
    #   for streaming requests: block to eval before closing connection
    def streaming_response(env, status=200, headers={})
      yield if block_given?
      EM.next_tick do
        # bit leaky that we're assuming @env is defined
        env['async.callback'].call [status, headers, deferred_body]
      end
      ASYNC_RESPONSE
    end

    # Ideally just allow users to call body repeatedly...
    def flush(content)
      deferred_body.chunk [content]
    end

    # Write last chunk to stream, then close connection
    def flush!(content = "")
      flush(content)
      close
    end

    # Closes the connection, will flush remaining chunks to stream
    def close(flush = true)
      deferred_body.callback(&@before_close_callback)
      EM.next_tick {
        deferred_body.succeed if !flush || deferred_body.empty?
      }
    end

    # Immediately close the connection. Don't wait for remaining items to flush
    def close!
      close(false)
    end

    protected

    ASYNC_RESPONSE = [-1, {}, []].freeze

    # From [thin_async](https://github.com/macournoyer/thin_async)
    class DeferrableBody
      include EM::Deferrable

      def initialize
        @queue = []
      end

      # Enqueue a chunk of content to be flushed to stream
      # at a later time.
      def chunk(body)
        @queue << body
        schedule_dequeue
      end

      # When rack attempts to iterate over `body`, save the block,
      # and execute at a later time when `@queue` has elements
      def each(&blk)
        @body_callback = blk
        schedule_dequeue
      end

      def empty?
        @queue.empty?
      end

      private
      def schedule_dequeue
        return unless @body_callback
        EM.next_tick do
          next unless body = @queue.shift
          body.each do |chunk|
            @body_callback.call(chunk)
          end
          schedule_dequeue unless empty?
        end
      end
    end

    def deferred_body
      @deferred_body ||= DeferrableBody.new
    end
  end
end
