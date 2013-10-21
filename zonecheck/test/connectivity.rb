# ZCTEST 1.0
# $Id: connectivity.rb,v 1.24 2010/06/07 08:51:25 chabannf Exp $

# 
# CONTACT     : zonecheck@nic.fr
# AUTHOR      : Stephane D'Alu <sdalu@nic.fr>
#
# CREATED     : 2002/08/02 13:58:17
# REVISION    : $Revision: 1.24 $ 
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

#####
#
# WARN:
#   - 'chk_icmp' contains system dependant 'ping' command
#      although -q and -c option seems to be fairly standard,
#      unfortunately 'ping' is not part of POSIX
# 
# OPEN:
#   - 'chk_udp' perhaps used a SOA request instead of a 'server status'
#     in case the tested DNS uses view
#
# BUGFIX:
#   - chk_udp: recvfrom reject datagram bigger than the requested size
#              instead of copying the beginning
#     using the NResolv::DNS::UDPSize instead of 1 byte
#

require 'framework'
require 'timeout'


module CheckNetworkAddress
    ##
    ## Check nameserver connectivity (ICMP, UDP, TCP)
    ## 
    ## - as request are directly made to the DNS (no CacheManager)
    ##   the tests won't be affected by the transport flags
    ## 
    class Connectivity < Test
	with_msgcat 'test/connectivity.%s'

	def initialize(*args)
	    super(*args)
	    @ping4_cmd = const('ping4')
	    @ping6_cmd = const('ping6')
	end

	#-- Checks --------------------------------------------------
	# DESC: Test TCP connectivity with DNS server
	def chk_tcp(ns, ip)
	    # The idea is to open a TCP connection
	    #  if no one is listening          => Errno::ECONNREFUSED
	    #  if there is a firewal (timeout) => Errno::EINVAL
	    #                                     Errno::ECONNRESET
	    # The total timeout has been forced to 8 seconds
	    #  as with the chk_udp test
	    msg_dr = Dnsruby::Message::new(@domain.name.to_s,"ANY")
	    rawmsg_dr = msg_dr.encode()
	    
	    sock	= nil
	    begin
		timeout(8) {
		    sock  = TCPSocket::new(ip.to_s, 53)
		    sock.write([rawmsg_dr.length].pack('n'))
        sock.write(rawmsg_dr)
        lenhdr  = sock.read(2)
        return false if lenhdr.nil? || lenhdr.size != 2
        len   = lenhdr.unpack('n')[0]
        reply = sock.read(len)
		}
		true
	    rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EINVAL,
		    TimeoutError
		false
	    ensure
		sock.close unless sock.nil?
	    end
	end

	# DESC: Test UDP connectivity with DNS server
	def chk_udp(ns, ip)
	    # The idea is to send 25 'query' concerning the domain in 5 seconds
	    #  if we received one answer within 8 seconds (dont care about 
	    #  its content, we consider it sucessful)
      msg_dr = Dnsruby::Message::new(@domain.name.to_s,"ANY")
      rawmsg_dr = msg_dr.encode()
	    sock	= nil
	    thr		= nil
	    begin
	      case ip
	      when Dnsruby::IPv4 
          protocol = Socket::AF_INET
	      when Dnsruby::IPv6
	        protocol = Socket::AF_INET6
	      else
	        protocol = nil
	        raise ArgumentError, 'Argument should be an address'
	      end
		sock = UDPSocket::new(protocol)
		sock.connect(ip.to_s, 53)
		thr = Thread::new {
		    (1..25).each { sock.write(rawmsg_dr) ; sleep(0.2) }
		}
		timeout(8) { sock.recv(512) }
		true
	    rescue Errno::ECONNREFUSED, TimeoutError
		false
	    ensure
		thr.kill   unless thr.nil?
		sock.close unless sock.nil?
	    end
	end

	# DESC: Test if host is alive (watch for firewall)
	def chk_icmp(ns, ip)
	    # Build ping command
	    ping_tmpl = case ip
			when Dnsruby::IPv4 then @ping4_cmd
			when Dnsruby::IPv6 then @ping6_cmd
			else raise 'INTERNAL: Unknown address format'
			end
	    ping_cmd = ping_tmpl % [ ip.to_s ]

	    # Do ping
	    dbgmsg(ns, ip) { "Executing: #{ping_cmd}" }
	    system(ping_cmd)
	end
    end
end
