# ZCTEST 1.0
# $Id: mail.rb,v 1.40 2010/10/22 14:21:22 bortzmeyer Exp $

# 
# CONTACT     : zonecheck@nic.fr
# AUTHOR      : Stephane D'Alu <sdalu@nic.fr>
#
# CREATED     : 2002/09/25 19:14:21
# REVISION    : $Revision: 1.40 $ 
# DATE        : $Date: 2010/10/22 14:21:22 $
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

#
# TODO: remove temporary hack where we are looking at the local resolver
#       due to bestresolverip not correctly implemented
#

require 'timeout'
require 'framework'
require 'mail'


module CheckExtra
    ##
    ## Check domain NS records
    ##
    class Mail < Test
	with_msgcat 'test/mail.%s'

	CONNECTION_TIMEOUT = 20

	#-- Initialisation ------------------------------------------
	def initialize(*args)
	    super(*args)
	    @fake_dest = const('fake_mail_dest')
	    @fake_from = const('fake_mail_from')
	    @fake_user = const('fake_mail_user')
	    @fake_host = const('fake_mail_host')
	    @timeout_open    = const('smtp:open:timeout').to_i
	    @timeout_session = const('smtp:session:timeout').to_i
	end

	#-- Shortcuts -----------------------------------------------
	def bestmx(name)
    begin
      pref, exch = 65536, nil

      mxlist = mx(bestresolverip(name), name)
      mxlist = mx(nil, name) if mxlist.empty?
      return nil if mxlist.nil?
      mxlist.each { |m|
    if m.preference < pref
        pref, exch = m.preference, m.exchange
    end
      }
      exch
    rescue Dnsruby::NXDomain
      nil
    end
	end

	def mhosttest(mdom, mhost, dbgio=nil)
	    # Mailhost and IP 
	    mip   = addresses(mhost, bestresolverip(mhost))[0]
	    mip   = addresses(mhost, nil)[0] if mip.nil?
	    raise "No host servicing mail for domain #{mdom}" if mip.nil?

	    # Execute test on mailhost
	    mrelay =  ZoneCheck::Mail::new(mdom, mip.rdata.to_s, dbgio)
	    mrelay.open(@timeout_open)
	    begin
              Timeout::timeout(@timeout_session) {
		mrelay.banner
		mrelay.helo(@fake_host)
		mrelay.fake_info(@fake_user, @fake_dest, @fake_from)
		yield mrelay
                mrelay.quit
              }
	    ensure
		mrelay.close
	    end
	end
	
	
	def openrelay(mdom, mhost)
	    status = nil
	    begin
		mhosttest(mdom, mhost) { |mrelay| 
		    return status = mrelay.test_openrelay }
	    ensure
		dbgmsg { 
		    [ "not an openrelay : #{DBG.status2str(status, false)}",
			"  on domain #{mdom.to_s} using relay #{mhost.to_s}" ]
		}
	    end
	end

	def testuser(user, mdom, mhost)
	    status = nil
	    dbgio  = []
	    begin
		mhosttest(mdom, mhost, dbgio) { |mrelay| 
		    return status = mrelay.test_userexists(user) }
	    ensure
		dbgmsg { 
		    [ "mail for user #{user.to_s} : #{DBG.status2str(status)}",
			"  on domain #{mdom.to_s} using relay #{mhost.to_s}" ] + dbgio
		}
	    end
	end

	#-- Checks --------------------------------------------------
	# DESC: Check that the best MX for hostmaster is not an openrelay
	def chk_mail_openrelay_hostmaster
	  # TODO
	    rname = soa(bestresolverip).rname
      mdom  = Dnsruby::Name::create(".") 
	    mdom  = Dnsruby::Name::create(rname.labels[1..-1]) if rname.labels.size > 1
	    
	    mhost = bestmx(mdom) || mdom
	    return true unless openrelay(mdom, mhost)
	    { 'mailhost'   => mhost.to_s,
	      'hostmaster' => "#{rname[0].string}@#{mdom.to_s}",
	      'from_host'  => @fake_from.to_s,
	      'to_host'    => @fake_dest.to_s }
	end

	# DESC: Check that the best MX for the domain is not an openrelay
	def chk_mail_openrelay_domain
	  # TODO
	    mdom  = @domain.name
	    mhost = bestmx(mdom) || mdom
	    return true unless openrelay(mdom, mhost)
	    { 'mailhost'   => mhost.to_s,
	      'from_host'  => @fake_from.to_s,
	      'to_host'    => @fake_dest.to_s }
	end

	# DESC: Check that hostmaster address is valid
	def chk_mail_delivery_hostmaster
	    # TODO
	    rname = soa(bestresolverip).rname
	    mdom  = Dnsruby::Name::new(rname.labels[1..-1])
	    user  = "#{rname[0].string}@#{mdom}"

	    mxlist = mx(bestresolverip(mdom), mdom)
	    mxlist = mx(nil, mdom) if mxlist.empty?
	    mxlist.sort! { |a,b|
		a.preference <=> b.preference }

	    if mxlist.empty?
		return true if testuser(user, mdom, mdom)
	    else
		mxlist.each { |m|
		    begin
			return true if testuser(user, mdom, m.exchange)
		    rescue TimeoutError, Errno::ECONNREFUSED
		    end
		}
	    end
	    { 'hostmaster' => user.to_s, 
	      'mxlist'     => mxlist.collect { |mx| mx.exchange.to_s}.join(', ')}
	end
	
	# DESC: check for MX or A
	def chk_mail_mx_or_addr
	    ip = bestresolverip
	    begin
	    !mx(ip).empty? || !addresses(@domain.name, ip).empty?
	    rescue Dnsruby::NXDomain
	      false
	    end
	end

	# DESC: Check that postmaster address is valid
	def chk_mail_delivery_postmaster
	  # TODO
	    mdom  = @domain.name
	    user  = "postmaster@#{mdom}"

	    mxlist = mx(bestresolverip(mdom), mdom)
	    mxlist = mx(nil, mdom) if mxlist.empty?
	    mxlist.sort! { |a,b|
		a.preference <=> b.preference }

	    if mxlist.empty?
		return true if testuser(user, mdom, mdom)
	    else
		mxlist.each { |m|
		    begin
			return true if testuser(user, mdom, m.exchange)
		    rescue TimeoutError, Errno::ECONNREFUSED
		    end
		}
	    end
	    return false
	    { 'postmaster' => user.to_s,
	      'mxlist'     => mxlist.collect { |mx| mx.exchange.to_s }.join(', ') }
	end

	# DESC:
	def chk_mail_hostmaster_mx_cname
	    rname = soa(bestresolverip).rname
	    mdom  = Dnsruby::Name::create(rname.labels[1..-1]) if rname.labels.size > 1
	    mhost = bestmx(mdom)
	    return true if mhost.nil?	# No MX
	    ! is_cname?(mhost) 
	end

	#-- Tests ---------------------------------------------------
	# 
	def tst_mail_delivery
	  begin
	    ip = bestresolverip
	    if    !mx(ip).empty?			then 'MX'
	    elsif !addresses(@domain.name, ip).empty?	then 'A'
	    else					     'nodelivery'
	    end
	  rescue Dnsruby::ResolvError, Dnsruby::ResolvTimeout
	    return 'nodelivery'
	  end
	end
    end
end
