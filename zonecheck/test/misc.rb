# ZCTEST 1.0
# $Id: misc.rb,v 1.37 2010/06/23 12:51:35 chabannf Exp $

# 
# CONTACT     : zonecheck@nic.fr
# AUTHOR      : Stephane D'Alu <sdalu@nic.fr>
#
# CREATED     : 2002/08/02 13:58:17
# REVISION    : $Revision: 1.37 $ 
# DATE        : $Date: 2010/06/23 12:51:35 $
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
#   - move these functions into another file
#

require 'framework'

module CheckNetworkAddress
    ##
    ##
    ##
    class Misc < Test
	with_msgcat 'test/misc.%s'

	#-- Checks --------------------------------------------------
	# DESC:
	def chk_ns_reverse(ns, ip)
	    #ip_name	= Dnsruby::Name::create(ip)
	    ip_name = ip.to_name
	    srv		= rec(ip) ? ip : nil
	    begin
	      return ! ptr(srv, ip_name).empty?
	    rescue Dnsruby::NXDomain
	      return false
	    end
	end

	def chk_ns_matching_reverse(ns, ip)
	    #ip_name	= Dnsruby::Name::create(ip)
      ip_name = ip.to_name
	    srv		= rec(ip) ? ip : nil
      begin
        ptrlist     = ptr(srv, ip_name)
      rescue Dnsruby::NXDomain
        return false
      end
	    return true if ptrlist.empty?
	    ptrlist.each { |rev|
		seen = { rev => true }

		name = rev.rdata
		return true if name == ns

		while name = is_cname?(name, ip)
		    if seen[name]
		    then raise "Loop in CNAME chain when looking for #{rev.ptrdname}"
		    else seen[name] = true
		    end
		    return true if name == ns
		end
	    }

	    false
	end

	# DESC: Ensure coherence between given (param) primary and SOA
	def chk_given_nsprim_vs_soa(ns, ip)
	    mname = soa(ip).mname
	    if @domain.ns[0][0] != mname
		@domain.ns[1..-1].each { |nsname, |
		    return { 'given_primary' => @domain.ns[0][0].to_s,
			     'primary'       => mname.to_s } if nsname == mname }
	    end
	    true
	end
	   
	# DESC: Ensure coherence between given (param) nameservers and NS
	def chk_given_ns_vs_ns(ns, ip)
	    nslist_from_ns    = ns(ip).collect{ |n| n.domainname.to_s.downcase }
	    nslist_from_param = @domain.ns.collect { |n, ips| n.to_s.downcase }
	    return true if nslist_from_ns.unsorted_eql?(nslist_from_param)
	    { 'list_from_ns'    => nslist_from_ns.sort.join(', ').to_s,
	      'list_from_param' => nslist_from_param.sort.join(', ').to_s }
	end

	# DESC: Ensure that a server is not recursive
	def chk_not_recursive(ns, ip)
	    ! rec(ip)
	end

	# DESC: Ensure that a server claiming to be recursive really is it
	def chk_correct_recursive_flag(ns, ip)
	    return true unless rec(ip)
	    
	    namespace = case ip
                  when Dnsruby::IPv4 then "in-addr.arpa."
                  when Dnsruby::IPv6 then "ip6.arpa."
                  else nil
                  end
	    dbgmsg(ns, ip) { 
		'asking SOA for: ' + 
		[ @domain.name.labels[-1] || Dnsruby::Name::create(".").to_s,
		    Dnsruby::Name::create(namespace).to_s ].join(', ')
	    }
      
	    soa(ip, @domain.name.labels[-1] || Dnsruby::Name::create(".")) &&
		soa(ip, Dnsruby::Name::create(namespace))
	end

#	# DESC:
#	def chk_rir_inetnum(ns, ip)
#	    true
#	end

#	# DESC:
#	def chk_rir_route(ns, ip)
#	    true
#	end
	#-- Tests ---------------------------------------------------
	# 
	def tst_recursive_server(ns, ip)
	  begin
	    rec(ip) ? 'true' : 'false'
	  rescue Dnsruby::ResolvError, Dnsruby::ResolvTimeout
	    return 'false'
	  end
	end
    end
end
