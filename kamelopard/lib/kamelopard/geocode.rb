# vim:ts=4:sw=4:et:smartindent:nowrap

require 'rubygems'
require 'net/http'
require 'uri'
require 'cgi'
require 'json'

# Geocoder base class
class Geocoder
    def initialize
        raise "Unimplemented -- some other class should extend Geocoder and replace this initialize method"
    end

    def lookup(address)
        raise "Unimplemented -- some other class should extend Geocoder and replace this lookup method"
    end
end

# Uses Yahoo's PlaceFinder geocoding service: http://developer.yahoo.com/geo/placefinder/guide/requests.html
# Google's would seem most obvious, but since it requires you to display
# results on a map, ... I didn't want to have to evaluate other possible
# restrictions. The argument to the constructor is a PlaceFinder API key, but
# testing suggests it's actually unnecessary
class YahooGeocoder < Geocoder
    def initialize(key)
        @api_key = key
        @proto = 'http'
        @host = 'where.yahooapis.com'
        @path = '/geocode'
        @params = { 'appid' => @api_key, 'flags' => 'J' }
    end

    # Returns an object built from the JSON result of the lookup, or an exception
    def lookup(address)
        # The argument can be a string, in which case PlaceFinder does the parsing
        # The argument can also be a hash, with several possible keys. See the PlaceFinder documentation for details
        # http://developer.yahoo.com/geo/placefinder/guide/requests.html
        http = Net::HTTP.new(@host)
        if address.kind_of? Hash then
            p = @params.merge address
        else
            p = @params.merge( { 'q' => address } )
        end
        q = p.map { |k,v| "#{ CGI.escape(k) }=#{ CGI.escape(v) }" }.join('&')
        u = URI::HTTP.build([nil, @host, nil, @path, q, nil])

        resp = Net::HTTP.get u
        parse_response resp
    end

    def parse_response(resp)
        d = JSON.parse(resp)
        raise d['ErrorMessage'] if d['Error'].to_i != 0
        d
    end
end

# EXAMPLE
# require 'rubygems'
# require 'kamelopard'
# g = YahooGeocoder.new('some-api-key')
# puts g.lookup({ 'city' => 'Springfield', 'count' => '100' })
