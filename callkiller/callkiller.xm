// See http://iphonedevwiki.net/index.php/Logos

#if TARGET_OS_SIMULATOR
#error Do not support the simulator, please use the real iPhone Device.
#endif

#import <UIKit/UIKit.h>
#import <notify.h>
#import <dlfcn.h>

#import "TUCall.h"
#import "TUCallCenter.h"
#import "TUCallSoundPlayer.h"
#import "CTCallCenter.h"
#import "CXCall.h"
#import "TUProxyCall.h"
#import "TUHandle.h"
#import "CHRecentCall.h"
#import "MPRecentsTableViewCell.h"
#import "MPRecentsTableViewController.h"
#import "SBRemoteAlertAdapter.h"

#import "statics.h"
#import "Preference.h"
#import "MobileRegionDetector.h"

#define SQLITE_OPEN_READONLY 0x00000001
#define kCallDbPath @"/var/mobile/Library/CallDirectory/CallDirectory.db"

@interface SpringBoard
- (void)_updateRingerState:(int)arg1 withVisuals:(BOOL)arg2 updatePreferenceRegister:(BOOL)arg3;
@end

typedef int (*DSYSTEM)(const char *);
static DSYSTEM dsystem = 0;
static FMDatabase *db = nil;
static TUProxyCall *pendingIncomingTUCall = nil;
static BOOL pendingIncomingTUCallBlocked = NO;
static NSDictionary *pref = nil;
static NSString *mpHistoryFilePath = nil;
static NSFileHandle *mpHistoryFileHandle = nil;
static SpringBoard *sb = nil;
static BOOL isRingerOn = NO;
static BOOL isRingerTempOff = NO;

// for MobilePhone
static UIImage *blockIcon = nil;
static NSMutableArray *blockedCallUniqueIds = nil;
#define kBlockIconData3X "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"
#define kBlockIconData2X "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"

@interface LSBundleProxy
@property (nonatomic, readonly) NSURL *dataContainerURL;
+ (id)bundleProxyForIdentifier:(id)arg1;
@end

