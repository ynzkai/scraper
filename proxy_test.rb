#!/usr/bin/env ruby

require 'mechanize'
require 'benchmark'

require File.expand_path('proxies.rb', __dir__)

class Scraper < Mechanize

  attr_accessor :url

  def initialize(url)
    super()
    self.user_agent_alias = 'Mac Safari'
    self.robots = false
    self.open_timeout = 10
    self.read_timeout = 10
    self.request_headers[SecureRandom.hex(10)] = SecureRandom.hex(10)

  end

  def test_proxy(url, proxy)
    set_proxy(*proxy)
    begin
      _page = get url
    rescue => e
      $stderr.puts "#{e.class}: #{e.message}"
    end
    _page
  end
end


# url = ["https://www.therealreal.com/sales/womens-jewelry?taxons%5B%5D=759"]
# url = ["https://www.therealreal.com/sales/new-arrivals-fine-watches-1449?taxons%5B%5D=760"]
url = "https://www.therealreal.com/shop/women/handbags"

scraper = Scraper.new(url)

puts "start testing proxy IPs:"

proxies = []

Proxies.each do |proxy|
  puts "test proxy #{proxy} :"
  _page = nil
  time = Benchmark.realtime { |x| _page = scraper.test_proxy url, proxy }
  result = _page.nil? ? "Bad" : "Ok"

  proxies.push ["\"#{proxy[0]}\"", proxy[1], "nil", "nil", result, time]
end

puts "Done!"

puts "report the test result:"
proxies.each do |p|
  puts p.join ', '
end
