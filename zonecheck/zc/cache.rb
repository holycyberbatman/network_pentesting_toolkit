# $Id: cache.rb,v 1.14 2010/06/23 12:03:26 chabannf Exp $

# 
# CONTACT     : zonecheck@nic.fr
# AUTHOR      : Stephane D'Alu <sdalu@nic.fr>
#
# CREATED     : 2002/08/02 13:58:17
# REVISION    : $Revision: 1.14 $ 
# DATE        : $Date: 2010/06/23 12:03:26 $
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
require 'sync'
require 'dbg'


##
##
##
class Cache
    Nothing = Object::new	# Another way to express nil

    #
    # Initialize the cache mechanisme
    #
    def initialize(name='0x%x'%__id__)
	@name  = name
	@mutex = Sync::new
	@list  = {}
    end


    #
    # Is caching enabled?
    #
    def enabled?
	! $dbg.enabled?(DBG::NOCACHE)
    end


    #
    # Clear the items (all if none specified)
    #
    def clear(*items)
	@mutex.synchronize {
	    # Clear item content
	    list = items.empty? ? @list.keys : items
	    list.each { |item| 
		# Sanity check
		if ! @list.has_key?(item)
		    raise ArgumentError, "Cache item '#{item}' not defined"
		end
		
		# Clear 
		@list[item] = {} 
	    }
	}
    end


    #
    # Define cacheable item
    #
    def create(*items)
	items.each { |item| 
	    # Sanity check
	    if @list.has_key?(item)
		raise ArgumentError, "Cache item '#{item}' already defined"
	    end
	    # Create item
	    @list[item] = {}
	}
    end


    #
    # Use a cacheable item
    #
    def use(item, args=nil, force=false)
	# Sanity check
	if ! @list.has_key?(item)
	    raise ArgumentError, "Cache item '#{item}' not defined"
	end

	# Caching enabled?
	return yield unless enabled?
	
	# Compute key to use for retrieval
	key = case args
	      when NilClass then nil
	      when Array    then case args.length
				 when 0 then nil
				 when 1 then args[0]
				 else        args
				 end
	      else               args
	      end

	# Retrieve information
	computed, r = nil, nil
	begin
	@mutex.synchronize {
	    r		= @list[item][key]
	    computed	= force || r.nil?
	    if computed
		r = yield
		r = Nothing if r.nil?
		@list[item][key] = r
	    end
	    r = nil if r == Nothing
	}
  rescue Sync_m::Err::UnknownLocker => e
    $dbg.msg(DBG::INIT) { "An error occured on the cache mutex: " + e }
  end

	# Debugging information
	$dbg.msg(DBG::CACHE_INFO) {
	    l = case args
		when NilClass then "#{item}"
		when Array    then case args.length
				   when 0 then "#{item}"
				   when 1 then "#{item}[#{args[0].to_s}]"
				   else        "#{item}[#{args.collect{|e| e.to_s}.join(',')}]"
				   end
		else               "#{item}[#{args.to_s}]"
		end
		    
	    if computed
	    then "computed(#{@name}): #{l}=#{r}"
	    else "cached  (#{@name}): #{l}=#{r}"
	    end
	}

	# Returns result
	r
    end
end
end