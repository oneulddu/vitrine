// Workshop's comparison shelf. Each visible card plays its own fixed style without changing the
// player's choice; selecting it updates every ordinary lyrics view and preview through the notification.
#import "Core/SGLocalize.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "LyricsLook.h"
#import "SGRKaraokeView.h"

@interface SGRLyricsStyleCell : UITableViewCell
@property (nonatomic, strong) SGRKaraokeView *preview;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UIImageView *check;
@end

@implementation SGRLyricsStyleCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if (!(self = [super initWithStyle:style reuseIdentifier:identifier])) return nil;
    self.backgroundColor = SGCardBackground();
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.isAccessibilityElement = YES;
    _nameLabel = [UILabel new];
    _nameLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    _nameLabel.adjustsFontForContentSizeCategory = YES;
    _nameLabel.numberOfLines = 0;
    _nameLabel.textColor = UIColor.whiteColor;
    _check = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle.fill"]];
    [self.contentView addSubview:_nameLabel];
    [self.contentView addSubview:_check];
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    CGFloat titleHeight = ceil([_nameLabel sizeThatFits:CGSizeMake(MAX(1, width - 80), CGFLOAT_MAX)].height);
    _nameLabel.frame = CGRectMake(16, 12, MAX(1, width - 80), titleHeight);
    _check.frame = CGRectMake(width - 44, 12, 24, 24);
    CGFloat top = CGRectGetMaxY(_nameLabel.frame) + 8;
    _preview.frame = CGRectMake(0, top, width, MAX(0, self.contentView.bounds.size.height - top));
}
- (void)prepareForReuse {
    [super prepareForReuse];
    [self.preview removeFromSuperview];
    self.preview = nil;
}
@end

@interface SGRLyricsStylesPage : SGPage
@end

@implementation SGRLyricsStylesPage
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = SGL(@"settings.lyricsstyle.title", @"Lyrics styles");
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.tableView.backgroundColor = UIColor.blackColor;
    [self.tableView registerClass:SGRLyricsStyleCell.class forCellReuseIdentifier:@"style"];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(selectionChanged)
        name:SGRLyricsStyleDidChangeNotification object:nil];
}
- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)SGRLyricsStyleIDs().count;
}
- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path {
    return 244 + ceil([UIFont preferredFontForTextStyle:UIFontTextStyleHeadline].lineHeight * 2);
}
- (void)markCell:(SGRLyricsStyleCell *)cell identifier:(NSString *)identifier {
    BOOL selected = [identifier isEqualToString:SGRLyricsStyleNow()];
    cell.check.hidden = !selected;
    cell.accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    SGRLyricsStyleCell *cell = [table dequeueReusableCellWithIdentifier:@"style" forIndexPath:path];
    NSString *identifier = SGRLyricsStyleIDs()[(NSUInteger)path.row];
    cell.nameLabel.text = SGRLyricsStyleName(identifier);
    cell.accessibilityLabel = cell.nameLabel.text;
    cell.preview = [[SGRKaraokeView alloc] initWithSampleLines:SGRLyricsSampleLines() length:SGRLyricsSampleLength()];
    cell.preview.sampleStyleIdentifier = identifier;
    [cell.contentView addSubview:cell.preview];
    [self markCell:cell identifier:identifier];
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    SGRSetLyricsStyle(SGRLyricsStyleIDs()[(NSUInteger)path.row]);
    [table deselectRowAtIndexPath:path animated:YES];
}
- (void)selectionChanged {
    // Keep the sample clocks running instead of reloading cells on every selection.
    for (NSIndexPath *path in self.tableView.indexPathsForVisibleRows)
        [self markCell:(SGRLyricsStyleCell *)[self.tableView cellForRowAtIndexPath:path]
            identifier:SGRLyricsStyleIDs()[(NSUInteger)path.row]];
}
@end

UIViewController *SGRLyricsStylesSettingsPage(void) {
    return [[SGRLyricsStylesPage alloc] initWithStyle:UITableViewStyleInsetGrouped];
}
