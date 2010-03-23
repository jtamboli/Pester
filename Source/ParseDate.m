//
//  ParseDate.m
//  Pester
//
//  Created by Nicholas Riley on 11/28/07.
//  Copyright 2007 Nicholas Riley. All rights reserved.
//

#import <Foundation/Foundation.h>

// generated by perl -MExtUtils::Embed -e xsinit -- -o perlxsi.c
#include <EXTERN.h>
#include <perl.h>

EXTERN_C void xs_init (pTHX);

EXTERN_C void boot_DynaLoader (pTHX_ CV* cv);

EXTERN_C void
xs_init(pTHX)
{
    char *file = __FILE__;
    dXSUB_SYS;
    
    /* DynaLoader is a special case */
    newXS("DynaLoader::boot_DynaLoader", boot_DynaLoader, file);
}
// end generated code

static PerlInterpreter *my_perl;
static NSDateFormatter *dateManipFormatter;
static BOOL parser_OK = NO;

NSDate *parse_natural_language_date(NSString *input) {
    if (my_perl == NULL || !parser_OK)
	return [NSDate distantPast];

    if (input == nil)
	return nil;

    if ([input rangeOfString: @"|"].length > 0) {
	NSMutableString *sanitized = [[input mutableCopy] autorelease];
	[sanitized replaceOccurrencesOfString: @"|" withString: @""
				      options: NSLiteralSearch
					range: NSMakeRange(0, [sanitized length])];
	input = sanitized;
    }
    
    NSString *temp = [[NSString alloc] initWithFormat: @"my $s = eval {UnixDate(q|%@|, '%%q')}; warn $@ if $@; $s", input];
    // XXX Date::Manip doesn't support Unicode, apparently
    SV *d = eval_pv([temp cStringUsingEncoding: NSISOLatin1StringEncoding], FALSE);
    [temp release];
    if (d == NULL) return nil;
    
    STRLEN s_len;
    char *s = SvPV(d, s_len);
    if (s == NULL || s_len == 0) return nil;
    
    NSDate *date = [dateManipFormatter dateFromString: [NSString stringWithUTF8String: s]];
    // NSLog(@"%@", date);
    
    return date;
}

void init_date_parser(void) {
    if (my_perl == NULL) return;

    parser_OK = NO;

    NSString *localeLanguageCode = [[NSLocale currentLocale] objectForKey: NSLocaleLanguageCode];
    char *language = NULL;
    if ([localeLanguageCode isEqualToString: @"en"])
	language = "English";
    else if ([localeLanguageCode isEqualToString: @"fr"])
	language = "French";
    else if ([localeLanguageCode isEqualToString: @"sv"])
	language = "Swedish";
    else if ([localeLanguageCode isEqualToString: @"de"])
	language = "German";
    else if ([localeLanguageCode isEqualToString: @"pl"])
	language = "Polish";
    else if ([localeLanguageCode isEqualToString: @"nl"])
	language = "Dutch";
    else if ([localeLanguageCode isEqualToString: @"es"])
	language = "Spanish";
    else if ([localeLanguageCode isEqualToString: @"pt"])
	language = "Portuguese";
    else if ([localeLanguageCode isEqualToString: @"ro"])
	language = "Romanian";
    else if ([localeLanguageCode isEqualToString: @"it"])
	language = "Italian";
    else if ([localeLanguageCode isEqualToString: @"ru"])
	language = "Russian";
    else if ([localeLanguageCode isEqualToString: @"tr"])
	language = "Turkish";
    else if ([localeLanguageCode isEqualToString: @"da"])
	language = "Danish";
    else if ([localeLanguageCode isEqualToString: @"ca"])
	language = "Catalan";
    else
	return;

    // Date::Manip uses "US" to mean month/day and "non-US" to mean day/month.
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateStyle: NSDateFormatterShortStyle];
    BOOL isUS = [[dateFormatter dateFormat] characterAtIndex: 0] == 'M';
    [dateFormatter release];

    int gmtOffsetMinutes = ([[NSTimeZone defaultTimeZone] secondsFromGMT]) / 60;
    NSString *temp = [[NSString alloc] initWithFormat:
	  @"Date_Init(\"Language=%s\", \"DateFormat=%s\", \"Internal=1\", \"TZ=%c%02d:%02d\")",
	  language, isUS ? "US" : "non-US",
	  gmtOffsetMinutes < 0 ? '-' : '+', abs(gmtOffsetMinutes) / 60, abs(gmtOffsetMinutes) % 60];
    SV *d = eval_pv([temp UTF8String], FALSE);
    [temp release];
    if (d == NULL) return;

    // XXX test date needs to be format-independent (try ISO 8601)
    if (parse_natural_language_date(@"20100322t134821") == nil) return;

    parser_OK = YES;
}

// Perl breaks backwards compatibility between 5.8.8 and 5.8.9.
// (libperl.dylib does not contain Perl_sys_init or Perl_sys_term.)
// Use the 5.8.8 definitions, which still seems to work fine with 5.8.9.
// This allows ParseDate to be compiled on 10.6 for 10.5.
#undef PERL_SYS_INIT
#define PERL_SYS_INIT(c,v) MALLOC_CHECK_TAINT2(*c,*v) PERL_FPU_INIT MALLOC_INIT
#undef PERL_SYS_TERM
#define PERL_SYS_TERM() OP_REFCNT_TERM; MALLOC_TERM

static void init_perl(void) {
    const char *argv[] = {"", "-CSD", "-I", "", "-MDate::Manip", "-e", "0"};
    argv[3] = [[[NSBundle mainBundle] resourcePath] fileSystemRepresentation];
    PERL_SYS_INIT(0, NULL);
    my_perl = perl_alloc();
    if (my_perl == NULL) return;

    perl_construct(my_perl);
    if (perl_parse(my_perl, xs_init, 7, (char **)argv, NULL) != 0) goto fail;

    PL_exit_flags |= PERL_EXIT_DESTRUCT_END;
    if (perl_run(my_perl) != 0) goto fail;

    init_date_parser(); // even if it fails, may try again later
    return;

fail:
    perl_destruct(my_perl);
    perl_free(my_perl);
    PERL_SYS_TERM();
    my_perl = NULL;
}


// note: the documentation is misleading here, and this works.
// <http://gcc.gnu.org/ml/gcc-patches/2004-06/msg00385.html>
void initialize(void) __attribute__((constructor));

void initialize(void) {
    dateManipFormatter = [[NSDateFormatter alloc] init];
    [dateManipFormatter setDateFormat: @"yyyyMMddHHmmss"]; // Date::Manip's "%q"
    init_perl();
}