static BlockReason checkBlockReason(TUCall *call, NSString **reasonData) {
    // isBlocked表示被系统拦截？？
    if (call.isBlocked)
        return ReasonBlockedAsSystemBlacklist;
   
    // 联系人数据库位置
    // /var/mobile/Library/AddressBook/AddressBook.sqlitedb -- ABPersonFullTextSearch_content -- c16Phone
    if (call.contactIdentifier && [pref[kKeyBypassContacts] boolValue])
        return ReasonNotBlocked;
    
    NSString *phonenumber = call.handle.value;
    
    if (phonenumber.length == 0 && [pref[kKeyBlockUnknown] boolValue]) {
        // 未知号码 ？
        return ReasonBlockedAsUnknownNumber;
    }
    
    if ([phonenumber hasPrefix:@"+86"]) {
        // 去掉+86
        phonenumber = [phonenumber substringFromIndex:3];
    }
    
    // 移除前缀
    NSArray *ignoredPrefixes = pref[kKeyIgnoredPrefixes];
    for (NSArray *item in ignoredPrefixes) {
        NSString *pattern = item[1];    // 0 - user_input; 1 - pattern; 2 - comment
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
        if (regex && [regex firstMatchInString:phonenumber options:0 range: NSMakeRange(0, [phonenumber length])]) {
            phonenumber = [phonenumber substringFromIndex:pattern.length];
            break;
        }
    }
    
    if ([phonenumber hasPrefix:@"0"]) {
        // 固话，按区号拦截规则
        for (NSString *phonePrefix in pref[kKeyBlockedCitiesFlattened]) {
            if ([phonenumber hasPrefix:phonePrefix]) {
                return ReasonBlockedAsLandline;
            }
        }
    } else if (phonenumber.length == 11 && 
               ([phonenumber hasPrefix:@"13"] ||
                [phonenumber hasPrefix:@"15"] ||
                [phonenumber hasPrefix:@"17"] ||
                [phonenumber hasPrefix:@"18"] ||
                [phonenumber hasPrefix:@"19"] )) 
        {
        // 手机号，按归属地拦截规则
        NSString *regionCode = [[MobileRegionDetector sharedInstance] detectRegionCode:phonenumber];
        if (regionCode.length > 0 && [pref[kKeyMobileBlockedCitiesFlattened] containsObject:regionCode]) {
            return ReasonBlockedAsMobile;
        }
    }

    // 黑名单拦截
    NSArray *blacklist = pref[kKeyBlacklist];
    for (NSArray *item in blacklist) {
        NSString *pattern = item[1];    // 0 - user_input; 1 - pattern; 2 - comment
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
        if (regex && [regex firstMatchInString:phonenumber options:0 range: NSMakeRange(0, [phonenumber length])]) {
            return ReasonBlockedAsBlacklist;
        }
    }
    
    if (!db) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:kCallDbPath]) {
            db = [FMDatabase databaseWithPath:kCallDbPath];
            db.crashOnErrors = NO;
            db.logsErrors = NO;
            [db openWithFlags:SQLITE_OPEN_READONLY];    // 只读方式打开
        } else {
            return ReasonNotBlocked;
        }
    }
   
    // 关键字拦截
    NSString *number2Query = nil;
    if (phonenumber.length == 11 && 
        ([phonenumber hasPrefix:@"13"] ||
         [phonenumber hasPrefix:@"15"] ||
         [phonenumber hasPrefix:@"17"] ||
         [phonenumber hasPrefix:@"18"] ||
         [phonenumber hasPrefix:@"19"]
    )) {
        // 手机号
        number2Query = [NSString stringWithFormat:@"86%@", phonenumber];
    } else {
        if ([phonenumber hasPrefix:@"0"]) {
            // 0开头，表示是区号，去掉0
            phonenumber = [phonenumber substringFromIndex:1];
        }
        if (phonenumber.length < 9) {
            // 认为是短号，无需加86前缀
            number2Query = phonenumber;
        } else {
            number2Query = [NSString stringWithFormat:@"86%@", phonenumber];
        }
    }
    
    // 说明：CallDirectory.PhoneNumber.number是整型，而非字符串，这也是上面区号的情况，需要去掉前导0的原因
    
    NSString *label = nil;
    FMResultSet *rs = [db executeQuery:@"select localized_label from\
                       (select * from\
                        (select id from PhoneNumber where number = ?) as A\
                        left join PhoneNumberIdentificationEntry as B on A.id = B.phone_number_id) as C\
                       left join Label as L where L.id = C.label_id", number2Query];
    if ([rs next]) {
        label = [rs stringForColumnIndex:0];
    }
    [rs close];
    Log("== label found in db: %@", label);   // label可能是nil
    
    NSArray *keywords = pref[kKeyBlackKeywords];
    for (NSString *kwd in keywords) {
        if ([label containsString:kwd]) {
            if (reasonData) {
                *reasonData = [label copy];
            }
            return ReasonBlockedAsKeywords;
        }
    }
    return ReasonNotBlocked;
}

static void openMPHistoryFileWriteHandle() {
    if (mpHistoryFileHandle) {
        [mpHistoryFileHandle closeFile];
    }
    mpHistoryFileHandle = [NSFileHandle fileHandleForWritingAtPath:mpHistoryFilePath];
    [mpHistoryFileHandle seekToEndOfFile];
}

