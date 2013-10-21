# ZCTEST 1.0
# $Id: rootserver.rb,v 1.21 2010/06/08 09:15:40 chabannf Exp $

# 
# CONTACT     : zonecheck@nic.fr
# AUTHOR      : Stephane D'Alu <sdalu@nic.fr>
#
# CREATED     : 2002/08/02 13:58:17
# REVISION    : $Revision: 1.21 $ 
# DATE        : $Date: 2010/06/08 09:15:40 $
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
require 'yaml'



module CheckNetworkAddress
  class RootServerList
    def initialize(rootserver)
      @rootserver = { }
      rootserver.each { |k, v|
          @rootserver[Dnsruby::Name::create(k)] =
        v.collect { |addr| if addr =~ Dnsruby::IPv4::Regex
          Dnsruby::IPv4::create(addr)
        elsif addr =~ Dnsruby::IPv6::Regex
          Dnsruby::IPv6::create(addr)
        end
          } }
      end
    
        def [](idx) ; @rootserver[idx]      ; end
        def size  ; @rootserver.size      ; end
        def each  ; @rootserver.each { |k,v| yield(k,v) } ; end 
        def keys  ; @rootserver.keys      ; end
    
        def self.from_hintfile(filename=nil)
          filename = "#{$zc_config_dir}/rootservers" if filename.nil?
      File::open(filename) { |io|
          return RootServerList::new(YAML::load(io)) }
        end
    
        ICANN = RootServerList::new({ 
      'a.root-servers.net.' => [ '198.41.0.4'     ],
      'b.root-servers.net.' => [ '128.9.0.107'    ],
      'c.root-servers.net.' => [ '192.33.4.12'    ],
      'd.root-servers.net.' => [ '128.8.10.90'    ],
      'e.root-servers.net.' => [ '192.203.230.10' ],
      'f.root-servers.net.' => [ '192.5.5.241'    ],
      'g.root-servers.net.' => [ '192.112.36.4'   ],
      'h.root-servers.net.' => [ '128.63.2.53'    ],
      'i.root-servers.net.' => [ '192.36.148.17'  ],
      'j.root-servers.net.' => [ '192.58.128.30'  ],
      'k.root-servers.net.' => [ '193.0.14.129'   ],
      'l.root-servers.net.' => [ '199.7.83.42'   ],
      'm.root-servers.net.' => [ '202.12.27.33'   ] })
    
        Default = (Proc::new {
               rootserver = ICANN
               if f = $rootserver_hintfile
             begin
                 rootserver = RootServerList.from_hintfile(f)
             rescue YAML::ParseError,SystemCallError => e
                 Dbg.msg(DBG::CONFIG, 
                   "Unable to read/parse rootserver hint file (#{e})")
             end
               end
               rootserver
           }).call
    
        @@current = Default
        def self.current=(rs) ; @@current = rs  ; end
        def self.current    ; @@current   ; end
    end
    
    class RootServer < Test
	with_msgcat 'test/rootserver.%s'

	#-- Checks --------------------------------------------------
	# DESC: root server list should be available
	def chk_root_servers(ns, ip)
	    ! ns(ip, Dnsruby::Name::create(".")).nil?
	end

	# DESC: root server list should be coherent with ICANN
	def chk_root_servers_ns_vs_icann(ns, ip)
	    rs_list  = ns(ip, Dnsruby::Name::create(".")).collect { |n| n.domainname}
	    ref_list = RootServerList.current.keys
	    unless rs_list.unsorted_eql?(ref_list)
		return { 'rs_list'  => rs_list.collect{|e| e.to_s}.join(', '),
		'ref_list' => ref_list.collect{|e| e.to_s}.join(', ') }
	    end
	    true
	end

	# DESC: root server addresses should be coherent with ICANN
	def chk_root_servers_ip_vs_icann(ns, ip)
	    RootServerList.current.each { |rs, ips|
        rs_addr = [] 
        addresses(rs, ip).each{ |rr|
          rs_addr << rr.address
        }
		unless rs_addr.unsorted_eql?(ips)
		    return { 'rs'       => rs.to_s,
		      'rs_addr'  => rs_addr.collect{|e| e.to_s}.join(', '),
			     'ref_addr' => ips.collect{|e| e.to_s}.join(', ') }
		end
	    }
	    true
	end
    end
end

