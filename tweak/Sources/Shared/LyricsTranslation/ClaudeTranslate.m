#import <Security/Security.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Lyrics/Lyrics.h"
#import "AIServicesInternal.h"

static NSString *const kService = @"Vitrine.Claude", *const kAccount = @"api-key";
static NSString *const kModel = @"claude-sonnet-5";
static NSMutableDictionary *sg_done;

static NSDictionary *keyQuery(void) {
    return @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
             (__bridge id)kSecAttrService: kService, (__bridge id)kSecAttrAccount: kAccount};
}
static NSString *cleanKey(NSString *text) {
    NSMutableCharacterSet *around = [NSCharacterSet.whitespaceAndNewlineCharacterSet mutableCopy];
    [around addCharactersInString:@"\"'“”‘’"];
    NSString *key = [text stringByTrimmingCharactersInSet:around];
    return key.length <= 4096 && [key rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location == NSNotFound ? key : nil;
}
static NSString *storedKey(void) {
    NSMutableDictionary *query = [keyQuery() mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef data = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &data);
    id value = CFBridgingRelease(data);
    if (status != errSecSuccess || ![value isKindOfClass:NSData.class] || [value length] > 4096) return nil;
    NSString *key = cleanKey([[NSString alloc] initWithData:value encoding:NSUTF8StringEncoding]);
    return key.length ? key : nil;
}
static BOOL storeKey(NSString *key) {
    SecItemDelete((__bridge CFDictionaryRef)keyQuery());
    [sg_done removeAllObjects];
    if (!key.length) return YES;
    NSMutableDictionary *item = [keyQuery() mutableCopy];
    item[(__bridge id)kSecValueData] = [key dataUsingEncoding:NSUTF8StringEncoding];
    item[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
    if (status != errSecSuccess) SGLog(@"claude: the key could not be kept (%d)", (int)status);
    return status == errSecSuccess;
}
BOOL SGClaudeKeySet(void) { return storedKey() != nil; }
static NSString *setting(NSString *key, NSString *fallback) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:key];
    return [value isKindOfClass:NSString.class] ? value : fallback;
}
static NSString *cleanModel(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return nil;
    NSString *model = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return model.length && model.length <= 256 && [model rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location == NSNotFound ? model : nil;
}

static NSString *unreadable(void) {
    return SGL(@"settings.translation.claude.error.unreadable", @"Claude's answer could not be read. Try again.");
}

NSArray<NSString *> *SGClaudeTranslationsIn(id root, NSInteger status, NSError *error, NSUInteger count, NSString **problem) {
    if (problem) *problem = nil;
    NSString *failure = nil;
    NSDictionary *reply = [root isKindOfClass:NSDictionary.class] ? root : nil;
    id detail = [reply[@"error"] isKindOfClass:NSDictionary.class] ? reply[@"error"][@"message"] : nil;
    if (error) failure = SGL(@"settings.translation.claude.error.unreachable", @"Claude could not be reached.");
    else if (status == 401 || status == 403) failure = SGL(@"settings.translation.claude.error.keyinvalid", @"Claude turned the key down. Check it on the Lyrics page.");
    else if (status == 429 || (status >= 500 && status <= 599)) failure = SGL(@"settings.translation.claude.error.busy", @"Claude is busy right now. Try again in a minute.");
    else if (status == 400 && [detail isKindOfClass:NSString.class] && [detail length]) {
        NSString *message = [detail length] > 1024 ? [detail substringToIndex:1024] : detail;
        failure = [NSString stringWithFormat:SGL(@"settings.translation.claude.error.badrequest", @"Claude did not take the request: %@"), message];
    } else if (status != 200) failure = [NSString stringWithFormat:SGL(@"settings.translation.claude.error.status", @"Claude did not complete the request (%ld)."), (long)status];
    NSArray *out = nil;
    if (!failure) {
        id content = reply[@"content"];
        NSMutableString *text = [NSMutableString string];
        BOOL valid = [content isKindOfClass:NSArray.class] && [content count] <= 2000 && !reply[@"error"];
        if (valid) for (id part in content) {
            if (![part isKindOfClass:NSDictionary.class]) { valid = NO; break; }
            if (![part[@"type"] isEqual:@"text"]) continue;
            id piece = part[@"text"];
            if (![piece isKindOfClass:NSString.class] || [piece length] > 256000 - text.length) { valid = NO; break; }
            [text appendString:piece];
        }
        if (valid && ![reply[@"stop_reason"] isEqual:@"max_tokens"]) out = SGLyricsAIArrayIn(text, count);
        if (!out) failure = unreadable();
    }
    if (problem) *problem = failure;
    return out;
}

NSURLRequest *SGClaudeRequest(NSString *system, NSString *prompt, NSString **problem) {
    NSString *key = storedKey(), *model = cleanModel(setting(SGKeyLyricsClaudeModel, kModel));
    if (!key) { *problem = SGL(@"settings.translation.claude.error.nokey", @"Add a Claude API key on the Lyrics page first."); return nil; }
    if (!model) { *problem = SGL(@"settings.translation.claude.error.model", @"Check Claude's model on the Lyrics page."); return nil; }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://api.anthropic.com/v1/messages"]];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 60;
    [request setValue:key forHTTPHeaderField:@"x-api-key"];
    [request setValue:@"2023-06-01" forHTTPHeaderField:@"anthropic-version"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"model": model, @"max_tokens": @8192, @"system": system,
        @"messages": @[@{@"role": @"user", @"content": prompt}]} options:0 error:nil];
    return request;
}

