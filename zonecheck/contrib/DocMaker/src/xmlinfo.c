/******************************************************************************
 * $Id: xmlinfo.c,v 1.1 2010/10/05 09:00:55 bortzmeyer Exp $
 * 
 * AUTHOR : Stephane D'Alu <sdalu@sdalu.com>
 * CREATED: 2003/01/12 18:02:35
 *
 * WWW    : http://www.sdalu.com/software/
 * LICENSE: GPL v2 (see http://www.gnu.org/licenses/gpl.txt)
 *
 *
 * $Revision: 1.1 $ 
 * $Date: 2010/10/05 09:00:55 $
 *
 *
 * REQUIRES:
 *  libxml2: http://xmlsoft.org/downloads.html
 *
 * COMPILING:
 *  gcc -o xmlinfo xmlinfo.c `xml2-config --cflags` `xml2-config --libs`
 *
 */


#include <string.h>
#include <stdarg.h>
#include <unistd.h>
#include <fcntl.h>

#include <libxml/xmlmemory.h>
#include <libxml/parser.h>
#include <libxml/tree.h>
#include <libxml/xmlerror.h>
#include <libxml/globals.h>


#define EXIT_OK       0
#define EXIT_BADXML   1
#define EXIT_NOFILE   2
#define EXIT_USAGE    3
#define EXIT_INTERNAL 4

static char *progname;

void usage(int exitcode) {
    printf("usage: %s [-h] [-q] [-e encoding] filename\n", progname);
    printf("    -q     quiet\n");
    printf("    -e     output encoding (<utf8>|utf16|iso-8859-1|...)\n");
    printf("    -h     this help\n");
    exit(exitcode);
}

void noerror_handler(void *ctx, const char *msg, ...) {
}


int
main(int argc, char **argv) {
    int   ch;
    char *encoding	= "utf8";
    char *filename;
    int   quiet		= 0;
    int   exitcode	= EXIT_OK;

    xmlDocPtr                 doc = NULL;
    xmlDtdPtr                 dtd = NULL;
    xmlCharEncoding           enc;
    xmlCharEncodingHandlerPtr enchandler;
    xmlOutputBufferPtr        out;

    /* LibXML version checking */
    LIBXML_TEST_VERSION;

    /* Who am I? */
    if ((progname = rindex(argv[0], '/')))
        progname++;
    else
        progname = argv[0];

    /* Parsing CLI */
    while ((ch = getopt(argc, argv, "hqe:")) != -1)
	switch (ch) {
	case 'q': quiet    = 1;      break;
	case 'e': encoding = optarg; break;
	case 'h': /* FALL THROUGH */
	case '?': usage(EXIT_OK);    break;
	default:  usage(EXIT_USAGE); break;
	}
    argc -= optind;
    argv += optind;

    switch (argc) {
    case 1:  filename = argv[0]; break;
    case 0:  filename = "-";     break;
    default: usage(EXIT_USAGE);
    }


    /* Get user encoding */
    if ((enc = xmlParseCharEncoding(encoding)) == XML_CHAR_ENCODING_ERROR) {
	fprintf(stderr, "Unknown encoding: %s\n", encoding);
	usage(EXIT_USAGE);
    }
    enchandler = xmlGetCharEncodingHandler(enc);

    /* Shut up */
    xmlSetGenericErrorFunc(NULL, &noerror_handler);
    xmlGetWarningsDefaultValue = 0;
    xmlPedanticParserDefault(0);

    /* File exists? (race condition below) */
    if (strcmp(filename, "-") && (open(filename, O_RDONLY) < 0)) {
	if (!quiet)
	    fprintf(stderr, "ERROR: unable to open %s\n", filename);
	exitcode = EXIT_NOFILE;
	goto exit;
    }

    /* Parse document */
    if ((doc = xmlParseFile(filename)) == NULL) {
	if (!quiet)
	    fprintf(stderr, "ERROR: badly formed document\n");
	exitcode = EXIT_BADXML;
	goto exit;
    }
    
    /* Extract DTD (if any) */
    dtd = xmlGetIntSubset(doc);

    /* Create output buffer */
    if ((out = xmlOutputBufferCreateFd(1, enchandler)) == NULL) {
	if (!quiet)
	    fprintf(stderr, "ERROR: unable to open output channel\n");
	exitcode = EXIT_INTERNAL;
	goto exit;
    }
    
    /* Dump information */
    if (doc->version) {
	xmlOutputBufferWriteString(out, "Version   : ");
	xmlOutputBufferWriteString(out, doc->version);
	xmlOutputBufferWriteString(out, "\n");
    }

    if (doc->encoding) {
	xmlOutputBufferWriteString(out, "Encoding  : ");
	xmlOutputBufferWriteString(out, doc->encoding);
	xmlOutputBufferWriteString(out, "\n");
    }

    if (dtd && dtd->name) {
	xmlOutputBufferWriteString(out, "Name      : ");
	xmlOutputBufferWriteString(out, dtd->name);
	xmlOutputBufferWriteString(out, "\n");
    }

    if (dtd && dtd->ExternalID) {
	xmlOutputBufferWriteString(out, "Identifier: ");
	xmlOutputBufferWriteString(out, dtd->ExternalID);
	xmlOutputBufferWriteString(out, "\n");
    }

    if (dtd && dtd->SystemID) {
	xmlOutputBufferWriteString(out, "URI       : ");
	xmlOutputBufferWriteString(out, dtd->SystemID);
	xmlOutputBufferWriteString(out, "\n");
	xmlOutputBufferFlush(out);
    }

    /* Free resources */
    if (doc)
	xmlFreeDoc(doc);
    xmlCleanupParser();

    /* OK */
 exit:
    exit(exitcode);
}