%group group_springboard
%hook SBTelephonyManager
-(void)callEventHandler:(NSNotification*)arg1 {
    if (![pref[kKeyEnabled] boolValue]) {
        %orig;
        return;
    }
    TUProxyCall *call = arg1.object;
    Log("call.status: %d", call.status);
    if (pendingIncomingTUCall) {
        if (call == pendingIncomingTUCall) {
            /**
             call.status:
             1 - call established
             3 - outgoing connecting
             4 - incoming ringing
             5 - disconnecting
             6 - disconnected
             // 以上是我根据调试结果推断的
             */
            if (call.status == 1) {
                // 用户手动接通
                pendingIncomingTUCall = nil;
                pendingIncomingTUCallBlocked = NO;  // just in case
            } else if (call.status == 6) { 
                // 电话被挂断
                pendingIncomingTUCall = nil;
                if (pendingIncomingTUCallBlocked) {
                    // 被我们拦截后导致的挂断
                    pendingIncomingTUCallBlocked = NO;
                    if (sb) {
                        if (isRingerTempOff) {
                            // 若临时禁用了响铃，还原它
                            isRingerTempOff = NO;
                            [sb _updateRingerState:1 withVisuals:NO updatePreferenceRegister:NO];
                        }
                    }
                    return; // 不调用 %orig
                } else {
                    pendingIncomingTUCallBlocked = NO;
                }
            } else {
                // 其他状态
                if (pendingIncomingTUCallBlocked) {
                    return; // 不调用 %orig，防止出现通话界面闪一下的情况
                }
            }
        } else {
            // 过程中来了第二通电话，不管它
        }
    } else {
        if (call.isIncoming && call.status == 4) {  // 4 ringing
            // new incoming call
            if (sb) {
                if (isRingerOn) {
                    // 临时禁用响铃
                    isRingerTempOff = YES;
                    [sb _updateRingerState:0 withVisuals:NO updatePreferenceRegister:NO];
                }
            }
            Log("== pendingIncomingTUCall: %@, contact: %@, label: %@, isBlocked: %@, sourceIdentifier: %@, displayName: %@, callerNameFromNetwork: %@", call.handle.value, call.contactIdentifier, call.localizedLabel, call.isBlocked ? @"Y" : @"N", call.sourceIdentifier, call.displayName, call.callerNameFromNetwork);
            pendingIncomingTUCall = call;
            
            NSString *keywords = nil;
            BlockReason reason = checkBlockReason(call, &keywords);
            if (reason != ReasonNotBlocked) {
                //Log("== call blocked");
                pendingIncomingTUCallBlocked = YES;
                
                // it will trigger callEventHandler immediatelly with call.status == 5
                [[TUCallCenter sharedInstance] disconnectCall:call];
                
                [[GCDQueue globalQueue] queueBlock:^{
                    NSData *recordJSON = [NSJSONSerialization dataWithJSONObject:@{
                                                                               @"u": call.uniqueProxyIdentifier,    // uid
                                                                               @"p": call.handle.value ?: @"",      // phone
                                                                               @"d": @(long([NSDate date].timeIntervalSince1970)),    // timestamp
                                                                               @"r": @(reason), // reason code
                                                                               @"rd": keywords ?: @""   // reason data(keywords)
                                                                               } 
                                                                     options:kNilOptions error:nil];
                    [mpHistoryFileHandle writeData:recordJSON];
                    [mpHistoryFileHandle writeData:[NSData dataWithBytes:"\n" length:1]];
                    [mpHistoryFileHandle synchronizeFile];
                    [[GCDQueue mainQueue] queueBlock:^{
                        notify_post(kMPHistoryAddedNotification);
                    }];
                }];
                return; // 不调用 %orig，防止出现通话界面闪一下的情况
            } else {
                // 无需拦截，若已临时禁用响铃，需要还原
                if (sb) {
                    if (isRingerTempOff) {
                        isRingerTempOff = NO;
                        [sb _updateRingerState:1 withVisuals:NO updatePreferenceRegister:NO];
                    }
                }
            }
        }
    }
    %orig;
}
%end


%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    sb = self;
    %orig;
//    freopen("/var/mobile/callkiller/callkiller.log", "a+", stderr);
    
    dsystem = (DSYSTEM)dlsym(RTLD_DEFAULT, "system");
//    dsystem("touch /var/mobile/callkiller.log");
    
    // 为MobilePhone创建拦截记录文件
    LSBundleProxy *mobilephone = [LSBundleProxy bundleProxyForIdentifier:@"com.apple.mobilephone"];
    mpHistoryFilePath = [NSString stringWithFormat:@"%@/Documents/%@", mobilephone.dataContainerURL.path, kMPHistoryFileName];
    dsystem([[NSString stringWithFormat:@"touch %@", mpHistoryFilePath] UTF8String]);
    openMPHistoryFileWriteHandle();
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:kCallDbPath]) {
        db = [FMDatabase databaseWithPath:kCallDbPath];
        db.crashOnErrors = NO;
        db.logsErrors = NO;
        [db openWithFlags:SQLITE_OPEN_READONLY];    // 只读方式打开
    }

    int token;
    notify_register_dispatch(kCallKillerPrefUpdatedNotification, &token, dispatch_get_main_queue(), ^(int token) {
        pref = [Preference load];
        // Log("== pref updated: %@", pref);
    });
    
    notify_register_dispatch(kMPHistoryFileChangedNotification, &token, dispatch_get_main_queue(), ^(int token) {
        openMPHistoryFileWriteHandle();
    });
    
    
    pref = [Preference load];
}

- (void)_updateRingerState:(int)on withVisuals:(BOOL)arg2 updatePreferenceRegister:(BOOL)arg3 {
    isRingerOn = on;
    %orig;
}

%end

%end    // group_springboard