void SGLyricsTranslateWithClaude(NSString *trackID, NSArray<SGKaraokeLine *> *lines, NSString *languageTag,
                                 void (^done)(NSArray<NSString *> *, NSString *)) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray *texts = SGLyricsAITexts(lines);
        NSString *prompt = texts ? SGLyricsTranslationPrompt(texts, languageTag) : nil;
        if (!prompt) { done(nil, unreadable()); return; }
        if (!SGClaudeKeySet()) { done(nil, SGL(@"settings.translation.claude.error.nokey", @"Add a Claude API key on the Lyrics page first.")); return; }
        NSString *model = setting(SGKeyLyricsClaudeModel, kModel);
        NSString *memo = [NSString stringWithFormat:@"%@|%@", trackID, languageTag];
        if (!sg_done) sg_done = [NSMutableDictionary dictionary];
        NSDictionary *cached = trackID ? sg_done[memo] : nil;
        if ([cached[@"texts"] isEqual:texts] && [cached[@"model"] isEqual:model]) { done(cached[@"answer"], nil); return; }
        if (![[texts componentsJoinedByString:@""] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) { done(texts, nil); return; }
        SGLyricsAIAsk(SGLyricsAIClaude, SGLyricsTranslationInstruction(), prompt, texts.count, ^(NSArray *answer, NSString *problem) {
            if (answer) {
                NSMutableArray *clean = [answer mutableCopy];
                for (NSUInteger i = 0; i < texts.count; i++) if (![texts[i] length]) clean[i] = @"";
                answer = [clean copy];
                if (trackID) {
                    if (sg_done.count >= 32) [sg_done removeAllObjects];
                    sg_done[memo] = @{@"texts": texts, @"model": model, @"answer": answer};
                }
            }
            done(answer, problem);
        });
    });
}

static void askForKey(void) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.translation.claudekey.title", @"Claude API key")
        message:SGL(@"settings.translation.claudekey.message", @"The song's lyrics go to Anthropic, on your own API key. The key stays on this iPhone.") preferredStyle:UIAlertControllerStyleAlert];
    __weak UIAlertController *weakAlert = alert;
    UIAlertAction *save = [UIAlertAction actionWithTitle:SGL(@"common.save", @"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSArray<UITextField *> *fields = weakAlert.textFields;
        NSString *model = cleanModel(fields[0].text), *key = cleanKey(fields[1].text);
        if (!model || !key.length || !storeKey(key)) return;
        [NSUserDefaults.standardUserDefaults setObject:model forKey:SGKeyLyricsClaudeModel];
    }];
    save.enabled = NO;
    __weak UIAlertAction *weakSave = save;
    for (NSUInteger i = 0; i < 2; i++) [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        if (i == 0) {
            field.placeholder = SGL(@"settings.translation.openaikey.model", @"Model");
            field.text = setting(SGKeyLyricsClaudeModel, kModel);
        } else {
            field.placeholder = SGL(@"settings.translation.openaikey.key", @"API key");
            field.secureTextEntry = YES;
        }
        [field addAction:[UIAction actionWithHandler:^(UIAction *action) {
            NSArray<UITextField *> *fields = weakAlert.textFields;
            if (fields.count == 2) weakSave.enabled = cleanModel(fields[0].text) && cleanKey(fields[1].text).length;
        }] forControlEvents:UIControlEventEditingChanged];
    }];
    [alert addAction:save];
    if (SGClaudeKeySet()) [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.remove", @"Remove") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { storeKey(nil); }]];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}
SGModRow *SGClaudeKeyRow(void) {
    return SGStatActionRow(SGL(@"settings.translation.claudekey.title", @"Claude API key"),
        SGL(@"settings.translation.claudekey.subtitle", @"Translate any song with your own Claude key"),
        ^NSString *{ return SGClaudeKeySet() ? SGL(@"settings.translation.openaikey.set", @"Set") : SGL(@"common.off", @"Off"); }, ^{ askForKey(); });
}
