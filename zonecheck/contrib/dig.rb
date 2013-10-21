#!/usr/local/bin/ruby

ZC_INSTALL_PATH		= (ENV["ZC_INSTALL_PATH"] || (ENV["HOME"] || "/homes/sdalu") + "/Repository/zonecheck").dup.untaint

ZC_LIB			= "#{ZC_INSTALL_PATH}/lib"

$LOAD_PATH << ZC_LIB

require 'rubygems'
require 'dnsruby'

resolver = Dnsruby::Resolver::new({ :nameserver => 'ns1.nic.fr'})
resolver.dnssec = false

name = Dnsruby::Name::create("fr.")
puts name

resolver.query(name.to_s, "NS") { |r,t,n,rpl|
    puts "#{r.to_dig}"
}

