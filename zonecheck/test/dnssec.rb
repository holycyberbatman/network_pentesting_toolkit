# ZCTEST 1.0
# $Id: dnssec.rb,v 1.11 2011/03/11 16:09:18 kmkaplan Exp $

# 
# CONTACT     : zonecheck@nic.fr
# AUTHOR      : Stephane D'Alu <sdalu@nic.fr>
#
# CREATED     : 2002/08/02 13:58:17
# REVISION    : $Revision: 1.11 $ 
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

require 'framework'
require 'time'

module CheckDNSSEC
    ##
    ## Check domain NS records
    ##
    class DNSSEC < Test
      with_msgcat 'test/dnssec.%s'
    
      #-- Checks --------------------------------------------------
      
      def chk_edns(ns, ip)
#        begin
          msg   = Dnsruby::Message::new(@domain.name, "ANY")
          optrr = Dnsruby::RR::OPT.new(4096)
          optrr.dnssec_ok = true
          msg.add_additional(optrr)
          msg.do_caching = false
          
          resolver = Dnsruby::Resolver::new({:nameserver => ip.to_s})
          resolver.do_caching = false
          resolver.dnssec = false
           
          
          ret = resolver.send_message(msg)
          resolver = nil
          return false if ret.nil? || ret.additional.empty?
          ret.additional.each { |add|
            return true if add.type == "OPT" && add.payloadsize > 1024
          }
          return false
