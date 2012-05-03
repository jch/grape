require 'eventmachine'

module Grape
  # Streaming APIs
  #
  # @example
  # class Streaming < Grape::API
  #   before do
  #     stream "on caturday "
  #   end
  #
  #   after do
  #     stream "kthxbye"
  #   end
  #
  #   get '/stream', :stream => true do
  #     status 202
  #     count = 0
  #     EM.add_timer(0.1) {stream "i iz sleepin "}
  #     EM.add_timer(0.2) {stream "in yr bed "}
  #     EM.add_timer(0.3) {
  #       stream "kthx "
  #       close
  #     }
  #   end
  # end
  #
  # > curl http://localhost:3000/stream
  # > on caturday i iz sleepin in yr bed kthx kthxbye
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

    # Write a chunk of content to the stream
    def stream(content)
      deferred_body.chunk [content]
    end

    # Write last chunk to stream, then close connection
    def stream!(content = "")
      stream(content)
      close
    end

    # Closes the connection, after calling any callbacks defined by
    # `streaming_callback` and flushing any remaining chunks to stream
    def close(flush = true)
      deferred_body.close!(flush)
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

      def before_close(&blk)
        @before_close = blk
      end

      def close!(flush = true)
        @before_close.call if @before_close && flush
        callback {@closed = true}
        EM.next_tick {
          succeed if !flush || empty?
        }
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

    # Declare a callback to run before connection is closed
    def before_close(&blk)
      deferred_body.before_close(&blk)
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
  end
end
