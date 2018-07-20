// See http://iphonedevwiki.net/index.php/Logos

#if TARGET_OS_SIMULATOR
#error Do not support the simulator, please use the real iPhone Device.
#endif

#import <UIKit/UIKit.h>
#import <notify.h>

#import "TUCall.h"
#import "TUCallCenter.h"
#import "TUCallSoundPlayer.h"
#import "CTCallCenter.h"
#import "CXCall.h"
#import "TUProxyCall.h"
#import "TUHandle.h"

#import "statics.h"
#import "Preference.h"

#define SQLITE_OPEN_READONLY 0x00000001
#define kCallDbPath @"/var/mobile/Library/CallDirectory/CallDirectory.db"

static FMDatabase *db = nil;
static TUProxyCall *pendingIncomingTUCall = nil;
static NSDictionary *pref = nil;

static void Log(const char *fmt, ...) {
    static NSDateFormatter *dateFormatter = nil;
    if (!dateFormatter) {
        dateFormatter = [NSDateFormatter new];
        [dateFormatter setTimeZone:[NSTimeZone timeZoneWithName:@"Asia/Shanghai"]];
        dateFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    }
    
    va_list arg_ptr; 
    va_start(arg_ptr, fmt); 
    NSString *format = [[NSString stringWithUTF8String:fmt] stringByAppendingString:@"\n"];
    NSString *now = [dateFormatter stringFromDate:[NSDate date]];
    NSString *msg = [[NSString alloc] initWithFormat:[NSString stringWithFormat:@"%@ %@", now, format] arguments:arg_ptr]; 
    va_end(arg_ptr); 
    
    // append
    NSString *path = @"/var/mobile/callkiller.log";
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    [handle truncateFileAtOffset:[handle seekToEndOfFile]];
    [handle writeData:[msg dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

static BOOL isCallInBlackList(TUCall *call) {
    // ?? 不确定isBlocked这个属性有没有作用
    if (call.isBlocked)
        return YES;
   
    // 联系人数据库位置
    // /var/mobile/Library/AddressBook/AddressBook.sqlitedb -- ABPersonFullTextSearch_content -- c16Phone
    if (call.contactIdentifier && [pref[kKeyBypassContacts] boolValue])
        return NO;
    
    NSString *phonenumber = call.handle.value;
    
    if (phonenumber.length == 0 && [pref[kKeyBlockUnknown] boolValue]) {
        // 未知号码 ？
        return YES;
    }
    
    if ([phonenumber hasPrefix:@"+86"]) {
        // 去掉+86
        phonenumber = [phonenumber substringFromIndex:3];
    }
    
    if ([phonenumber hasPrefix:@"0"]) {
        // 按区号拦截规则
        for (NSString *phonePrefix in pref[kKeyBlockedCitiesFlattened]) {
            if ([phonenumber hasPrefix:phonePrefix]) {
                return YES;
            }
        }
    }

    // 黑名单拦截
    NSArray *blacklist = pref[kKeyBlacklist];
    for (NSArray *item in blacklist) {
        NSString *pattern = item[1];    // 0 - user_input; 1 - pattern; 2 - comment
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
        if (regex && [regex firstMatchInString:phonenumber options:0 range: NSMakeRange(0, [phonenumber length])]) {
            return YES;
        }
    }
    
    if (!db) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:kCallDbPath]) {
            db = [FMDatabase databaseWithPath:kCallDbPath];
            db.crashOnErrors = NO;
            db.logsErrors = NO;
            [db openWithFlags:SQLITE_OPEN_READONLY];    // 只读方式打开
        } else {
            return NO;
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
    Log("==== label found in db: %@", label);   // label可能是nil
    
    NSArray *keywords = pref[kKeyBlackKeywords];
    for (NSString *kwd in keywords) {
        if ([label containsString:kwd]) {
            return YES;
        }
    }
    return NO;
}

%hook SBTelephonyManager
-(void)callEventHandler:(NSNotification*)arg1 {
    if (![pref[kKeyEnabled] boolValue]) {
        %orig;
        return;
    }
    TUProxyCall *call = arg1.object;
//    Log("call status: %d", call.callStatus);
    if (pendingIncomingTUCall) {
        if (call == pendingIncomingTUCall) {
            /**
             call.callStatus:
             1 - call established
             3 - outgoing connecting
             4 - incoming ringing
             6 - disconnected
             // 以上是我根据调试结果推断的
             */
            if (call.callStatus == 1 ||     // 接通
                call.callStatus == 6) {     // 挂断
                pendingIncomingTUCall = nil;
//                Log("==== pendingIncomingTUCall set nil");
            }
        } else {
            // 过程中来了第二通电话，不管它
        }
    } else {
        if (call.isIncoming && call.callStatus == 4) {  // 4 ringing
            // new incoming call
            Log("==== pendingIncomingTUCall: %@, contact: %@, label: %@, isBlocked: %@", call.handle.value, call.contactIdentifier, call.localizedLabel, call.isBlocked ? @"Y" : @"N");
            pendingIncomingTUCall = call;
            
            if (isCallInBlackList(call)) {
                Log("==== call blocked");
                [[TUCallCenter sharedInstance] disconnectCall:call];
                return; // 不调用 %orig，防止出现通话界面闪一下的情况
            }
        }
    }
    %orig;
}
%end

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    
    // remove the log file created in 1.0.0
    NSString *path = @"/var/mobile/callkiller.log";
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:kCallDbPath]) {
        db = [FMDatabase databaseWithPath:kCallDbPath];
        db.crashOnErrors = NO;
        db.logsErrors = NO;
        [db openWithFlags:SQLITE_OPEN_READONLY];    // 只读方式打开
    }
    int token;
    notify_register_dispatch("com.laoyur.callkiller.preference-updated", &token, dispatch_get_main_queue(), ^(int token) {
        pref = [Preference load];
        // Log("== pref updated: %@", pref);
    });
    pref = [Preference load];
}

%end
