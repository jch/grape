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
    class ClosedConnectionError < RuntimeError; end

    def streaming?
      # TODO: would prefer to pass in the endpoint instance and access through that
      options[:route_options][:stream]
    end

    # Declare a callback to run before connection is closed
    def streaming_callback(&blk)
      deferred_body.callback(&blk)
    end

    # Schedules deferred rack response and immediately returns
    # ASYNC_RESPONSE signaling response will be async.
    def streaming_response(env, status=200, headers={})
      EM.next_tick do
        if callback = env['async.callback']
          callback.call [status, headers, deferred_body]
        else
          $stderr.puts "missing async.callback. run within thin or rainbows"
          # warn
        end
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

    # Closes the connection, after calling any callbacks defined by
    # `streaming_callback` and flushing any remaining chunks to stream
    def close(flush = true)
      EM.next_tick {
        deferred_body.succeed if !flush || deferred_body.empty?
      }
    end

    # Immediately close the connection. Don't wait for remaining items to flush
    def close!
      close(false)
    end

    def closed?
      deferred_body.closed?
    end

    protected

    ASYNC_RESPONSE = [-1, {}, []].freeze

    # From [thin_async](https://github.com/macournoyer/thin_async)
    class DeferrableBody
      include EM::Deferrable

      attr_reader :queue

      def initialize
        @queue  = []
        @closed = false
        callback {@closed = true}
      end

      # Enqueue a chunk of content to be flushed to stream
      # at a later time.
      def chunk(body)
        raise Grape::Streaming::ClosedConnectionError.new("Attempted to write to a closed connection") if closed?
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

      def closed?
        @closed
      end

      private
      def schedule_dequeue
        return unless @body_callback
        EM.next_tick do
          next unless body = @queue.shift
          body.each do |chunk|
            @body_callback.call(chunk)
          end
        end
      end
    end

    def deferred_body
      @deferred_body ||= DeferrableBody.new
    end
  end
end
