# $Id: Makefile,v 1.40 2010/06/01 15:36:06 chabannf Exp $

#  
# CONTACT     : zonecheck@nic.fr 
# AUTHOR      : Stephane D'Alu <sdalu@nic.fr> 
# 
# CREATED     : 2003/10/23 21:04:09 
# REVISION    : $Revision: 1.40 $  
# DATE        : $Date: 2010/06/01 15:36:06 $ 
# 

RUBY ?=ruby
ZC_INSTALLER=$(RUBY) ./installer.rb


all: configinfo

configinfo: 
	@echo "Nothing to make, you can install it right now!"
	@echo " => but ensure that you have the full path for the ruby interpreter!"
	@echo ""
	@$(ZC_INSTALLER) configinfo
	@echo ""
	@echo "You can change them by using the syntax:"
	@echo "  $(MAKE) key=value"

install:
	@$(ZC_INSTALLER) all

default:
	$(MAKE) RUBY=`which ruby` install