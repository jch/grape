require 'grape'
require 'pry'
require 'thin'

module Integration
  class Streaming < Grape::API
    before do
      stream "on caturday "
    end

    after do
      stream "kthxbye"
    end

    get '/stream', :stream => true do
      status 202
      count = 0
      EM.add_timer(0.1) {stream "i iz sleepin "}
      EM.add_timer(0.2) {stream "in yr bed "}
      EM.add_timer(0.3) {
        stream "kthx "
        close
      }
    end
  end
end

if $0 == __FILE__
  unless ENV['SERVER']
    puts "You need to specify a server."
    exit 1
  end

  server = Integration.const_get(ENV['SERVER'])
  Rack::Handler::Thin.run(server, {
    :Host => '127.0.0.1',
    :Port => '9938'
  })
end