static void loadMPBlockHistory() {
    [blockedCallUniqueIds removeAllObjects];
    NSString *mpFilePath = [NSString stringWithFormat:@"%@/Documents/%@", NSHomeDirectory(), kMPHistoryFileName];
    NSString *list = [NSString stringWithContentsOfFile:mpFilePath encoding:NSUTF8StringEncoding error:nil];
    NSArray *rows = [list componentsSeparatedByString:@"\n"];
    for (NSString *row in rows) {
        if (!row.length)
            continue;
        NSDictionary *record = [NSJSONSerialization JSONObjectWithData:[row dataUsingEncoding:NSUTF8StringEncoding] options:kNilOptions error:nil];
        if (record)
            [blockedCallUniqueIds addObject:record[@"u"]];
    }
}

static BOOL isCallUniqueIdBlockedByCallKiller(NSString *uid) {
    return [blockedCallUniqueIds containsObject:uid];
}

static NSString *urlEncode(NSString *str) {
    return (__bridge NSString *)CFURLCreateStringByAddingPercentEscapes(
                                                              NULL,
                                                              (CFStringRef)str,
                                                              NULL,
                                                              (CFStringRef)@"!*'();:@&=+$,/?%#[]",
                                                              kCFStringEncodingUTF8);
}

%group group_mobilephone

%hook MobilePhoneApplication

- (void)applicationDidFinishLaunching:(id)arg1 {
    %orig;
    NSData *iconData;
    CGFloat scale = [UIScreen mainScreen].scale;
    if (scale > 2.0) {
        iconData = [[NSData alloc] initWithBase64EncodedString:@kBlockIconData3X options:kNilOptions]; 
    } else {
        iconData = [[NSData alloc] initWithBase64EncodedString:@kBlockIconData2X options:kNilOptions]; 
    }
    blockIcon = [UIImage imageWithData: iconData scale:scale];
    
    blockedCallUniqueIds = [NSMutableArray new];
    loadMPBlockHistory();
    
    int token;
    notify_register_dispatch(kMPHistoryAddedNotification, &token, dispatch_get_main_queue(), ^(int token) {
        loadMPBlockHistory();
    });
}

%end

%hook MPRecentsTableViewController

- (UITableViewCell*)tableView:(UITableView*)tableview cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    UITableViewCell *cell = %orig;
    CHRecentCall *call = [self recentCallAtTableViewIndex:indexPath.row];
    
    if (call.callStatus == 8) { // 8 - incomingMissed
        
        BOOL blockedByCallKiller = NO;
        if ([call.callOccurrences count]) {
            // 多个电话合并
            for (NSDictionary *occurrence in call.callOccurrences) {
                if (isCallUniqueIdBlockedByCallKiller(occurrence[@"kCHCallOccurrenceUniqueIdKey"])) {
                    blockedByCallKiller = YES;
                    break;
                }
            }
        } else {
            blockedByCallKiller = isCallUniqueIdBlockedByCallKiller(call.uniqueId);
        }
            
        if (blockedByCallKiller) {
            MPRecentsTableViewCell *cell1 = (MPRecentsTableViewCell*)cell;
            cell1.callTypeIconView.image = blockIcon;
            cell1.callTypeIconView.hidden = NO;
        }
    }
    return cell;
}

%new
- (NSArray<UITableViewRowAction *> *)tableView:(UITableView *)tableView editActionsForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    NSMutableArray *actions = [NSMutableArray new];
    
    UITableViewRowAction *deleteAction = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDestructive title:@"🗑" handler:^(UITableViewRowAction * _Nonnull action, NSIndexPath * _Nonnull indexPath) {
        [tableView setEditing:NO animated:NO];
        [self tableView:tableView commitEditingStyle:UITableViewCellEditingStyleDelete forRowAtIndexPath: indexPath];
    }];
    deleteAction.backgroundColor = [UIColor colorWithHexString:@"FF6666"];
    [actions addObject:deleteAction];

    if ([NSStringFromClass(cell.class) isEqualToString:@"MPRecentsTableViewCell"]) {
        MPRecentsTableViewCell *cell1 = (MPRecentsTableViewCell*)cell;
        if (cell1.callTypeIconView.hidden || cell1.callTypeIconView.image != blockIcon) {
            
            CHRecentCall *call = [self recentCallAtTableViewIndex:indexPath.row];
            NSString *number = call.callerId ?: @"";
            NSString *label = cell1.callerLabelLabel.text;
           
            [actions insertObject:[UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleNormal title:@"🚫" handler:^(UITableViewRowAction * _Nonnull action, NSIndexPath * _Nonnull indexPath) {
                
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"设置标签 / Add Tag" message:nil preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                        NSString *label = [alert.textFields[0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                        NSString *url = [NSString stringWithFormat:@"callkiller://add_to_blacklist/?from=com.apple.mobilephone&number=%@&label=%@", urlEncode(number), urlEncode(label)];
                        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:url] options:@{} completionHandler:nil];
                    }]];
                    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
                        textField.text = label;
                    }];
                    [(UIViewController *)self presentViewController:alert animated:YES completion:nil];
                });
                [tableView setEditing:NO animated:YES];
            }] atIndex:0];
        }
    }
    return actions;
}

