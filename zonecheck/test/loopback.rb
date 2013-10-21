# ZCTEST 1.0
# $Id: loopback.rb,v 1.19 2010/06/07 08:51:25 chabannf Exp $

# 
# CONTACT     : zonecheck@nic.fr
# AUTHOR      : Stephane D'Alu <sdalu@nic.fr>
#
# CREATED     : 2002/09/11 11:20:17
# REVISION    : $Revision: 1.19 $ 
# DATE        : $Date: 2010/06/07 08:51:25 $
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


require 'framework'

module CheckNetworkAddress
    ##
    ## Check for loopback network delegation/resolution
    ## 
    class Loopback < Test
	with_msgcat 'test/loopback.%s'

	#-- Constants -----------------------------------------------
	IPv4LoopbackName = Dnsruby::IPv4::create("127.0.0.1").to_name
	IPv6LoopbackName = Dnsruby::IPv6::create("::1").to_name

	#-- Helper --------------------------------------------------
	def ipv4_delegated?(ip)
	    (!soa(ip, Dnsruby::Name::create(IPv4LoopbackName.labels[1..-1])).nil?  ||
	     !soa(ip, Dnsruby::Name::create(IPv4LoopbackName.labels[2..-1])).nil?  ||
	     !soa(ip, Dnsruby::Name::create(IPv4LoopbackName.labels[3..-1])).nil? )
	end

	def ipv6_delegated?(ip)
	    !soa(ip, Dnsruby::Name::create(IPv6LoopbackName.labels[1..-1])).nil?	    
	end

	#-- Checks --------------------------------------------------
	# DESC: loopback network should be delegated
	def chk_loopback_delegation(ns, ip)
	    case ip
	    when Dnsruby::IPv4	then return ipv4_delegated?(ip)
	    when Dnsruby::IPv6	then return ipv4_delegated?(ip) && ipv6_delegated?(ip)
	    end
	    false
	end

	# DESC: loopback host reverse should exists
	def chk_loopback_host(ns, ip)
	    case ip
	    when Dnsruby::IPv4	then return !ptr(ip, IPv4LoopbackName).empty?
	    when Dnsruby::IPv6	then return !ptr(ip, IPv4LoopbackName).empty? &&
		                     !ptr(ip, IPv6LoopbackName).empty?
	    end
	    false
	end
    end
end
