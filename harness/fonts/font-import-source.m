// FontImport.m as the tweak compiles it, with Core Text's registration replaced by check.m's double (the same one
// FontLibrary.m uses there), so the imported family's registration can be held and counted like the library's.
#import <CoreText/CoreText.h>
bool harnessRegister(CFURLRef url, CTFontManagerScope scope, CFErrorRef *error);
#define CTFontManagerRegisterFontsForURL harnessRegister
#import "Shared/Fonts/FontImport.m"
