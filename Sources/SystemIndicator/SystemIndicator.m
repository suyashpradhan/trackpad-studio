// Private selector and graphic IDs referenced from EdgePad (see THIRD_PARTY_NOTICES.md).
#import "SystemIndicator.h"
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <math.h>
#import <string.h>

bool TSShowVolumeIndicator(double level, uint32_t displayID) {
    static id manager;
    static SEL show;
    static NSMethodSignature *signature;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSBundle *framework = [NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/OSD.framework"];
        if (![framework load]) return;
        Class cls = NSClassFromString(@"OSDManager");
        SEL shared = NSSelectorFromString(@"sharedManager");
        if (![cls respondsToSelector:shared]) return;
        NSMethodSignature *factory = [cls methodSignatureForSelector:shared];
        if (factory.numberOfArguments != 2 || strcmp(factory.methodReturnType, "@")) return;
        manager = ((id (*)(id, SEL))objc_msgSend)(cls, shared);
        show = NSSelectorFromString(@"showImage:onDisplayID:priority:msecUntilFade:filledChiclets:totalChiclets:locked:");
        if (![manager respondsToSelector:show]) return;
        NSMethodSignature *candidate = [manager methodSignatureForSelector:show];
        if (candidate.numberOfArguments != 9 || strcmp(candidate.methodReturnType, "v")) return;
        for (NSUInteger i = 2; i < 9; ++i) {
            const char *type = [candidate getArgumentTypeAtIndex:i];
            if (strlen(type) != 1 || !strchr("cCsSiIlLqQB", type[0])) return;
        }
        signature = candidate;
    });
    if (!signature || !isfinite(level)) return false;
    // macOS on Intel and Apple Silicon is little-endian. NSInvocation copies
    // the declared argument width, including 1-byte BOOL and 4-byte display ID.
    uint64_t args[] = {level <= 0 ? 4u : 3u, displayID, 500, 900,
                       (uint64_t)llround(fmin(1, fmax(0, level)) * 100), 100, 0};
    @try {
        NSInvocation *call = [NSInvocation invocationWithMethodSignature:signature];
        call.selector = show;
        for (NSUInteger i = 0; i < 7; ++i) [call setArgument:&args[i] atIndex:i + 2];
        [call invokeWithTarget:manager];
        return true;
    } @catch (NSException *exception) {
        return false;
    }
}
