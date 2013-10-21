# $Id: framework.rb,v 1.56 2010/09/30 12:39:15 bortzmeyer Exp $

# 
# CONTACT     : zonecheck@nic.fr
# AUTHOR      : Stephane D'Alu <sdalu@nic.fr>
#
# CREATED     : 2002/08/02 13:58:17
# REVISION    : $Revision: 1.56 $ 
# DATE        : $Date: 2010/09/30 12:39:15 $
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
module ZoneCheck
require 'cache'
require 'cachemanager'
require 'msgcat'

##
## Class that should be inherited by every test set
##
class Test
    ##
    ## Abstract class for: Succeed, Failed, Error
    ##
    class Result # --> ABSTRACT <--
	class Desc
	    attr_writer :error, :details
	    attr_reader :error, :details
	    attr_reader :check

	    def initialize(check=true)
		@check		= check
		@error		= nil	# Error message (ie: Exception)
		@details	= nil
	    end

	    def hash
		@check ^ @error.hash ^ @msg.details
	    end
	    
	    def eql?(other)
		(@check       == other.instance_eval('@check')       &&
		 @error       == other.instance_eval('@error')       &&
		 @details     == other.instance_eval('@details'))
	    end
	    alias == eql?
	end





	attr_reader :testname, :desc, :ns, :ip

	def initialize(testname, desc, ns=nil, ip=nil)
	    @testname	= testname
	    @desc	= desc
	    @ns		= ns
	    @ip		= ip
	end
	

	def eql?(other)
	    self.instance_of?(Result) && other.instance_of?(Result) &&
		self.testname == other.testname                     &&
		self.ns       == other.ns                           &&
		self.ip       == other.ip
	end
	alias == eql?
	
	def hash
	    testname.hash ^ ns.hash ^ ip.hash
	end

	def source
	    if ! @ns.nil?				# NS
	    then @ip.nil? ? "#{@ns}" : "#{@ns}/#{ip}"	# NS/IP
	    else $mc.get('word:generic')		# generic
	    end
	end
    end



    ##
    ## Test that has Succeed
    ##
    class Succeed < Result
	def ok? ; true	; end
    end


    
    ##
    ## Test that has Failed
    ##
    class Failed < Result
	def ok? ; false	; end
    end



    ##
    ## Test that was unable to complete due to Error
    ##
    class Error < Result
	def ok? ; false	; end
    end




    def initialize(network, config, cm, domain)
	@network	= network
	@config		= config
	@cm		= cm
	@domain		= domain

	@cache		= Cache::new
    end

    def dbgmsg(ns=nil, ip=nil)
	$dbg.msg(DBG::TESTDBG) { 
	    func = 'caller_unknown'
	    caller.each { |l|
		if l =~ /`((?:chk|tst)_.*)'/ #` <-- emacs
		    func = $1
		    break
		end
	    }
	    
	    header = if ns.nil? && ip.nil?
		     then func
		     else func + ' [' + [ ns, ip ].collect{|e| e.to_s}.compact.join('/') + ']'
		     end
	    
	    case arg = yield
	    when Array then [ header ] + arg
	    else            [ header, arg ]
	    end
	}
    end

    # Test if 'name' is a cname
    #  If 'name' is inside the current domain, the specified 'ip'
    #   will be used (if 'ip' is nil the first nameserver address
    #   is used)
    #  WARN: this is necessary because the query could be in the
    #        domain being delegated
    #  IDEA: a better way would be to use the cachemanager to fake
    #        the nameserver NS, A and AAAA records retrieved by autoconf
    #        unfortunately we have a NOCACHE option in the debug mode
    def is_cname?(name, ip=nil)
	if name.subdomain_of?(@domain.name) || name.eql?(@domain.name)
	    ip = @domain.addresses[0] if ip.nil?
	else
	    ip = nil
	end
	res = @cm[ip].cname(name)
	res.nil? ? nil : res.cname
    end

    def is_resolvable?(name, ip=nil, domain=@domain.name)
	(( (name.subdomain_of?(domain) || name.eql?(domain))  && !@cm[ip].addresses(name).empty?)   ||
	 ( @cm[ip].rec(@domain.name) && !@cm[ip].addresses(name).empty?)   ||
	 (!@cm[ip].rec(@domain.name) && !@cm[nil].addresses(name).empty?))
    end


    def bestresolverip(name=@domain.name)
	if (ips = @domain.get_resolver_ips(name)).nil?
	then nil
	else ips[0]
	end
    end
    
    def prefix_of(arg,size=nil)
      case arg 
      when Dnsruby::IPv4 
        if size.nil?
          raise RuntimeError, 'Not Implemented Yet'
        else
          if size > arg.address.size * 8
              raise ArgumentError, 'prefix size too big'
          end
          bytes, bits_shift = size / 8, 8 - (size % 8)
          address = arg.address.slice(0, bytes) + 
              ("\0" * (arg.address.size - bytes))
          if arg.address.respond_to?("bytes")
            a = arg.address.bytes.to_a
            a[bytes] = (a[bytes] >> bits_shift) << bits_shift
            address = a.map { |e| e.chr }.join
          else
            address[bytes] = (arg.address[bytes] >> bits_shift) << bits_shift
          end
          Dnsruby::IPv4::new(address.freeze)
        end
      when Dnsruby::IPv6
        if size.nil?
          size = 64
        end
        if size > arg.address.size * 8
            raise ArgumentError, 'prefix size too big'
        end
        bytes, bits_shift = size / 8, 8 - (size % 8)
        address = arg.address.slice(0, bytes) + 
            ("\0" * (arg.address.size - bytes))
        if arg.address.respond_to?("bytes")
          a = arg.address.bytes.to_a
          a[bytes] = (a[bytes] >> bits_shift) << bits_shift
          address = a.map { |e| e.chr }.join
        else
          address[bytes] = (arg.address[bytes] >> bits_shift) << bits_shift
        end
        Dnsruby::IPv6::new(address.freeze)
      else
        raise ArgumentError, "Could not fing the prefix of : #{address}"
      end
    end
    
    def is_valid_hostname?(name)
      name.labels.each { |lbl|
        return false if (lbl.downcase =~ /^-|-$/) # to_s would have put a '\' before '.'
        # have at least one character and is just composed of letters and '.' and '-'
        return false unless (lbl.downcase =~ /^[A-Za-z0-9\-]*$/)
        return false if (lbl.downcase =~ /^\./) # begin with a dot
      }
      true
    end
    
    def is_valid_mbox_address?(name)
        return false unless name.labels.size > 1
        mbox  = name[0].string  # to_s would have put a '\' before '.'
        is_valid_hostname?(Dnsruby::Name::new(name.labels[1..-1]))      &&
            (mbox !~ /[^A-Za-z0-9\._\-~\#]/)      &&
            (mbox !~ /^\.|\.$/)
    end

    #-- Shortcuts -----------------------------------------------
    def const(name)
	@config.constants.fetch(name)
    end

    def rec(ip=nil, dom=@domain.name, force=false)
	@cm[ip].rec(dom, force)
    end

    def soa(ip=nil, dom=@domain.name, force=false)
	@cm[ip].soa(dom, force)
    end

    def ns(ip=nil, dom=@domain.name, force=false)
	@cm[ip].ns(dom, force)
    end

    def mx(ip=nil, dom=@domain.name, force=false)
	@cm[ip].mx(dom, force)
    end

    def any(ip=nil, resource=nil)
	@cm[ip].any(@domain.name, resource)
    end
    
    def addresses(name, ip=nil)
	@cm[ip].addresses(name)
    end
    
    def a(ip, name, force=false)
	@cm[ip].a(name, force)
    end

    def aaaa(ip, name, force=false)
	@cm[ip].aaaa(name, force)
    end

    def cname(ip, name, force=false)
	@cm[ip].cname(name, force)
    end

    def ptr(ip, name)
	@cm[ip].ptr(name)
    end
    
    def dnskey(ip, name=@domain.name, force=false)
      @cm[ip].dnskey(name, force)
    end
    
    def rrsig(ip, resource, name=@domain.name, force=false)
      @cm[ip].rrsig(name, resource, force)
    end
    
    def is_dnssec_mandatory?()
      return @domain.is_dnssec_mandatory
    end
    
    def given_ds()
      return @domain.ds
    end
    
    def given_dnskey()
      return @domain.dnskey
    end
    
    def edns()
      return @cm.edns
    end
end



##
## Hold tests that are generic
##
module CheckGeneric
    def self.family ; 'generic'		; end
end



##
## Hold tests that are directed to an NS entry
##  => take an NS name as argument
##
module CheckNameServer
    def self.family ; 'nameserver'	; end
end



##
## Hold tests that are directed to a DNS running on an IP address
##  => take an NS name and an IP address as argument
##
module CheckNetworkAddress
    def self.family ; 'address'		; end
end

##
## Hold tests that are related to DNSSEC
##
module CheckDNSSEC
    def self.family ; 'dnssec'   ; end
end

##
## Hold tests that are not directed DNS related
##
module CheckExtra
    def self.family ; 'extra'		; end
end
end