#        rescue Dnsruby::ResolvError, Dnsruby::ResolvTimeout
#          return false
#        end
      end
      
      def chk_has_soa_rrsig(ns, ip)
          ret = rrsig(ip,"SOA")
          is_not_empty = ! ret.empty?
          #return {"dig" => ret.to_s} unless is_not_empty
          return is_not_empty
      end
      
      def chk_one_dnskey(ns, ip)
          ! dnskey(ip).empty?
      end
      
      def chk_several_dnskey(ns, ip)
          dnskey(ip).size >= 2
      end
      
      def chk_zsk_and_ksk(ns, ip)
          zsk = false
          ksk = false
          dnskey(ip).each { |key|
            zsk = true if key.flags%2 == 1
            ksk = true if key.flags%2 == 0 
          }
          #return { "dig" => dnskey(ip) } unless zsk && ksk
          return zsk && ksk
      end
      
      def chk_algorithm(ns,ip)
        rrsig(ip,"SOA").each {|sig|
        if [Dnsruby::Algorithms.RSASHA1,
            Dnsruby::Algorithms.RSASHA256,
            Dnsruby::Algorithms.RSASHA512,
            Dnsruby::Algorithms.RSASHA1_NSEC3_SHA1,
            Dnsruby::Algorithms.DSA,
            Dnsruby::Algorithms.DSA_NSEC3_SHA1].include?(sig.algorithm)
          return true
        end
        }
        return {"error" => $mc.get('dnssec:algorithm:unknown')}
      end
      
      def chk_key_length(ns,ip)
        keys = dnskey(ip)
        keys.each {|key|
          pkey = key.public_key
          case key.algorithm
          when Dnsruby::Algorithms.RSASHA1
            if key.key_length < 1024 && !(key.sep_key?)
              return {"keylength" => key.key_length.to_s,
                "algo" => "RSA SHA 1"}
            elsif key.key_length < 2048 && key.sep_key?
              return {"keylength" => key.key_length.to_s,
                  "algo" =>  "RSA SHA 1"}
            end
          when Dnsruby::Algorithms.RSASHA256
            if key.key_length < 1024 && !(key.sep_key?)
              
              return {"keylength" => key.key_length.to_s,
                "algo" =>  "RSA SHA 256"}
            elsif key.key_length < 2048 && key.sep_key?
              return {"keylength" => key.key_length.to_s,
                "algo" =>  "RSA SHA 256"}
            end
          when Dnsruby::Algorithms.RSASHA512
            if key.key_length < 1024 && !(key.sep_key?)
              return {"keylength" => key.key_length.to_s,
                "algo" =>  "RSA SHA 512"}
            elsif key.key_length < 2048 && key.sep_key?
              return {"keylength" => key.key_length.to_s,
                "algo" =>  "RSA SHA 512"}
            end  
          when Dnsruby::Algorithms.RSASHA1_NSEC3_SHA1
            if key.key_length < 1024 && !(key.sep_key?)
              return {"keylength" => key.key_length.to_s,
                "algo" =>  "RSA SHA1 NSEC3 SHA1"}
            elsif key.key_length < 2048 && key.sep_key?
              return {"keylength" => key.key_length.to_s,
                "algo" =>  "RSA SHA1 NSEC3 SHA1"}
            end
          when Dnsruby::Algorithms.DSA
            if key.key_length < 1024 && !(key.sep_key?)
              return {"keylength" => key.key_length.to_s,
                "algo" =>  "DSA"}
            elsif key.key_length < 2048 && key.sep_key?
              return {"keylength" => key.key_length.to_s,
                "algo" =>  "DSA"}
            end
          when Dnsruby::Algorithms.DSA_NSEC3_SHA1
            if key.key_length < 1024 && !(key.sep_key?)
              return {"keylength" => key.key_length.to_s,
                "algo" =>  "DSA NSEC3 SHA1"}
            elsif key.key_length < 2048 && key.sep_key?
              return {"keylength" => key.key_length.to_s,
                "algo" =>  "DSA NSEC3 SHA1"}
            end
          end
        }
        true
      end
      
      def chk_soa_rrsig_expiration(ns,ip)
        sig = rrsig(ip,"SOA")[0]
        return true if Time::now.to_i < sig.expiration - 0.1 * (sig.expiration - sig.inception)
        { "date" =>  Time.at(sig.expiration) }
      end
      
      def chk_soa_rrsig_validity_period(ns,ip)
        sig = rrsig(ip,"SOA")[0]
        min = const('rrsig:validityperiod:min').to_i
        max = const('rrsig:validityperiod:max').to_i
        return true if  (sig.expiration - sig.inception) > min &&
                        (sig.expiration - sig.inception) > sig.ttl && 
                        (sig.expiration - sig.inception) < max
        { "period"  =>  (sig.expiration - sig.inception),
          "min"     =>  min,
          "max"     =>  max,
          "ttl"     =>  sig.ttl }
      end
      
      
      
      def chk_verify_soa_rrsig(ns,ip)
        begin
          sv = Dnsruby::SingleVerifier::new(Dnsruby::SingleVerifier::VerifierType::ANCHOR)
          soa = soa(ip).resource
          soa_rrsig = rrsig(ip,"SOA")[0].resource
          return false if soa_rrsig.nil?
          key = nil
          dnskey(ip).each { |keyTemp|
            key = keyTemp.resource if keyTemp.resource.key_tag == soa_rrsig.key_tag
          }
          soa_rrset = Dnsruby::RRSet::new(soa)
          soa_rrset.add(soa_rrsig)
          return false if key.nil? || soa_rrset.nil?
          return sv.verify_rrset(soa_rrset,key)
        rescue Dnsruby::VerifyError => e
          return false
        end
      end
      
      def chk_ds_and_dnskey_coherence(ns,ip)
        # Find all given DS otherwise return false
        if given_ds && !given_ds.all? {|ds|
            if ds.digest_type && ds.digestbin && ds.key_tag && ds.algorithm
              dnskey(ip).detect {|keytemp|
                ds.check_key(keytemp)
              }
            else
              dnskey(ip).detect {|keytemp|
                dstemp = Dnsruby::RR.create({ :name => @domain.name,
                                              :type => Dnsruby::Types.DS,
                                              :digest => ds.digest,
                                              :digest_type => ds.digest_type,
                                              :digestbin => ds.digestbin,
                                              :key_tag => keytemp.key_tag,
                                              :algorithm => keytemp.algorithm})
                dstemp.check_key(keytemp)
              }
            end
          }
          return false
        end
        # Find all given DNSKEY otherwise return false
        if given_dnskey && !given_dnskey.all? {|dnskey|
            dnskey(ip).detect {|keytemp|
              keytemp.key == dnskey.key && keytemp.sep_key?
            }
          }
          return false
        end
        return true
      end
      
      def tst_dnssec_policy(ns,ip)
        if is_dnssec_mandatory?
          if edns == "never"
            raise ArgumentError, 'Conflict between --edns never and --securedelegation, try with --edns always or auto'
          end
          return "full"
        else
          unless edns == "never"
            begin 
              ret = rrsig(ip,"SOA")
              is_not_empty = ! ret.empty?
              return "off" unless is_not_empty
              return "lax" if is_not_empty
            rescue Dnsruby::ResolvError => e
              return "off"
            rescue Dnsruby::ResolvTimeout => e
              return "off"
            end
          else
            return "off"  
          end
        end
      end
      
      def tst_a_ds_or_dnskey_is_given(ns,ip)
        if given_ds.nil? && given_dnskey.nil?
          return "false"
        else
          return "true"
        end
      end
      
    end
end
