//
//  RevokedMessageHighlight.m
//  SovietExtension
//
//  撤回消息高亮功能
//

#import "RevokedMessageHighlight.h"
#import <objc/runtime.h>
#import <objc/message.h>

/// 关联对象 key，用于存储消息 ID
static const char kMessageIDKey;
static const char kRevokedHighlightKey;

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

- (void)setupHighlightHook {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Hook NSTableView 的 reloadData 方法
        // 当消息列表刷新时，我们有机会检查并添加高亮
        [self hookNSTableView];
        
        NSLog(@"[SovietExtension] RevokedMessageHighlight hooks installed");
    });
}

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

#pragma mark - Hook NSTableView

- (void)hookNSTableView {
    Class tableViewClass = [NSTableView class];
    
    if (!tableViewClass) {
        NSLog(@"[SovietExtension] NSTableView class not found");
        return;
    }
    
    // Hook reloadData 方法
    SEL originalSel = @selector(reloadData);
    SEL swizzledSel = @selector(so_reloadData);
    
    Method originalMethod = class_getInstanceMethod(tableViewClass, originalSel);
    Method swizzledMethod = class_getInstanceMethod([self class], swizzledSel);
    
    if (originalMethod && swizzledMethod) {
        method_exchangeImplementations(originalMethod, swizzledMethod);
        NSLog(@"[SovietExtension] Hooked NSTableView reloadData");
    }
    
    // Hook viewAtRow: 方法，用于在获取 Cell 时添加高亮
    SEL originalViewAtRowSel = @selector(viewAtRow:makeIfNecessary:);
    SEL swizzledViewAtRowSel = @selector(so_viewAtRow:makeIfNecessary:);
    
    Method originalViewAtRowMethod = class_getInstanceMethod(tableViewClass, originalViewAtRowSel);
    Method swizzledViewAtRowMethod = class_getInstanceMethod([self class], swizzledViewAtRowSel);
    
    if (originalViewAtRowMethod && swizzledViewAtRowMethod) {
        method_exchangeImplementations(originalViewAtRowMethod, swizzledViewAtRowMethod);
        NSLog(@"[SovietExtension] Hooked NSTableView viewAtRow:");
    }
}

#pragma mark - Swizzled Methods

// Swizzled reloadData
- (void)so_reloadData {
    // 调用原始方法
    [self so_reloadData];
    
    // 刷新后，尝试添加高亮
    [[RevokedMessageHighlight sharedInstance] highlightRevokedMessagesInTableView:(NSTableView *)self];
}

// Swizzled viewAtRow:makeIfNecessary:
- (NSView *)so_viewAtRow:(NSInteger)row makeIfNecessary:(BOOL)makeIfNecessary {
    NSView *view = [self so_viewAtRow:row makeIfNecessary:makeIfNecessary];
    
    // 在获取 view 时检查是否需要高亮
    if (view) {
        [[RevokedMessageHighlight sharedInstance] checkAndHighlightView:view atRow:row inTableView:(NSTableView *)self];
    }
    
    return view;
}

#pragma mark - Highlight Logic

- (void)highlightRevokedMessagesInTableView:(NSTableView *)tableView {
    if (!tableView) return;
    
    // 检查是否是消息列表（通过检查列数或行数特征）
    // 微信消息列表通常是单列的 TableView
    if (tableView.numberOfColumns > 2) {
        return; // 可能不是消息列表
    }
    
    // 遍历可见行，检查是否需要高亮
    NSInteger firstRow = [tableView rowsInRect:tableView.visibleRect].location;
    NSInteger lastRow = firstRow + [tableView rowsInRect:tableView.visibleRect].length;
    
    for (NSInteger row = firstRow; row < lastRow; row++) {
        NSView *view = [tableView viewAtRow:row makeIfNecessary:NO];
        if (view) {
            [self checkAndHighlightView:view atRow:row inTableView:tableView];
        }
    }
}

- (void)checkAndHighlightView:(NSView *)view atRow:(NSInteger)row inTableView:(NSTableView *)tableView {
    if (!view) return;
    
    // 检查是否已经有高亮标记
    NSView *existingHighlight = [view viewWithTag:10086];
    if (existingHighlight) {
        return; // 已经高亮过了
    }
    
    // 尝试获取消息 ID（通过关联对象或其他方式）
    NSString *messageID = objc_getAssociatedObject(view, &kMessageIDKey);
    
    // 如果没有消息 ID，尝试从子视图的 accessibilityLabel 获取
    if (!messageID) {
        messageID = [self extractMessageIDFromView:view];
    }
    
    // 检查是否被撤回
    if (messageID && [self isMessageRevoked:messageID]) {
        [self addRevokedHighlightToView:view messageID:messageID];
    }
}

- (NSString *)extractMessageIDFromView:(NSView *)view {
    // 尝试从视图的 accessibilityLabel 或其他属性提取消息 ID
    // 这里需要根据微信的实际视图结构来实现
    
    // 方法1：检查 accessibilityLabel
    NSString *accessibilityLabel = [view accessibilityLabel];
    if (accessibilityLabel && [accessibilityLabel length] > 10) {
        // 可能是消息 ID
        return accessibilityLabel;
    }
    
    // 方法2：递归检查子视图
    for (NSView *subview in view.subviews) {
        NSString *subLabel = [subview accessibilityLabel];
        if (subLabel && [subLabel length] > 10) {
            return subLabel;
        }
    }
    
    return nil;
}

- (void)addRevokedHighlightToView:(NSView *)view messageID:(NSString *)messageID {
    // 设置灰色背景
    view.wantsLayer = YES;
    view.layer.backgroundColor = [[NSColor colorWithCalibratedWhite:0.92 alpha:1.0] CGColor];
    view.layer.cornerRadius = 4.0;
    
    // 创建 "[已撤回]" 标记
    NSTextField *badge = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 70, 18)];
    badge.stringValue = @"[已撤回]";
    badge.font = [NSFont boldSystemFontOfSize:10];
    badge.textColor = [NSColor colorWithCalibratedRed:0.6 green:0.0 blue:0.0 alpha:1.0];
    badge.backgroundColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.8];
    badge.bordered = NO;
    badge.editable = NO;
    badge.selectable = NO;
    badge.tag = 10086;
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    
    // 设置圆角
    badge.wantsLayer = YES;
    badge.layer.cornerRadius = 3.0;
    
    [view addSubview:badge];
    
    // 添加约束
    [NSLayoutConstraint activateConstraints:@[
        [badge.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:8],
        [badge.topAnchor constraintEqualToAnchor:view.topAnchor constant:8]
    ]];
    
    // 添加关联对象，标记已高亮
    objc_setAssociatedObject(view, &kRevokedHighlightKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    NSLog(@"[SovietExtension] Added highlight for revoked message: %@", messageID);
}

@end
