// What a picture is, read once off the main thread: the colour a page around it should take, picked from what the
// picture actually is (a flat border, a portrait, a dark cover with an accent, colourful art) rather than from its
// dominant colour, and how far down its content and its subjects reach, for the picture to stay sharp to there. The
// album's picture-aware full screen cover reads its cover and its animated cover's first frame with it
// (Album/AlbumHeader.x); the artist page's picture-aware photo reads its photo with the artist variant (SGRPhotoRead,
// below).
//
// The image is aspect-filled into a 256x256 bitmap and averaged in 4x4 blocks to a 64x64 sample, read in OKLab;
// pixels under half opaque are left out of every measure. Measured: the border (the outer 3 rows and columns, the
// corners in both) and its per-component median, the foot (the bottom 9 rows), the mean lightness and chroma, the
// share of pixels with L under 0.25, and six k-means clusters (12 iterations) with their coverage, lightness and
// chroma. Then the picture is the first of these that holds:
//
//     solid        85% of the border within 0.05 of its median and 55% of all pixels within 0.06 of it: dark
//                  under L 0.35, light over L 0.85 with chroma under 0.04, else coloured; the border's colour
//     dark accent  mean L under 0.33 or 60% of pixels under L 0.25, and a cluster of chroma 0.08 or more covering
//                  15% or more with L between 0.15 and 0.9: the widest such cluster, then the most chromatic
//     portrait     faces covering 5% or more, the lowest face edge at or below half the height: the foot's colour
//                  outside the faces, while any of the foot is outside them
//     colourful    mean chroma 0.06 or more: the cluster with the most coverage times chroma
//     foot         the foot's colour
//
// A picture that is not solid is also given to Vision on the 256x256 bitmap: faces, and salient objects above 0.5
// confidence. Its pixel-only reading is delivered first and the final one replaces it; a Vision error makes the pixel
// reading final, so a cover is never held up by it.
//
// Readings are kept by the sample's content (NSCache, 64 of them) and, weakly, by the UIImage, so the same image is
// not sampled again; none is written to disk.
// Threading: SGRCoverRead, SGRPhotoRead and -pageColor are main thread only; the work runs on one serial utility queue
// they share.
#import <UIKit/UIKit.h>

typedef struct {
    CGFloat L, a, b;
} SGRLab;

typedef NS_ENUM(NSInteger, SGRCoverKind) {
    SGRCoverKindFoot,
    SGRCoverKindSolidDark,
    SGRCoverKindSolidLight,
    SGRCoverKindSolidColour,
    SGRCoverKindDarkAccent,
    SGRCoverKindPortrait,
    SGRCoverKindColourful,
};

BOOL SGRCoverKindIsSolid(SGRCoverKind kind);

@interface SGRCoverReading : NSObject
@property (nonatomic, readonly) SGRCoverKind kind;
// The colour picked, in OKLab, as read off the picture.
@property (nonatomic, readonly) SGRLab colour;
// NO for the pixel-only reading delivered while Vision still runs.
@property (nonatomic, readonly) BOOL final;
// Fractions of the sample's height from its top: the bottom of a solid picture's lowest row of content (rows with
// two or more pixels farther than 0.06 from the border's colour; 0 with none, and 1 when the picture is not solid),
// and the lowest edge of a face or salient object (0 with none).
@property (nonatomic, readonly) CGFloat contentBottom, subjectBottom;
// The sample's content: equal for two images that read the same.
@property (nonatomic, readonly) uint64_t identity;
// The colour for a page: chroma lifted 1.15 times (unless under 0.03), lightness held to 0.44 (0.40 with Increase
// Contrast), then brought into sRGB by reducing its chroma alone.
- (UIColor *)pageColor;
@end

// The page colour of an OKLab colour, as -pageColor makes it, in OKLab; `contrast` for Increase Contrast.
SGRLab SGRCoverPageLab(SGRLab colour, BOOL contrast);
CGFloat SGRLabDistance(SGRLab one, SGRLab other);
// The colour at lightness `L`, `chroma` and `hue` (radians), brought into sRGB by its chroma alone: as it is when sRGB
// holds it, else the most chroma at that lightness and hue that it holds. Any thread.
SGRLab SGRLabInSRGB(CGFloat L, CGFloat chroma, CGFloat hue);
// An sRGB colour in OKLab and back (sRGB components 0-1; the way back clamps). The RGB8 pair is the same through
// tables, for a bitmap's pixels: any thread.
SGRLab SGRLabFromRGB(CGFloat red, CGFloat green, CGFloat blue);
void SGRLabToRGB(SGRLab lab, CGFloat *red, CGFloat *green, CGFloat *blue);
SGRLab SGRLabFromRGB8(const uint8_t rgb[3]);
void SGRLabToRGB8(SGRLab lab, uint8_t rgb[3]);

