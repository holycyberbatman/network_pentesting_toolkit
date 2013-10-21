# ZCTEST 1.0
# $Id: nameserver.rb,v 1.21 2010/06/07 08:51:25 chabannf Exp $

# 
# CONTACT     : zonecheck@nic.fr
# AUTHOR      : Stephane D'Alu <sdalu@nic.fr>
#
# CREATED     : 2002/08/02 13:58:17
# REVISION    : $Revision: 1.21 $ 
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

module CheckNameServer
    ##
    ## Check accessibility of nameserver
    ## 
    ## - these tests are performed without contacting the nameserver
    ##   (see modules CheckNetworkAddress for that)
    ##
    class ServerAccess < Test
	with_msgcat 'test/nameserver.%s'

	BOGON_IP = Dnsruby::IPv4::create('127.0.0.2')

	#-- Initialization ------------------------------------------
	def initialize(*args)
	    super(*args)

	    @cache.create(:ip)
	end

	#-- Shortcuts -----------------------------------------------
	def ip(ns)
	    @cache.use(:ip, ns) {
		@domain.ns.assoc(ns)[1] }
	end

	#-- Checks --------------------------------------------------
	# DESC: Nameserver IP addresses should be public!
	def chk_ip_private(ns)
	    ip(ns).each { |addr| 
	      case addr
  	      when Dnsruby::IPv4
            # 10.0.0.0     -  10.255.255.255   (10/8       prefix)
            # 172.16.0.0   -  172.31.255.255   (172.16/12  prefix)
            # 192.168.0.0  -  192.168.255.255  (192.168/16 prefix)
            bytes = addr.address.unpack('CCCC')
            return false if (((bytes[0] == 10))                            ||
              ((bytes[0] == 172) && (bytes[1]&0xf0 == 16))  ||
              ((bytes[0] == 192) && (bytes[1] == 168)))
  	      when Dnsruby::IPv6
  	        # TODO 
            return false if false
  	      else
  	        raise ArgumentError, 'Argument should be an address'
	      end
      }
      return true
	end
	
	#-- Checks --------------------------------------------------
  # DESC: Nameserver IP addresses should not be local
  def chk_ip_local(ns)
      ip(ns).each { |addr| 
        case addr
          when Dnsruby::IPv4
            # 127.0.0.0     -  127.255.255.255   (127/8       prefix)
            bytes = addr.address.unpack('CCCC')
            return false if (bytes[0] == 127)
          when Dnsruby::IPv6
            # TODO 
            return false if false
          else
            raise ArgumentError, 'Argument should be an address'
        end
      }
      return true
  end


	# DESC:
	def chk_ip_bogon(ns)
	    bogon = []
	    ip(ns).each { |addr|
	      name = ""
	      case addr
	      when Dnsruby::IPv4
          name = ('%d.%d.%d.%d' % addr.address.unpack('CCCC').reverse) +
                         '.bogons.cymru.com.'
	      when Dnsruby::IPv6
          name = addr.address.unpack("H32")[0].split(//).reverse.join(".") + '.bogons.cymru.com.'
  	    else
  	      raise ArgumentError, 'Argument should be an address'
  	    end
		bname = Dnsruby::Name::create(name)
		begin
		    case addr
		    when Dnsruby::IPv4
			@cm[nil].addresses(bname).each { |baddr|
			    if baddr == BOGON_IP
				bogon << addr 
				break
			    end
			}
		    end
		rescue Dnsruby::NXDomain => e
		  
		end
	    }
	    return true if bogon.empty?
      { 'addresses' => bogon.collect{|e| e.to_s}.join(', ').to_s }
	end
    end
end
