// Labs: Spotify's flags for features it built and did not ship; every row forces one flag.
#import "Core/SGLocalize.h"
#import "Settings/SGModPage.h"
#import "Flags.h"

static UIViewController *martiniPage(void) {
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.labs.martini.title", @"AI Chat (Martini)") intro:SGRestartNote sections:@[
        SGSection(SGL(@"settings.labs.martini.on_home.header", @"On Home"), @[
            SGFlagRow(SGL(@"settings.labs.martini.entry_point.title", @"Chat entry point"), @"ios-home-evopage-impl.interactive_entrypoint_enabled"),
            SGFlagRow(SGL(@"settings.labs.martini.backend.title", @"Martini behind it"), @"ios-home-evopage-impl.interactive_entrypoint_martini_enabled"),
            SGFlagRow(SGL(@"settings.labs.martini.floating.title", @"Floating chat"), @"ios-home-evopage-impl.interactive_entrypoint_floating_chat_enabled"),
            SGFlagRow(SGL(@"settings.labs.martini.mic.title", @"Microphone"), @"ios-home-evopage-impl.interactive_entrypoint_mic_enabled"),
            SGFlagRow(SGL(@"settings.labs.martini.glowing_pill.title", @"Glowing pill"), @"ios-home-evopage-impl.interactive_entrypoint_pill_glow_enabled"),
        ]),
        SGSection(SGL(@"settings.labs.martini.chat_section.header", @"The chat"), @[
            SGFlagRow(SGL(@"settings.labs.martini.intent_pills.title", @"Intent pills"), @"ios-martini-floatingchat-impl.intent_pills_enabled"),
            SGFlagRow(SGL(@"settings.labs.martini.thinking_states.title", @"Thinking states"), @"ios-martini-floatingchat-impl.thinking_states_enabled"),
            SGFlagRow(SGL(@"settings.labs.martini.voice_recording.title", @"Voice recording"), @"ios-martini-floatingchat-impl.voice_recording_enabled"),
        ]),
        SGSection(SGL(@"settings.labs.martini.in_player.header", @"In the player"), @[
            SGFlagRow(SGL(@"settings.labs.martini.entry_point.title", @"Chat entry point"), @"ios-martini-npvcardprovider-impl.floating_chat_entry_point_enabled"),
        ]),
    ] footer:nil];
}

UIViewController *SGLabsPage(void) {
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.labs.title", @"Labs") intro:SGL(@"settings.labs.intro", @"Unreleased features; some do nothing on your version. A switch that is on forces the feature on; off leaves it to Spotify, which may still turn it on. Changes apply after you restart Spotify.") sections:@[
        SGSection(nil, @[
            SGWithSymbol(SGPageRow(SGL(@"settings.labs.martini.row.title", @"AI Chat (Martini)"), ^UIViewController *{ return martiniPage(); }), @"bubble.left.and.bubble.right"),
        ]),
        SGSection(SGL(@"settings.labs.library.header", @"Library"), @[
            SGFlagRow(SGL(@"settings.labs.local_files.title", @"Local files from the Files app"), @"ios-feature-localfiles.documents_enabled"),
        ]),
        SGSection(SGL(@"settings.labs.widget.header", @"Home screen widget"), @[
            SGFlagRow(SGL(@"settings.labs.progress_bar.title", @"Progress bar"), @"ios-widgets-widgetremoteconfig-impl.progress_bar_enabled"),
        ]),
        SGNotedSection(SGL(@"settings.labs.sleep_timer.header", @"Sleep timer"), @[
            SGFlagRow(SGL(@"settings.labs.sleep_fade_out.title", @"Fade out"), @"ios-feature-sleeptimer.enable_fade_out"),
            SGFlagRow(SGL(@"settings.labs.sleep_one_minute.title", @"One minute option"), @"ios-feature-sleeptimer.enable_one_minute_option"),
            SGFlagRow(SGL(@"settings.labs.sleep_options_sheet.title", @"Options sheet"), @"ios-feature-sleeptimer.use_options_sheet"),
        ], SGL(@"settings.labs.sleep_options_sheet.footer", @"Options sheet is always on in Redesigned UI.")),
        SGSection(SGL(@"settings.labs.player.header", @"Player"), @[
            SGFlagRow(SGL(@"settings.labs.snake_cover.title", @"Snake on the cover art"), @"ios-feature-cover-art-snake.enabled"),
        ]),
        SGSection(SGL(@"settings.labs.podcast_comments.header", @"Podcast comments"), @[
            SGFlagRow(SGL(@"settings.labs.comments_card.title", @"Comments card"), @"ios-feature-comments.enable_comments_card"),
            SGFlagRow(SGL(@"settings.labs.pinned_comments.title", @"Pinned comments"), @"ios-feature-comments.enable_pinned_comments"),
            SGFlagRow(SGL(@"settings.labs.multi_reactions.title", @"Several reactions"), @"ios-feature-comments.enable_multi_reactions"),
        ]),
    ] footer:nil];
}
