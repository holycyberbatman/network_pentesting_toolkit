# $Id: param.rb,v 1.115 2011/03/11 16:09:18 kmkaplan Exp $

# 
# CONTACT     : zonecheck@nic.fr
# AUTHOR      : Stephane D'Alu <sdalu@nic.fr>
#
# CREATED     : 2002/08/02 13:58:17
# REVISION    : $Revision: 1.115 $ 
# DATE        : $Date: 2011/03/11 16:09:18 $
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
  require 'dbg'
  require 'report'
  require 'publisher'
  require 'msgcat'
  
  
  ##
  ## Parameters of the ZoneCheck application
  ## 
  ## All the subclasses have an 'autoconf' method, which must be
  ## used to finish configuring the class.
  ##
  class Param
    ##
    ## Hold the flags used to describe report output behaviour
    ##
    ## tagonly      : only print tag or information suitable for parsing
    ## one          : only print 1 message
    ## quiet        : don't print extra titles
    ## intro        : display summary about checked domain
    ## testname     : print the name of the test in the report
    ## explain      : explain the reason behind the test (if test failed)
    ## details      : give details about the test failure
    ## testdesc     : print a short description of the test being performed
    ## counter      : display a progress bar
    ## stop_on_fatal: stop on the first fatal error
    ## reportok     : also report test that have passed
    ## fatalonly    : only print fatal errors
    ##
    ## Corrections are silently made to respect the following constraints:
    ##  - 'tagonly' doesn't support 'explain', 'details' (as displaying
    ##     a tag for an explanation is meaningless)
    ##  - 'testdesc' and 'counter' are exclusive
    ##  - 'counter' can be ignored if the display doesn't suppport 
    ##     progress bar animation
    ##  - 'one' ignore 'testname', 'explain', 'details'
    ##  - 'fatalonly' ignore 'reportok'
    ##
    class ReportFlag
      attr_reader :tagonly,  :one,   :quiet
      attr_reader :testname, :intro, :explain, :details
      attr_reader :testdesc, :counter
      attr_reader :stop_on_fatal, :reportok, :fatalonly
      attr_reader :dig
      
      attr_writer :one, :quiet, :intro
      attr_writer :stop_on_fatal, :reportok, :fatalonly
      attr_writer :testname
      attr_writer :dig
      
      def initialize
        @tagonly  = @one                           	= false
        @intro    = @testname = @details = @explain	= false
        @testdesc = @counter			= false
        @stop_on_fatal				= true
        @reportok = @fatalonly			= false
        @dig = false
      end
      
      def tagonly=(val)
        @details = @explain  = false if @tagonly = val
      end
      
      def explain=(val)
        @explain  = val   if !@tagonly
      end
      
      def details=(val)
        @details  = val   if !@tagonly
      end
      
      def testdesc=(val)
        @counter  = false if @testdesc = val
      end
      
      def counter=(val)
        @testdesc = false if @counter = val
      end
      
      def autoconf
        $dbg.msg(DBG::AUTOCONF) {
          flags = []
          flags << 'tagonly'	if @tagonly
          flags << 'one'		if @one
          flags << 'quiet'	if @quiet
          flags << 'intro'	if @intro
          flags << 'testname'	if @testname
          flags << 'explain'	if @explain
          flags << 'details'	if @details
          flags << 'testdesc'	if @testdesc
          flags << 'counter'	if @counter
          flags << 'stop'		if @stop_on_fatal
          flags << 'reportok'	if @reportok
          flags << 'fatalonly'	if @fatalonly
          flags << 'NONE'		if flags.empty?
          "Report flags: #{flags.join('/')}"
        }
      end
    end
    
    
    
    ##
    ## Hold information about the domain to check 
    ##
    ## name      : a fully qualified domain name
    ## ns        : list of nameservers attached to the domain (name)
    ##              output format : [ [ ns1, [ ip1, ip2 ] ],
    ##                                [ ns2, [ ip3 ] ],
    ##                                [ ns3 ] ]
    ##              input  format : ns1=ip1,ip2;ns2=ip3;ns3
    ##              if element aren't specified they will be 'guessed'
    ##              when calling 'autoconf'
    ## addresses : list of ns addresses
    ## cache     : should result be stored in external database (for hooks)
    ##
    class Domain
      def initialize(name=nil, ns=nil)
        clear
        self.name = name unless name.nil?
        self.ns   = ns   unless ns.nil?
      end
      
      attr_reader :cache, :name, :ns, :addresses, :ds, :dnskey, :is_dnssec_mandatory
      attr_writer :cache, :ds, :dnskey, :is_dnssec_mandatory
      
      def clear
        @name      = nil
        @ns        = nil
        @ns_input	 = [ ]
        @addresses = nil
        @cache     = true
        @ds        = nil
        @dnskey    = nil
        @is_dnssec_mandatory = false
      end
      
      # 
      # The policy for caching is (stop on first match):
      #   - the NS have been guessed           => false
      #   - a necessary glue is missing        => false
      #   - an unecessary glue has been given  => false
      #   - everything else                    => true
      #
      def can_cache?
        # purely guessed information
        return false if @ns_input.empty?
        # glue misused
        @ns_input.each { |ns, ips|
	  return false unless (ns == @name || ns.subdomain_of?(@name)) ^ ips.empty? }
        # ok
        true
      end
      
      def name=(domain)
        domain = domain + '.' unless domain =~ /.\.$/
        domain = Dnsruby::Name::create(domain)
        unless domain.absolute?
          raise ArgumentError, $mc.get('xcp_param_fqdn_required')
        end
        @name = domain
      end
      
      def ns=(ns)
        if ns.nil?
          @ns_input = [ ]
          @ns       = nil
          return nil
        end
      
        # Parse inputed NS (and IPs)
        @ns_input = [ ]
        ns.split(/\s*;\s*/).each { |entry|
          ips  = []
          if entry =~ /^(.*?)\s*=\s*(.*)$/
          host_str, ips_str = $1, $2
          if host_str =~ Dnsruby::IPv4::Regex || 
             host_str =~ Dnsruby::IPv6::Regex ||
             !(host_str =~ /^[A-Za-z0-9.-]+$/)
            raise ParamError, $mc.get("param:ns_name") % host_str
          end

          # Canonicalize host names (final dot mandatory)
          host_str = host_str + '.' unless host_str =~ /.\.$/          
          host = Dnsruby::Name::create(host_str)
          ips_str.split(/\s*,\s*|\s+/).each { |str|
            if str =~ Dnsruby::IPv4::Regex
              ips << Dnsruby::IPv4::create(str)
            else
              if str =~ Dnsruby::IPv6::Regex
                ips << Dnsruby::IPv6::create(str)
              else
                raise ArgumentError, "Argument #{str} should be an IP address" 
              end
            end
          }
          else
            if entry =~ Dnsruby::IPv4::Regex || 
               entry =~ Dnsruby::IPv6::Regex ||
               !(entry =~ /^[A-Za-z0-9.-]+$/)
              raise ParamError, $mc.get("param:ns_name") % entry
            end
            # Canonicalize host names (final dot mandatory)
            entry = entry + '.' unless entry =~ /.\.$/
            host = Dnsruby::Name::create(entry)
          end
          @ns_input << [ host, ips ]
        }
        
        # Do a deep copy
        @ns = [ ]
        @ns_input.each { |host, ips| @ns << [ host, ips.dup ] }
        
        # 
        @ns
      end
      
      def autoconf(resolver)
        # Guess Nameservers and ensure primary is at first position
        if @ns.nil?
          $dbg.msg(DBG::AUTOCONF) { "Retrieving NS for #{@name}" }
          begin
            soa = nil
            resolver.query(@name,"SOA").answer.each { |record|
            soa = record if record.class == Dnsruby::RR::IN::SOA
            }
            
            if soa.nil?
              raise ParamError, $mc.get('xcp_param_soa')
            end
            
            primary = soa.mname
            $dbg.msg(DBG::AUTOCONF) {
            "Identified NS primary as #{primary}" }
          rescue Dnsruby::ResolvError, Dnsruby::ResolvTimeout 
            raise ParamError, $mc.get('xcp_param_domain_nxdomain') % @name
          rescue Dnsruby::ResolvError, Dnsruby::ResolvTimeout 
            raise ParamError, $mc.get('xcp_param_soa')
          end
          
          
          begin
            @ns = [ ]
            nameservers = []
            resolver.query(@name,"NS").answer.each { |record|
              nameservers << record.rdata if record.class == Dnsruby::RR::IN::NS
            }
            nameservers.each { |n|
              if n =~ Dnsruby::IPv4::Regex || n =~ Dnsruby::IPv6::Regex
                raise ParamError, $mc.get('xcp_param_nameserver_is_ip')
              end
              if n == primary
              then @ns.unshift([ n, [] ])
              else @ns <<  [ n, [] ]
              end
            }
          rescue Dnsruby::ResolvError, Dnsruby::ResolvTimeout 
            raise ParamError, $mc.get('xcp_param_nameservers_ns')
          end
          
          
          if @ns[0].nil?
            raise ParamError, $mc.get('xcp_param_prim_ns_soa')
          end
        end
        
        # Set cache status
        if @cache
          @cache &&= can_cache?
          $dbg.msg(DBG::AUTOCONF) { "Cache status set to #{@cache}" }
        end
        
        # Guess Nameservers IP addresses
        @ns.each { |ns, ips|
          if ips.empty? then
            $dbg.msg(DBG::AUTOCONF) { "Retrieving IP for NS: #{ns}" }
            begin
              resolver.query(ns.to_s,"A").answer.each { |rr|
                if rr.class == Dnsruby::RR::IN::A
                  ips << rr.address
                end
              }
              resolver.query(ns.to_s,"AAAA").answer.each { |rr|
                if rr.class == Dnsruby::RR::IN::AAAA
                  ips << rr.address
                end
              }
            rescue Dnsruby::ResolvError, Dnsruby::ResolvTimeout 
              
            end
          end
          
          if ips.empty? then
            raise ParamError, 
            $mc.get('xcp_param_nameserver_ips') % [ ns ]
          end
        }
        
        # XXX: doesn't allow to force an IP addresse.
        #	    # Sanity check on given IP addresses
        #	    #  => this is not done for nameservers which are in the 
        #	    #     delegated zone, as we need to perform additional
        #	    #     checks before, there will be an explicit test for it
        #	    #     in the configuration file
        #	    @ns_input.each { |ns, ips|
        #		if !ns.subdomain_of?(@name) && !ips.nil?
        #		    resolved_ips = nil
        #		    begin
        #			$dbg.msg(DBG::AUTOCONF) {"Comparing IP for NS: #{ns}"}
        #			resolved_ips = dns.getaddresses(ns, 
        #							Address::OrderStrict)
        #			
        #			unless ips.unsorted_eql?(resolved_ips)
        # #			    raise ParamError, 
        # #				$mc.get('xcp_param_ns_bad_ips') % ns
        #			end
        #		    rescue Dnsruby::ResolvError
        #		    end
        #		    if resolved_ips.nil? || resolved_ips.empty?
        #			raise ParamError, 
        #			    $mc.get('xcp_param_nameserver_ips') % [ ns ]
        #		    end
        #		end
        #	    }
        
        # Build addresses set
        @addresses = []
        @ns.each { |ns, ips| @addresses.concat(ips) }
      end
      
      def get_resolver_ips(name, prim=false)
        if name.nil? || !((name == @name) || (name.subdomain_of?(@name)))
          nil
          #	    elsif (name.labels.size - @name.labels.size) > 1
          #		raise RuntimeError, "XXX: correct behaviour not decided (#{name})"
        else
          if prim
          then ns[0][1]
          else @addresses
          end
        end
      end
    end
    
    
    
    ##
    ## As the Report class, but allow severity override
    ##
    class ProxyReport
      attr_reader :info, :warning, :fatal
      
      def initialize
        @report_class	= nil
        @info_attrname	= :info
        @warning_attrname	= :warning
        @fatal_attrname	= :fatal
        @report		= nil
        @info		= nil
        @warning		= nil
        @fatal		= nil
      end
      
      def allfatal
        @warning_attrname = @fatal_attrname = :fatal
      end
      
      def allwarning
        @warning_attrname = @fatal_attrname = :warning
      end
      
      def standard
        @warning_attrname	= :warning
        @fatal_attrname	= :fatal
      end
      
      def reporter=(report_class)
        @report_class = report_class
      end
      
      def reporter
        @report_class
      end
      
      def finish
        @report.finish
      end
      
      def autoconf(domain, rflag, publisher)
        # Set publisher class (if not already done)
        if @report_class.nil?
          require 'report/byseverity'
          @report_class = ::Report::BySeverity
        end
        
        # Instanciate report engine
        @report	= @report_class::new(domain, rflag, publisher)
        # Define dealing of info/warning/fatal severity
        @info       = @report.method(@info_attrname).call
        @warning    = @report.method(@warning_attrname).call
        @fatal      = @report.method(@fatal_attrname).call
        
        # Check for 'tagonly' support
        if rflag.tagonly && !@report.tagonly_supported?
          raise ParamError, 
          $mc.get('xcp_param_output_support') % [ 'tagonly' ]
        end
        # Check for 'one' support
        if rflag.one     && !@report.one_supported?
          raise ParamError, 
          $mc.get('xcp_param_output_support') % [ 'one'     ]
        end
        
        # Debug
        $dbg.msg(DBG::AUTOCONF) { "Report using #{reporter}" }
      end
    end
    
    
    
    ##
    ## Hold information necessary for initializing configuration
    ##  process.
    ##
    ## cfgfile: configuration file to use (zc.conf)
    ## testdir: directory where tests are located
    ## profile: allow override of automatic profile selection
    ## preset:  allow selection of a preset configuration
    ##
    class Preconf
      attr_reader :cfgfile, :testdir, :profile, :preset
      attr_writer :cfgfile, :testdir, :profile, :preset
      
      def initialize
        @cfgfile	= $zc_config_file
        @testdir	= ZC_TEST_DIR
        @profile	= nil
        @preset	= nil
      end
      
      def autoconf
        # Debug
        $dbg.msg(DBG::AUTOCONF) { "Configuration file: #{@cfgfile}" }
        $dbg.msg(DBG::AUTOCONF) { "Tests directory: #{@testdir}"    }
        $dbg.msg(DBG::AUTOCONF) { "Asking for profile: #{profile}"  }
        $dbg.msg(DBG::AUTOCONF) { "Asking for preset: #{preset}"    }
      end
    end
    
    
    
    ##
    ## Hold information about the resolver behaviour
    ## 
    ## ipv4    : use IPv4 routing protocol
    ## ipv6    : use IPv6 routing protocol
    ## mode    : use the following mode for new resolvers: STD / UDP / TCP 
    ##
    class Network
      attr_reader :ipv4, :ipv6, :query_mode
      attr_writer :query_mode
      
      def initialize
        @ipv6		= nil
        @ipv4		= nil
        @query_mode		= nil
      end
      
      def ipv6=(bool)
        if bool && ! $ipv6_stack
          raise ParamError, $mc.get('xcp_param_ip_no_stack') % 'IPv6'
        end
        @ipv6 = bool
      end
      
      def ipv4=(bool)
        if bool && ! $ipv4_stack
          raise ParamError, $mc.get('xcp_param_ip_no_stack') % 'IPv4'
        end
        @ipv4 = bool
      end
      
      def address_wanted?(address)
        case address
        when String
          case address
          when Dnsruby::IPv4::Regex then address if ipv4
          when Dnsruby::IPv6::Regex then address if ipv6
          else nil
          end
        when Dnsruby::IPv4 then address if ipv4
        when Dnsruby::IPv6 then address if ipv6
        when Array
          address.collect { |addr| address_wanted?(addr) }.compact
        else nil
        end
      end
      
      def autoconf
        # Select routing protocol (IPv4/IPv6)
        @ipv4 = @ipv6 = true if @ipv4.nil? && @ipv6.nil?
        @ipv4 = false        if @ipv4.nil? || !$ipv4_stack
        @ipv6 = false        if @ipv6.nil? || !$ipv6_stack
        if !@ipv4 && !@ipv6
          raise 'Why are you using this program! (No IP stack selected)'
        end
        # Debug
        $dbg.msg(DBG::AUTOCONF) { 
          routing = [ ]
          routing << 'IPv4' if @ipv4
          routing << 'IPv6' if @ipv6
          routing << 'NONE' if routing.empty?	# => YARGL
          "Routing protocol set to: #{routing.join('/')}"
        }
        
        # Select mode (UDP/TCP/STD)
        @query_mode = "std" if @query_mode.nil?
        # Debug
        $dbg.msg(DBG::AUTOCONF) {
          "Query mode set to: #{@query_mode}" }
      end
    end
    
    
    
    ##
    ## Hold information about local resolver
    ##
    ## local: local resolver to use
    ##
    class Resolver
      attr_reader :local
      
      def initialize
        @local	= nil
        @local_name	= nil
      end
      
      def local=(resolv)
        resolv = resolv.dup.untaint if resolv.tainted?
        @local_name = if resolv.nil? || resolv =~ /^\s*$/
                      then nil
                      else resolv
                      end
        @local = nil
      end
      
      def autoconf
        # Select local resolver
        if @local.nil?
          @local = if @local_name.nil?
                     # Use default resolver
                     Dnsruby::Resolver::new
                   else 
                     # Only accept addresses
                     unless @local_name =~ Dnsruby::IPv4::Regex ||
                       @local_name =~ Dnsruby::IPv6::Regex
                       raise ParamError, 
                       $mc.get('xcp_param_local_resolver')
                     end
                     # Build new resolver
                     Dnsruby::Resolver::new(@local_name)
                   end
        end
        @local.do_caching = false
        @local.dnssec = false
        # Debug
        $dbg.msg(DBG::AUTOCONF) {
          resolver = @local_name || '<default>'
          "Resolver #{resolver}"
        }
      end
    end
    
    
    ##
    ## Hold information about the test
    ## 
    ## list      : has listing of test name been requested
    ## test      : limiting tests to this list
    ## catagories: limiting tests to these categories
    ## desctype  : description type (name, xpl, error, ...)
    ##
    class Test
      attr_reader :list, :tests, :categories, :desctype
      attr_writer :list
      
      def initialize
        @list	      = false
        @tests	    = nil
        @categories	= nil
        @desctype   = nil
      end
      
      def desctype=(string)
        case string
        when MsgCat::NAME, MsgCat::EXPLANATION,
          MsgCat::SUCCESS, MsgCat::FAILURE
          @desctype = string
        else raise ParamError, 
          $mc.get('xcp_param_unknown_modopt') % [string, 'testdesc']
        end
      end
      
      
      def tests=(string)
        @tests = if string.nil? || string =~ /^\s*$/
                 then nil
                 else string.split(/\s*,\s*/)
                 end
      end
      
      def categories=(string)
        return if string =~ /^\s*$/
        @categories = string.split(/\s*,\s*/)
      end
      
      def autoconf
        # Debug
        $dbg.msg(DBG::AUTOCONF) {
          tests = (@tests || [ 'ALL' ]).join(',')
          "Selected tests: #{tests}" }
        $dbg.msg(DBG::AUTOCONF) {
          categories = (@categories || [ '+' ]).join(',')
          "Selected categories: #{categories}" }
        if @desctype
          $dbg.msg(DBG::AUTOCONF) {
            "Test description requested for type: #{@desctype}" }
        end
        if @list
          $dbg.msg(DBG::AUTOCONF) { 'Test listing requested' }
        end
      end
    end
    
    
    ##
    ## Hold information about the publisher
    ##
    ## engine : the publisher to use (write class, read object)
    ##
    class Publisher
      def initialize
        @publisher_class	= nil
        @publisher		= nil
      end
      
      def engine=(klass)
        @publisher_class = klass
      end
      
      def engine
        @publisher
      end
      
      def autoconf(rflag, option)
        # Set publisher class (if not already done)
        if @publisher_class.nil?
          require 'publisher/text'
          @publisher_class = ::Publisher::Text
        end
        
        # Set output publisher
        @publisher = @publisher_class::new(rflag, option, $console.stdout)
        
        $dbg.msg(DBG::AUTOCONF) { "Publish using #{@publisher_class}" }
      end
    end
    
    
    ##
    ## Hold optional input information
    ##
    class Option
      def initialize
        @opt	= { }
      end
      
      def [](key)         ; @opt[key]           ; end
      def []=(key,value)	; @opt[key] = value   ; end
      def delete(key)     ; @opt.delete(key)    ; end
      def clear           ; @opt = { }          ; end
      def each     ; @opt.each { |*a| yield a } ; end 
      
      def <<(args)
        args.strip.split(/\s*,\s*/).each { |arg|
          case arg
          when /^-$/		then self.clear
          when /^-(\w+)$/		then self.delete($1)
          when /^\+?(\w+)$/	then self[$1] = true
          when /^\+?(\w+)=(\w+)$/	then self[$1] = $2
          else raise ArgumentError, 'bad option specification'
          end
        }
        self
      end
      
      def autoconf
        @opt.each { |key, value| 
          $dbg.msg(DBG::AUTOCONF) {
            if value == true	# this is NOT a pleonasm!
            then "Option set: #{key}"
            else "Option set: #{key} = #{value}"
            end
          }
        }
      end
    end
    
    
    ##
    ## Hold information (statistics, ...)
    ##
    class Info
      attr_reader :testingtime, :testcount, :nscount, :profile
      attr_writer :testingtime, :testcount, :nscount, :profile
      
      def initialize
      end
      
      def clear
        @testingtime	= 0.0
        @testcount		= 0
        @nscount		= 0
        @profile		= nil
      end
      
      def autoconf
      end
    end
    
    
    
    ##
    ## Exception: Parameter errors (ie: usage)
    ##
    class ParamError < StandardError
    end
    
    
    
    #
    # ATTRIBUTS
    #
    attr_reader :publisher, :preconf, :network, :resolver, :rflag, 
                :test, :report, :option, :info
    attr_reader :domain, :edns
    attr_writer :domain, :edns
    
    
    
    #
    # Create parameters
    #
    def initialize
      @publisher	= Publisher::new
      @preconf	= Preconf::new
      @network	= Network::new
      @resolver	= Resolver::new
      @test		= Test::new
      @report		= ProxyReport::new
      @domain		= Domain::new
      @rflag		= ReportFlag::new
      @option		= Option::new
      @info		= Info::new
      @edns = "auto"
    end
    
    
      
    #
    # WRITER: error
    #
    def error=(string)
      return if (string = string.strip).empty?
      string.split(/\s*,\s*/).each { |token|
        case token
        when 'af',  'allfatal'	then @report.allfatal
        when 'aw',  'allwarning'	then @report.allwarning
        when 'ds',  'dfltseverity'	then @report.standard
        when 's',   'stop'		then @rflag.stop_on_fatal = true
        when 'ns',  'nostop'	then @rflag.stop_on_fatal = false
        else raise ParamError,
            $mc.get('xcp_param_unknown_modopt') % [ token, 'error' ]
        end
      }
    end
    
    #
    # WRITER: verbose
    #
    def verbose=(string)
      return if (string = string.strip).empty?
      string.split(/\s*,\s*/).each { |token|
        action = case token[0]
                 when ?!, ?-  then token = token[1..-1] ; false
                 when ?+      then token = token[1..-1] ; true
                 else	                                    true
                 end
        
        case token
        when 'i', 'intro'     then @rflag.intro	= action
        when 'n', 'testname'  then @rflag.testname	= action
        when 'x', 'explain'   then @rflag.explain	= action
        when 'd', 'details'   then @rflag.details	= action
        when 'o', 'reportok'  then @rflag.reportok	= action
        when 'f', 'fatalonly' then @rflag.fatalonly	= action
        when 't', 'testdesc'  then @rflag.testdesc	= action
        when 'c', 'counter'   then @rflag.counter	= action
        when 'g', 'dig'       then @rflag.dig = action
        else raise ParamError,
            $mc.get('xcp_param_unknown_modopt') % [ token, 'verbose' ]
        end
      }
    end
    
    #
    # WRITER: output
    #
    def output=(string)
      return if (string = string.strip).empty?
      string.split(/\s*,\s*/).each { |token|
        case token
        when 'bs', 'byseverity'
          require 'report/byseverity'
          @report.reporter  = Report::BySeverity
        when 'bh', 'byhost'
          require 'report/byhost'
          @report.reporter  = Report::ByHost
        when 't', 'text'
          require 'publisher/text'
          @publisher.engine = ::Publisher::Text
        when 'h', 'html'
          require 'publisher/html'
          @publisher.engine = ::Publisher::HTML
        when 'x', 'xml'
          require 'publisher/xml'
          @publisher.engine = ::Publisher::XML
        else
          raise ParamError,
              $mc.get('xcp_param_unknown_modopt') % [ token, 'output' ]
        end
      }
    end
    
    #
    # WRITER: transp
    #
    def transp=(string)
      return if (string = string.strip).empty?
      string.split(/\s*,\s*/).each { |token|
        case token
        when '4', 'ipv4'	then @network.ipv4 = true
        when '6', 'ipv6'	then @network.ipv6 = true
        when 'u', 'udp'	
              @network.query_mode = "udp"
        when 't', 'tcp'	
              @network.query_mode = "tcp"
        when 's', 'std'	
              @network.query_mode = "std"
        else raise ParamError,
              $mc.get('xcp_param_unknown_modopt') % [token, 'transp']
        end
      }
    end
    
    def securedelegation=(string)
      if (string = string.strip).empty?
        @domain.is_dnssec_mandatory = true
      else
        array = string.split(/\s*,\s*/)
        if array.size == 1 || array.size == 2
          array.each { |token|
            if token =~ /^DNSKEY:/
              token = token.gsub(/DNSKEY:/, '')
              rr = Dnsruby::RR::DNSKEY.new()
              rr.init_defaults
              rr.key = token
              unless @domain.dnskey
                @domain.dnskey = []
              end
              @domain.dnskey << rr
            elsif token =~ /^DS:/
              token = token.gsub(/DS:/,'')
              ds = token.split(/\s*:\s*/)
              unless ds.size == 2
                raise ParamError, 
                  "Syntax of DS argument should be DS:your_ds:the_hash_algorithm\n"
              end
              rr = Dnsruby::RR::DS.new()
              rr.init_defaults
              rr.digest= ds[0]
              rr.digest_type= ds[1]
              rr.digestbin = [rr.digest].pack("H*")
              unless @domain.ds
                @domain.ds = []
              end
              @domain.ds << rr
            elsif token =~ /^DS-RDATA:/
              token = token.gsub(/DS-RDATA:/,'')
              rr = Dnsruby::RR::DS.new()
              rr.from_string(token)
              unless @domain.ds
                @domain.ds = []
              end
              @domain.ds << rr
            else
              raise ParamError,
                "See man page for syntax of --securedelegation option"
            end
          }
        else
          raise ParamError,
            $mc.get('param_too_many_arguments') % [arra.size.to_s, 'sd']
        end
        @domain.is_dnssec_mandatory = true
      end
    end
  end

end