// Where a picture under a page's title stops being sharp, and how it goes into the page's colour below that.
typedef struct {
    CGFloat sharpEnd;     // a fraction of the picture's height from its top
    CGFloat blurRadius;   // points, the most the blur below sharpEnd reaches
    CGFloat mixLength;    // points the mix into the page's colour takes at most; 0 for no limit
} SGRCoverSharpness;
// A solid picture is sharp to its content's bottom and 5 points of the height more, at most 86%, and blurs to 24 pt
// below it; a solid dark one whose page colour is its own border's is not blurred at all and mixes into it over 120
// pt. Any other is sharp to `fallback` (a fraction of its height) or its subjects' lowest edge, whichever is lower,
// held between 60% and 90%, and blurs to 64 pt. Main thread (reads Increase Contrast).
SGRCoverSharpness SGRCoverSharpnessFor(SGRCoverReading *reading, CGFloat fallback);

// Reads `image` and calls `done` on the main thread: with a pixel-only reading first for a picture that goes to
// Vision, then with the final one; with nil when the image has no bitmap or nothing opaque enough to read. Returns NO,
// and never calls `done`, for nil or an image narrower than 80 pt.
BOOL SGRCoverRead(UIImage *image, void (^done)(SGRCoverReading *reading));

// The artist variant: a photo read for its faces, for the artist page's picture-aware photo (Artist/ArtistHeader.x).
// The same 64x64 OKLab sample; Vision looks for faces alone (no saliency), once per picture, and the reading is kept
// in a cache of its own (NSCache, 64, by the sample's content, and weakly by the UIImage). A Vision error reads the
// photo as one with no faces. Measured: the largest face's area as a share of the picture, the number of faces, the
// mean lightness, and the foot's colour: the OKLab mean of the bottom 12 rows (52-63), the pixels inside a face left
// out while any of the foot is outside them, its chroma then lifted 1.15 times (unless under 0.03) and held to 0.15.
@interface SGRPhotoReading : NSObject
@property (nonatomic, readonly) CGFloat largestFace;
@property (nonatomic, readonly) NSUInteger faceCount;
@property (nonatomic, readonly) CGFloat meanL;
@property (nonatomic, readonly) SGRLab foot;
// The sample's content: equal for two images that read the same.
@property (nonatomic, readonly) uint64_t identity;
@end

// Reads `image` and calls `done` once on the main thread, with nil when the image has no bitmap or nothing opaque
// enough to read. Returns NO, and never calls `done`, for nil or an image narrower than 80 pt.
BOOL SGRPhotoRead(UIImage *image, void (^done)(SGRPhotoReading *reading));
// The page's colour for a read photo, given `current`, the colour the page would take without it (SGRPalette's): the
// foot's colour where its chroma is 0.06 or more, 0.04 or more over the current colour's, and its hue outside 70-115
// degrees (skin and yellow), else the current colour; on a very dark photo (mean L under 0.24) brought down to the
// foot's lightness when more than 0.02 over it, hue and chroma kept. Then held to the page colour's lightness and
// brought into sRGB by its chroma, as SGRCoverPageLab does, without lifting it again. `contrast` for Increase Contrast.
SGRLab SGRPhotoPageLab(SGRPhotoReading *reading, SGRLab current, BOOL contrast);
// The same for UIColors, with Increase Contrast as it is now. Main thread.
UIColor *SGRPhotoPageColor(SGRPhotoReading *reading, UIColor *current);

#ifdef SGR_COVER_READ_TEST
// The harness answers for Vision (harness/album/cover-read-check.m, harness/artist-artwork/photo-read-check.m): rects
// in fractions of the bitmap from its top left, faces and salient objects, or NO for an error. `vision` is the real
// detector, for the harness to hand over to: faces and salient objects for a cover, faces alone for a photo.
typedef BOOL (*SGRCoverVision)(CGImageRef bitmap, NSArray<NSValue *> **faces, NSArray<NSValue *> **objects);
BOOL SGRCoverReadTestSubjects(CGImageRef bitmap, SGRCoverVision vision, NSArray<NSValue *> **faces, NSArray<NSValue *> **objects);
#endif
