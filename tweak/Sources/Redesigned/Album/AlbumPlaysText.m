// Presentation shared by the two count sources; unknown remote counts never become zeroes.
#import "Core/SGCore.h"
#import "Album.h"

static NSString *numberText(NSNumber *plays) {
    static NSNumberFormatter *formatter;
    if (!formatter) {
        formatter = [NSNumberFormatter new];
        formatter.numberStyle = NSNumberFormatterDecimalStyle;
    }
    return [formatter stringFromNumber:plays];
}

NSString *SGRAlbumPlaysText(NSUInteger plays) {
    return plays ? [NSString stringWithFormat:SGL(@"settings.album.play_counts.your_count", @"Your plays: %@"), numberText(@(plays))] : nil;
}

NSString *SGRAlbumSpotifyPlaysText(NSNumber *plays) {
    return plays ? [NSString stringWithFormat:SGL(@"settings.album.play_counts.spotify_count", @"Spotify plays: %@"), numberText(plays)] : nil;
}