%end    // hook MPRecentsTableViewController
%end    // group group_mobilephone

%ctor {
    NSString *bundle = [NSBundle mainBundle].bundleIdentifier;
    if ([bundle isEqualToString:@"com.apple.springboard"]) {
        %init(group_springboard);
    } else if ([bundle isEqualToString:@"com.apple.mobilephone"] && 
               [[Preference loadMPPref][kKeyMPInjectionEnabled] boolValue]) {
        %init(group_mobilephone);
    }
}

//%hook CHManager
//
//- (void)deleteAllCalls {
//    %orig;
//}
//- (void)deleteAllCallsSync {
//    %orig;
//}
//- (void)deleteCall:(id)arg1 {
//    %orig;
//}
//- (void)deleteCallAtIndex:(unsigned long long)arg1 {
//    %orig;
//}
//- (void)deleteCallsWithPredicate:(id)arg1 {
//    %orig;
//}
//- (void)deleteTheseCalls:(NSArray*)arg1 {
//    BOOL needNotify = NO;
//    for (CHRecentCall *call in arg1) {
//        if (blockedCallUniqueIds containsObject:call.uniqueId) {
//            needNotify = YES;
//            [blockedCallUniqueIds removeObject:call.uniqueId];
//        }
//    }
//    if (needNotify)
//        notify_post("com.laoyur.callkiller.callhistory-changed-by-user");
//    %orig;
//}
//- (void)deleteTheseCallsSync:(id)arg1 {
//    %orig;
//}
//
//%end

//%hook ICFCallServer
//
//- (void)shouldAllowIncomingCallForNumber:(id)arg1 forProviderIdentifier:(id)arg2 response:(id /* block */)arg3 {
//    Log("shouldAllowIncomingCallForNumber: %@ forProviderIdentifier:%@ response:%@", arg1, arg2, arg3);
//    %orig;
//}
//
//%end
//
//%hook TPInCallUILauncher
//+ (void)launchInCallUIForReason:(long long)arg1 completion:(id /* block */)arg2 {
//    Log("launchInCallUIForReason: %ld completion:%@", arg1, arg2);
//    %orig;
//}
//%end

//@interface SBAlertWindow: UIWindow
//@end
//
//%hook SBAlertWindow
//
//-(void)addView:(id)arg1 toBeObscuredByAlert:(id)arg2 {
//    Log("SBAlertWindow addView: %@ toBeObscuredByAlert:%@", arg1, arg2);
//    %orig;
//}
//-(void)displayAlert:(NSObject*)arg1 {
//    Log("SBAlertWindow displayAlert: %@", arg1);
//    if ([NSStringFromClass(arg1.class) isEqualToString:@"SBRemoteAlertAdapter"]) {
//        SBRemoteAlertAdapter *alert = (SBRemoteAlertAdapter*)arg1;
//        if ([alert.serviceBundleIdentifier isEqualToString:@"com.apple.InCallService"]) {
//            Log("SBRemoteAlertAdapter will display");
//        }
//    }
//    %orig;
//    
//    //test
////    self.frame = CGRectMake(2000, 0, 0, 0);
//}
//-(BOOL)deactivateAlert:(id)arg1 {
//    Log("SBAlertWindow deactivateAlert: %@", arg1);
//    return %orig;
//}
//-(void)setRootViewController:(id)arg1 {
//    Log("SBAlertWindow setRootViewController: %@", arg1);
//    return %orig;
//}
//
//%end
//
//@interface SBAlertWindowViewController : UIViewController
//-(void)setActiveAlert:(id)arg1;
//@end

//%hook SBAlertWindowViewController
//
//-(void)addAlertController:(id)arg1 {
//    Log("SBAlertWindowViewController addAlertController: %@", arg1);
//    %orig;
//}

//-(void)setActiveAlert:(id)arg1 {
//    Log("SBAlertWindowViewController setActiveAlert: %@", arg1);
//    %orig;
//}

//%end

