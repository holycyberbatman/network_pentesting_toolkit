# $Id: byseverity.rb,v 1.15 2010/06/21 09:34:44 chabannf Exp $

# 
# CONTACT     : zonecheck@nic.fr
# AUTHOR      : Stephane D'Alu <sdalu@nic.fr>
#
# CREATED     : 2002/08/02 13:58:17
# REVISION    : $Revision: 1.15 $ 
# DATE        : $Date: 2010/06/21 09:34:44 $
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

require 'report'
require 'config'

module Report
    ##
    ## Sorting by severity
    ##
    class BySeverity < Template
	def display_std
	    catlist = []
	    if !@rflag.fatalonly
		catlist << @ok   if @rflag.reportok
		catlist << @info << @warning
	    end
	    catlist << @fatal

	    allempty = true
	    catlist.each { |e| allempty &&= e.empty? }
	    if !allempty
		@publish.diag_start() unless @rflag.quiet
		
		catlist.each { |cat|
		    display(cat.list, cat.severity) }
	    end
	    
	    @publish.status(@domain.name, 
			    @info.count, @warning.count, @fatal.count)
	end

	private
	def display(list, severity)
	    return if list.nil? || list.empty?

	    if !@rflag.tagonly && !@rflag.quiet
		severity_tag	=  ZoneCheck::Config.severity2tag(severity)
		l10n_severity	= $mc.get("word:#{severity_tag}")
		@publish.diag_section(l10n_severity)
	    end
		
	    nlist = list.dup
	    while ! nlist.empty?
		# Get test result
		res		= nlist.shift
		
		# Initialize 
		whos		= [ res.source ]
		desc		= res.desc.clone
		testname	= res.testname
		
		# Look for similare test results
		nlist.delete_if { |a|
		    whos << a.source if ((a.testname == res.testname) && 
				         (a.desc == res.desc))
		}
		
#	  if whos.unsorted_eql?(@ns_list)
#	    whos = [$mc.get('report:all_servers')]
#	  end
		# Publish diagnostic
		@publish.diagnostic(severity, testname, desc, whos)
	    end
	end
    end
end
