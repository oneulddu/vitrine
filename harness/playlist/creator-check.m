// The creator line of the playlist header (creatorIn in Redesigned/Playlist/PlaylistHeader.x): the name beside
// the facepile, whose own initial is a label of its own. This file includes the generated header source to reach
// the static function. Exits nonzero on the first failed check.
#import <UIKit/UIKit.h>
#import "../harness-fail.h"
#include "gen/PlaylistHeader.m"

@interface SGRCreatorFacepileView : UIView @end
@implementation SGRCreatorFacepileView @end

static UILabel *label(NSString *text, UIView *parent) {
    UILabel *l = [UILabel new];
    l.text = text;
    [parent addSubview:l];
    return l;
}

// block > row > [facepile > initial, name]; the title label sits above the row, outside it.
static NSString *creatorWith(NSString *initial, NSString *name) {
    UIView *block = [UIView new], *row = [UIView new], *face = [SGRCreatorFacepileView new];
    [block addSubview:row];
    label(@"Title of the playlist", block);
    [row addSubview:face];
    if (initial) label(initial, face);
    if (name) label(name, row);
    return creatorIn(block);
}

static void expect(NSString *what, NSString *got, NSString *want) {
    if (got != want && ![got isEqualToString:want]) HARNESS_FAIL(@"%@: the creator reads %@, expected %@", what, got ?: @"nil", want ?: @"nil");
    NSLog(@"[harness] %@: creator %@", what, got ?: @"nil");
}

__attribute__((constructor(101))) static void sgr_creatorDefaults(void) {
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"spotifyglass.redesign"];
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        expect(@"name with facepile initial", creatorWith(@"D", @"Darkk"), @"Darkk");
        expect(@"one letter name", creatorWith(@"X", @"X"), @"X");
        expect(@"one character name", creatorWith(@"林", @"林"), @"林");
        expect(@"facepile initial alone", creatorWith(@"D", nil), nil);
        expect(@"blank name", creatorWith(@"D", @"  "), nil);
        NSLog(@"[harness] PASS creator");
        fprintf(stderr, "[harness] PASS creator\n");
    }
    return 0;
}
