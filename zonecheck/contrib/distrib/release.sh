#!/bin/sh

export SGML_CATALOG_FILES=/nicdoc/DocMaker/catalog.sgml
export XML_CATALOG_FILES=/nicdoc/DocMaker/catalog.xml
PATH=$PATH:/nicdoc/DocMaker/bin:/nicdoc/DocMaker/sysdeps/i386-FreeBSD/bin

warn() { echo "WARN: $1"  ; return 1; }
die()  { echo "ERROR: $1" ; exit   1; }
info() { echo "$1"        ; return 1; }

# Arguments
[ -z "$1" ] && die "version required (ex: 3.0.4)"

dest=${2:-/dev/null}
[ "${dest#/}" != ${dest} ] || dest=`pwd`/$dest


release=$1
tmp=/tmp/zcrelease.$$

cvstag=ZC-`echo $release | sed 's/\./_/g'`
module=zonecheck
tarname=$module-$release.tgz
tarlatest=$module-latest.tgz


info "Making ZoneCheck release $release"

info "Did you update the ChangeLog (and commit!) to document the changes?"
info "Type <Return> to confirm or Control-C to cancel: "
read confirmation

info "- setting CVSROOT"
if [ -z "$CVSROOT" ]; then
    if [ -f CVS/Root ]; then
	export CVSROOT=`cat CVS/Root`
    else
	die "unable to guess CVSROOT, you need to set it"
    fi
fi

info "- creating temporary directory $tmp"
mkdir -p $tmp
cd $tmp || die "unable to change directory to $tmp"

info "- exporting from CVS with tag $cvstag"
cvs -q export -r $cvstag $module ||
    die "unable to export release tagged $cvstag (may be your forgot to tag *before*?)"

info "- generating documentation"
(   mkdir -p $module/doc/html
    cd $module/doc/html || die "unable to change directory to zc/doc/html"
    xml2doc -q ../xml/FAQ.xml --output=html
    xml2doc -q ../xml/zc.xml  --output=htmlchunk
)
(   cd $module
    elinks -dump doc/html/FAQ.html > FAQ
)

info "- creating RPM spec"
sed s/@VERSION@/$release/ < $module/contrib/distrib/rpm/zonecheck.spec.in > $module/contrib/distrib/rpm/zonecheck.spec



info "- creating tarball: $tarname"
tar cfz $tarname $module

info "- copy on ${dest}"
cp $tarname ${dest}

info "- copy on savannah"
ln -s $tarname $tarlatest
rsync -av $tarname   dl.sv.nongnu.org:/releases/zonecheck/

info "- copy on www.zonecheck.fr"
rsync -av $tarname -e "ssh -p 2222" www.zonecheck.fr:/var/www/www.zonecheck.fr/htdocs/download

info "- cleaning"
rm -Rf $tmp

info "Do not forget to update www.zonecheck.fr:/var/www/www.zonecheck.fr/htdocs/lastnews.ihtml and download.shtml"

exit 0
