// SGModPage's -viewDidLoad attaches the search field (SGSettingsSearch.m), which is not part of this check; the
// index it feeds is, and the pages built here are never shown.
#import <UIKit/UIKit.h>
#import "Settings/SGModPage.h"

void SGSettingsSearchAttach(SGModPage *page) {
}
