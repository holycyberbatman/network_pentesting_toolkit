# $Id: dbg.rb,v 1.30 2010/06/23 12:03:59 chabannf Exp $

# 
# CONTACT     : zonecheck@nic.fr
# AUTHOR      : Stephane D'Alu <sdalu@nic.fr>
#
# CREATED     : 2002/09/16 13:31:29
# REVISION    : $Revision: 1.30 $ 
# DATE        : $Date: 2010/06/23 12:03:59 $
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
require 'thread'


##
## Debugging
##
class DBG
    #
    # Debugging types
    #
    INIT	= 0x0001	# Initialisation
    LOCALE	= 0x0002	# Localization / Internationalisation
    CONFIG	= 0x0004	# Configuration
    AUTOCONF	= 0x0008	# Autoconf
    LOADING	= 0x0010	# Loading tests
    TESTS	= 0x0020	# Tests performed
    TESTDBG	= 0x0040	# Debugging messages from tests
    CACHE_INFO	= 0x0400	# Information about cached object
    DBG		= 0x0800	# Debugger itself

    CRAZYDEBUG	= 0x1000	# Crazy Debug, don't try it...
    DNSRUBY	= 0x2000	# Dnsruby debugging messages
    NOCACHE	= 0x4000	# Disable caching
    DONT_RESCUE	= 0x8000	# Don't try to rescue exceptions

    #
    # Tag associated with some types
    #
    Tag = { 
	INIT		=> 'init',
	LOCALE		=> 'locale',
	CONFIG		=> 'config',
	AUTOCONF	=> 'autoconf',
	LOADING		=> 'loading',
	TESTS		=> 'tests',
	TESTDBG		=> 'testdbg',
	CACHE_INFO	=> 'cache',
	DBG		=> 'dbg'
    }


    #
    # Initializer
    #
    def initialize(lvl=0, output=$stderr)
	@output = output
	@lvl    = lvl
	@mutex	= Mutex::new
  @old_messages = []
	msg(DBG) { "Debugger initialized at level %0x" % @lvl }
    end


    #
    # Test if debug is enabled for that type
    #
    def enabled?(type) 
	@lvl & type != 0
    end
    alias [] enabled?


    #
    # Enable debugging for the specified type
    #
    def []=(type, enable)
	self.level = enable ? @lvl | type : @lvl & ~type
    end


    #
    # Change debugging level
    #
    def level=(lvl)
	old_crazydebug	= enabled?(CRAZYDEBUG)
	old_dnsruby	= enabled?(DNSRUBY)

	# parsing
	case lvl
	when String then @lvl = lvl =~ /^0x/ ? lvl.hex : lvl.to_i
	when Fixnum then @lvl = lvl
	else raise ArgumentError, "unable to interprete: #{lvl}"
	end
	
	# message
	msg(DBG) { "Setting level to 0x%0x" % lvl }


	# enable/disable Dnsruby
	if enabled?(DNSRUBY) ^ old_dnsruby
    Dnsruby::TheLog.level = Logger::DEBUG if enabled?(DNSRUBY)
	end

	# enable/disable CrazyDebug
	if enabled?(CRAZYDEBUG) ^ old_crazydebug
	    dbgfunc = if enabled?(CRAZYDEBUG)
			  proc { |event, file, line, id, binding, classname|
				@output.printf "%8s %s:%-2d %10s %8s\n", 
    				event, file, line, id, classname }
		      else
			  nil
		      end
	    set_trace_func(dbgfunc)
	end
	    failed_messages = @old_messages
      
      @mutex.synchronize {
        @old_messages = []
      }
      failed_messages.each {|type,msg|
        msg(type,msg) unless msg.nil?
      }
    end


    #
    # Print debugging message
    # WARN: It is adviced to use a block instead of the string 
    #       second argument, as this will provide a lazy evaluation
    #
    def msg(type, arg=nil)

	unless block_given? ^ !arg.nil?
	    raise ArgumentError, 'either string or block should be given'
	end
	arg = yield if block_given?
	
	arg = arg.to_s
  unless enabled?(type)
    @mutex.synchronize {
      @old_messages << [type,arg]
	  }
	  return 
	end
	@mutex.synchronize {
	    case arg
	    when Array
		case arg.size
		when 0
		    raise ArgumentError, 'the array argument must not be empty'
		when 1
		    @output.puts "DBG[#{Tag[type]}]: #{arg[0]}"
		else
		    tag       = "DBG[#{Tag[type]}]"
		    tagfiller = " " * tag.size
		    @output.puts "#{tag}: #{arg[0]}"
		    arg[1..-1].each { |l|
			@output.puts "#{tagfiller}| #{l}" }
		end
	    else
		@output.puts "DBG[#{Tag[type]}]: #{arg}"
	    end
	}
    end


    def self.status2str(status, ok=true)
	case status
	when FalseClass, TrueClass then status == ok ? 'passed' : 'failed'
	when NilClass,   Exception then 'exception'
	else                            'n/a'
	end
    end
end
end
