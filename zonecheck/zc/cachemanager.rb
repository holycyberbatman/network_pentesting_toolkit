# $Id: cachemanager.rb,v 1.40 2010/06/17 09:46:17 chabannf Exp $

# 
# CONTACT     : zonecheck@nic.fr
# AUTHOR      : Stephane D'Alu <sdalu@nic.fr>
#
# CREATED     : 2002/08/02 13:58:17
# REVISION    : $Revision: 1.40 $ 
# DATE        : $Date: 2010/06/17 09:46:17 $
#
# CONTRIBUTORS: (see also CREDITS file)
#
#
# LICENSE     : GPL v3
# COPYRIGHT   : AFNIC (c) 2003
#
# This file is part of ZoneCheck.
#
# ZoneCheck is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
# 
# ZoneCheck is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with ZoneCheck; if not, write to the Free Software Foundation,
# Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
#

#####
#
# TODO:
#   - add a close/destroy function to destroy the cachemanager and free
#     the dns resources
#
module ZoneCheck
require 'sync'
require 'cache'
require 'timeout'

##
## The CacheManager
##
class CacheManager
    ##
    ## Proxy an Dnsruby::RR class
    ##
    ## This will allow to add access to extra fields that are normally
    ## provided only in the DNS message header:
    ##  - ttl    : time to live
    ##  - aa     : authoritative answer
    ##  - ra     : recursivity available
    ##  - r_name : resource name
    ##
    class ProxyResource
      attr_reader :ttl, :aa, :ra, :r_name, :resource
      
      #
      # Initialize proxy 
      #
      def initialize(resource, ttl, name, header)
        @resource = resource
        @ttl      = ttl
        @r_name   = name
        @aa       = header.aa
        @ra       = header.ra
      end
      
      #
      # Save the class method for later use
      # 
      alias _class class
      
      #
      # Equality should work with proxy object or real object
      #
      def eql?(other)
        return false unless self.class == other.class
        other = other.instance_eval('@resource') if respond_to?(:_class)
        @resource == other
      end
      alias == eql?
      
      #
      # Redefine basic methods (hash, class, ...) to point to the
      # real object
      #
      def hash        ; @resource.hash        ; end
      def to_s        ; @resource.to_s        ; end
      def class       ; @resource.class       ; end
      def kind_of?(k) ; @resource.kind_of?(k) ; end
      alias instance_of? kind_of?
      alias is_a?        kind_of?
      
      #
      # Direct all unknown methods to the real object
      #
      def method_missing(method, *args)
        @resource.method(method).call(*args)
      end
    end
    
    
    
    
    attr_reader :all_caches, :all_caches_m, :root, :query_mode
    attr_accessor :edns, :domain_name
    
    def clear
      @cache.clear
    end
    
    def query_mode=(param)
      @query_mode = param
      case param
      when "tcp"
        @resolver.use_tcp = true
        @resolver.no_tcp = false
      when "udp"
        @resolver.use_tcp = false
        @resolver.no_tcp = true
      when "std"
        @resolver.use_tcp = false
        @resolver.no_tcp = false
      end
    end
    
    private
    def initialize(root, resolver)
      # Root node propagation
      @root		= root.nil? ? self      : root
      @all_caches	= root.nil? ? {}        : root.all_caches
      @all_caches_m	= root.nil? ? Sync::new : root.all_caches_m
      
      # Resolver
      @resolver		= resolver
      @resolver.do_caching = false
      @resolver.dnssec = false
      @edns = false
      @query_mode = "std"
      @edns_enabled = nil
      
      # Cached items
      @cache = Cache::new
      @cache.create(:address, :soa, :any, :ns, :mx, :cname, :a, :aaaa, :ptr, :rec, :dnskey, :rrsig)
    end
    
  def get_resources(name, resource, rec=true, exception=false, dnssec=false, edns=true, cnames={})
      msg = Dnsruby::Message::new(name.to_s, resource)
      msg.do_caching = false
      msg.header.rd = rec
      
      
      if @edns == "always" || 
        (@edns == "auto" && edns) || 
        (@edns == "autofailed" && dnssec)
        
        optrr = Dnsruby::RR::OPT.new(4096)
        if dnssec
          optrr.dnssec_ok = dnssec
        end
        msg.add_additional(optrr)
      end
      
      begin
        res = []
        ret = @resolver.send_message(msg)
        ret.answer.each {|rr|
          if (rr.type == "CNAME") && resource != "AXFR" && 
               resource != "CNAME" && resource != "ANY"
             if cnames.size > 5
               raise "Max CNAME lookup reached"
             elsif cnames[name.to_s]
               raise "CNAME loop on #{name.to_s}"
             else 
               cnames[name.to_s] = true
               res = res + get_resources(rr.cname, resource, rec, exception, dnssec, edns, cnames)
             end
          else
            res << ProxyResource::new(rr,rr.ttl,rr.name,ret.header)
          end
        }
        return res
      rescue Dnsruby::ResolvError => e
        if @edns  == "auto" && !dnssec
          case e 
          when Dnsruby::ServFail, Dnsruby::Refused, Dnsruby::NotImp
          then @edns = "autofailed"
               return get_resources(name, resource, rec, exception, dnssec, false, cnames)
          when Dnsruby::NXDomain
          then raise e,"(#{resource} #{name})" if exception
               return []
          else
               raise e,"(#{resource} #{name})"
          end
        else
          if e == Dnsruby::NXDomain
            raise e,"(#{resource} #{name})" if exception
            return []
          else
            raise e,"(#{resource} #{name})"
          end
        end
      rescue Dnsruby::ResolvTimeout => e
        if @edns  == "auto" && !dnssec
          @edns = "autofailed"
          return get_resources(name, resource, rec, exception, dnssec, edns, cnames)
        else
          raise e,"(#{resource} #{name})"
        end
      end
      nil
    end
    
    def get_resource(name, resource, rec=true, exception=false, dnssec=false, edns=true)
      res = get_resources(name, resource, rec, exception, dnssec, edns)
      return nil if res.nil?
      return res[0]
    end
    

    public
    def [](ip)
      begin
        @all_caches_m.synchronize {
          # Is the root asked?
          return @root if ip.nil?
          # Sanity check
          unless ip.nil? || 
                 (ip.class == Dnsruby::IPv4 || 
                 ip.class == Dnsruby::IPv6 )
            raise 'Argument should be an Address'
          end
           
          # Retrieve/Create the cachemanager for the address
          ip = ip.to_s
          if (ic = @all_caches[ip]).nil?
            resolver = Dnsruby::Resolver::new({:nameserver => ip})
            ic     = CacheManager::new(@root,resolver)
            ic.domain_name = @domain_name
            ic.init(@edns,
                    @query_mode,
                    @resolver.retry_times,
                    @resolver.retry_delay,
                    @resolver.query_timeout)
            @all_caches[ip] = ic
          end
          ic
        }
      rescue Sync_m::Err::UnknownLocker => e
        $dbg.msg(DBG::INIT) { "An error occured on the cachemanager mutex: " + e }
      end
    end
    
    def init(edns, query_mode, retry_times, retry_delay, query_timeout)
      @edns = edns
      self.query_mode = query_mode
      @resolver.retry_times = retry_times
      @resolver.retry_delay = retry_delay
      @resolver.query_timeout = query_timeout
      if edns == "auto"
        begin
          status = Timeout::timeout(3) {
            msg   = Dnsruby::Message::new(@domain_name, "ANY")
            optrr = Dnsruby::RR::OPT.new(4096)
            optrr.dnssec_ok = true
            msg.add_additional(optrr)
            msg.do_caching = false
            
            @resolver.do_caching = false
            
            ret = @resolver.send_message(msg)
            unless ret.nil? || ret.additional.empty?
              ret.additional.each { |add|
                if add.type == "OPT" && add.payloadsize > 1024
                  @edns = edns
                  break
                end
              }
            end
          }
          @edns = "auto"
        rescue Dnsruby::ResolvError
          @edns = "autofailed"
        rescue Dnsruby::ResolvTimeout
          @edns = "autofailed"
        rescue Timeout::Error
          @edns = "autofailed"
        end
      end
      return @edns
    end
    
    # Create the root information cache
    def self.create(resolver)
      CacheManager::new(nil, resolver)
    end
    
    #-- Shortcuts ----------------------------------------------------
    def addresses(host)
      case host
      when String
        if host =~ Dnsruby::IPv4.Regex
          host = Dnsruby::IPv4::create(host)
        elsif host =~ Dnsruby::IPv6.Regex
          host = Dnsruby::IPv6::create(host)
        else
          host = Dnsruby::Name::create(host)
        end
        addresses(host)
      when Dnsruby::IPv4
        [ host ]
      when Dnsruby::IPv6
        [ host ]
      when Dnsruby::Name
        @cache.use(:address, host) {
        getaddresses(host)
        }
      else
        raise ArgumentError, 'Expecting Address or DNS Name'
      end
    end
    
    def getaddresses(name)
      ret = []
      error_count = 0;
      begin
        ret += get_resources(name.to_s,"A")
      rescue Dnsruby::NXDomain => e
        error = e
        error_count += 1
      end
      begin
        ret += get_resources(name.to_s,"AAAA")
      rescue Dnsruby::NXDomain
        error_count += 1
      end
      raise error if error_count == 2 && !(error.nil?)
      return ret
    end
    
    # ANY records
    def any(domainname, resource=nil, force=nil)
      res = @cache.use(:any, domainname, force) {
        get_resources(domainname, "ANY")
      }
      if resource.nil?
        return res
      else
        nres = [ ]
        res.each { |r| nres << r if r.class == resource }
        return nres
      end
    end
    
    # SOA record
    def soa(domainname, force=nil)
      @cache.use(:soa, domainname, force) {
        get_resource(domainname,  "SOA")
      }
    end
    
    # NS records
    def ns(domainname, force=nil)
      @cache.use(:ns, domainname, force) {
        get_resources(domainname, "NS")
      }
    end
    
    # MX record
    def mx(domainname, force=nil)
      @cache.use(:mx, domainname, force) {
        get_resources(domainname, "MX")
      }
    end
    
    # A record
    def a(name, force=nil)
      @cache.use(:a, name, force) {
        get_resources(name,        "A")
      }
    end
    
    # AAAA record
    def aaaa(name, force=nil)
      @cache.use(:aaaa, name, force) {
        get_resources(name,        "AAAA")
      }
    end
    
    # CNAME record
    def cname(name, force=nil)
      @cache.use(:cname, name, force) {
        get_resource(name,        "CNAME")
      }
    end
    
    # PTR records
    def ptr(name, force=nil)
      @cache.use(:ptr, name, force) {
        get_resources(name,       "PTR")
      }
    end	
    
    # TXT record
    def txt(name, force=nil)
      @cache.use(:ptr, name, force) {
        get_resources(name,       "TXT")
      }
    end
    
    def dnskey(name, force=false)
      @resolver.dnssec = true
      begin
        ret = @cache.use(:dnskey, name, force) {
          get_resources(name,"DNSKEY")
        }
        ret.delete_if {|res| res.class != Dnsruby::RR::IN::DNSKEY }
        @resolver.dnssec = false
        return ret 
      rescue => e
        @resolver.dnssec = false
        raise e
      ensure
        @resolver.dnssec = false
      end
    end
    
    def rrsig(name, resource, force=false)
      if resource.nil?
        resource = "RRSIG"
      end
      ret = @cache.use(:rrsig, [name,resource], force) {
        get_resources(name,resource, true, false, true)
      }
      ret.delete_if {|res| res.class != Dnsruby::RR::IN::RRSIG }
      return ret
    end
    
    #-- Shortcuts ----------------------------------------------------
    def rec(domainname, force=nil)
      @cache.use(:rec, domainname, force) {
        soa = soa(domainname, force)
        raise Dnsruby::ResolvError, 'Domain doesn\'t exists' if soa.nil?
        soa.ra
      }
    end
end
end