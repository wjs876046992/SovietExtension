//
//  RevokedMessageHighlight.m
//  SovietExtension
//
//  Created by SovietExtension on 2026/6/24.
//  撤回消息高亮功能 - 轻量级实现
//

#import "RevokedMessageHighlight.h"

@implementation RevokedMessageHighlight

#pragma mark - Singleton

+ (instancetype)sharedInstance {
    static RevokedMessageHighlight *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

#pragma mark - Public

- (void)saveRevokedMessageWithID:(NSString *)msgID
                         session:(NSString *)session
                     replaceMsg:(NSString *)replaceMsg {
    if (!msgID || msgID.length == 0) {
        return;
    }
    
    NSMutableArray *revokedMessages = [self getRevokedMessagesArray];
    
    // 检查是否已存在
    for (NSDictionary *msg in revokedMessages) {
        if ([msg[@"msgID"] isEqualToString:msgID]) {
            return; // 已存在，不重复添加
        }
    }
    
    NSDictionary *revokedMsg = @{
        @"msgID": msgID ?: @"",
        @"session": session ?: @"",
        @"replaceMsg": replaceMsg ?: @"[撤回消息]",
        @"revokedAt": @([[NSDate date] timeIntervalSince1970])
    };
    
    [revokedMessages addObject:revokedMsg];
    
    [[NSUserDefaults standardUserDefaults] setObject:revokedMessages
                                              forKey:kRevokedMessagesKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    NSLog(@"[SovietExtension] Saved revoked message: %@", msgID);
}

- (BOOL)isMessageRevoked:(NSString *)msgID {
    if (!msgID || msgID.length == 0) {
        return NO;
    }
    
    NSArray *revokedMessages = [[NSUserDefaults standardUserDefaults] arrayForKey:kRevokedMessagesKey];
    
    for (NSDictionary *msg in revokedMessages) {
        if ([msg[@"msgID"] isEqualToString:msgID]) {
            return YES;
        }
    }
    
    return NO;
}

- (NSString *)revokedNoticeForMessageID:(NSString *)msgID {
    if (!msgID || msgID.length == 0) {
        return nil;
    }
    
    NSArray *revokedMessages = [[NSUserDefaults standardUserDefaults] arrayForKey:kRevokedMessagesKey];
    
    for (NSDictionary *msg in revokedMessages) {
        if ([msg[@"msgID"] isEqualToString:msgID]) {
            return msg[@"replaceMsg"];
        }
    }
    
    return nil;
}

- (void)clearAllRevokedMessages {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kRevokedMessagesKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    NSLog(@"[SovietExtension] Cleared all revoked messages");
}

#pragma mark - Private

- (NSMutableArray *)getRevokedMessagesArray {
    NSArray *existing = [[NSUserDefaults standardUserDefaults] arrayForKey:kRevokedMessagesKey];
    return existing ? [existing mutableCopy] : [NSMutableArray array];
}

@end
