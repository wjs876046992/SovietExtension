//
//  RevokedMessageHighlight.h
//  SovietExtension
//
//  撤回消息高亮功能
//

#import <Foundation/Foundation.h>

/// 存储被撤回消息的 key
#define kRevokedMessagesKey @"SovietExtension_RevokedMessages"

@interface RevokedMessageHighlight : NSObject

/// 单例
+ (instancetype)sharedInstance;

/// 初始化高亮功能
- (void)setupHighlightHook;

/// 存储被撤回的消息
/// @param msgID 消息ID
/// @param session 会话ID
/// @param replaceMsg 撤回提示消息
- (void)saveRevokedMessageWithID:(NSString *)msgID
                         session:(NSString *)session
                     replaceMsg:(NSString *)replaceMsg;

/// 检查消息是否被撤回
/// @param msgID 消息ID
- (BOOL)isMessageRevoked:(NSString *)msgID;

/// 获取被撤回消息的提示文本
/// @param msgID 消息ID
- (NSString *)revokedNoticeForMessageID:(NSString *)msgID;

/// 清除所有撤回记录
- (void)clearAllRevokedMessages;

@end
