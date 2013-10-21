# $Id: locale.rb,v 1.5 2010/06/29 12:08:35 chabannf Exp $

# 
# CONTACT     : zonecheck@nic.fr
# AUTHOR      : Stephane D'Alu <sdalu@nic.fr>
#
# CREATED     : 2003/08/29 14:10:22
# REVISION    : $Revision: 1.5 $ 
# DATE        : $Date: 2010/06/29 12:08:35 $
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
class Locale
    LANGRegex	= /^(\w+?)(?:_(\w+))?(?:\.([\w\-]+))?$/

    #
    # Normalize lang
    #  (and raise exception is the parameter is suspicious)
    #  The settings are based on: LanguageCode_CountryCode.Encoding
    #
    def self.normlang(lng)
	unless md = LANGRegex.match(lng)
	    raise ArgumentError, "Suspicious language selection: #{lng}"
	end
	lang  =       md[1].downcase
        lang += '_' + md[2].upcase   if md[2]
        lang += '.' + md[3].downcase if md[3]
        lang.untaint
    end

    #
    # Split lang between Language, Country, Encoding
    #
    def self.splitlang(lng)
	unless md = LANGRegex.match(lng)
	    raise ArgumentError, "Suspicious language selection: #{lng}"
	end
        [ md[1], md[2], md[3] ]
    end


    #
    # Initializer
    #
    def initialize
	@actions	= {}

	@lang		= nil
        @language	= nil
        @country	= nil
        @encoding	= nil

      if ENV['LANG']
        lng = ENV['LANG'] 
        ln, ct, en = ZoneCheck::Locale::splitlang(ZoneCheck::Locale::normlang(lng))
        evlist = []
        evlist << 'lang'  if (@language != ln) || (@country != ct)
        evlist << 'encoding'  if (@encoding != en)
        @lang, @language, @country, @encoding = lng, ln, ct, en
        $dbg.msg(DBG::LOCALE) { "locale set to #{lng}" }
        notify(*evlist)
      end
    end

    attr_reader :lang, :language, :country, :encoding

    def lang=(lng)
      ln, ct, en = ZoneCheck::Locale::splitlang(ZoneCheck::Locale::normlang(lng))
      if($supported_languages.include?(ln.downcase))
      	evlist = []
      	evlist << 'lang'	if (@language != ln) || (@country != ct)
      	evlist << 'encoding'	if (@encoding != en)
      	@lang, @language, @country, @encoding = lng, ln, ct, en
      	$dbg.msg(DBG::LOCALE) { "locale set to #{lng}" }
      	notify(*evlist)
      else
        $dbg.msg(DBG::LOCALE) { "The given language (#{lng}) is not supported by ZoneCheck. " +
        "Here is a list of supported languages: " +
        $supported_languages.join(", ")   }
      end
    end

    def watch(event, action)
	(@actions[event] ||= []) << action
    end

    def notify(*event)
	event.each { |ev|
	    @actions[ev].each { |a| a.call } if @actions.has_key?(ev) }
    end
end
end