if ENV['SERVER']
  require 'spec_helper'
  require 'faraday'

  describe Grape::Streaming do
    subject {
      Faraday.new('http://localhost:9938').get '/stream'
    }

    it 'should stream body' do
      subject.body.should == 'ohai ohai kthxbye'
    end

    it 'should send chunked transfer encoding' do
      pending "see Rack::Chunked"
      subject.headers['Transfer-Encoding'].should == 'chunked'
    end

    it 'should warn when setting header after headers are sent' do
    end

    it 'should warn when setting status after status is sent' do
    end

    it 'should error when attempting to write to a closed connection' do
      # how to test something that's already closed? should be unit test
    end
  end
end