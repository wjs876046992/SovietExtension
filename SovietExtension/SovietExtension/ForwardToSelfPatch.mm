//
//  ForwardToSelfPatch.mm
//  SovietExtension
//
//  ============================================================
//  撤回消息 → 同步发送给自己（全设备同步）
//  ============================================================
//
//  ★ 核心思路：在微信撤回回调里拿到原始消息内容，通过 SendMsg CGI
//    （sub_8da920）构造 type=5 文本消息发给自己的账号，全设备同步。
//
//  ★ 依赖（共 1 个 VM 地址）：
//     sub_8da920 (VA 0x8da920) — SendMsg CGI dispatcher
//     - Hopper: strings → "sendmsg_Send" 交叉引用定位
//     - x0 = 请求对象（80*8=640 字节），x1 = 1（发送标志）
//     - profile.sendMsgCGIVA 管理，YMSendMsgCGIRuntimeAddress() 取
//
//  ★ 请求对象布局（堆上构造，4 轮试错确认）：
//     +0x000: uint32_t type = 5
//     +0x120: std::string to       （接收方 wxid）
//     +0x138: std::string content  （消息正文）
//     +0x150: std::string from     （发送方 wxid）
//
//  ★ 废弃路径（试错记录，供后续版本适配参考）：
//     ① sub_8d8be8 type=1 → sub_1f3ab7c r2=0 → 只本地插入不走网络
//     ② sub_8da920 x1=0 → ccmn 检查失败 → 对象缺少关键字段
//     ③ 0x50FDCC + raw MessageWrap → 撤回栈无 conversation owner → SIGSEGV
//     ④ Bridge Replay 0x50C8F4 → 跨会话重放崩溃 + 需预热缓存
//     ⑤ sub_8d8be8 type=0(sub_8da710) → x1 必须有效会话上下文
//     ⑥ sub_8d8be8 type=3(sub_1f36da8) → CDN hex ≠ 真实 URL，失败
//     ⑦ sub_569528(extObject, cdnStr, flag) → x0 extObject 无效
//
//  ★ MessageWrap 字段布局（616 字节，2026-06-26 日志确认）：
//     +0x18 (24)  = 会话展示名（私聊=对方号，群聊=群ID?）
//     +0x30 (48)  = 自身 wxid — 群聊/图片消息时可能变 @chatroom
//     +0x48 (72)  = 发送者 wxid — 永不 chatroom
//     +0x100(256) = 毫秒创建时间
//     +0x108(264) = 消息类型 (originType)
//     +0x114(276) = 秒级创建时间
//     +0x130(304) = 消息内容 (文本=原文, 图片=CDN XML)
//     +0x148(328) = content/XML（另一偏移，可能冗余）
//     +0x160(352) = msgSource XML
//     +0x268(616) = 有效标志 (0=已删除)
//     selfUser 推断：别人撤回用 +0x30；是 chatroom 则回退 +0x48
//
//  ★ 撤回人补齐：图片消息时 FindRevokeXML 返回空，用 +0x48 补齐
//
//  ★ 群名获取（0 新增 hook/VM 地址，复用已有基础设施）：
//     WeChat 没有暴露「给定 roomID 查群名」的同步查询函数。群名走的链路是
//     Contact 列表 → sub_37ef000 批量遍历 → sub_2f16d4c(Contact, &0x3c0)
//     → sub_37ec73c → UpdateSessionCache。我们 hook UpdateSessionCache 读取
//     参数 a2 的固定偏移来获取群名。
//     Hopper 追踪链（2026-06-26）：
//       session_service::UpdateSessionCache (0x37EACC0)
//         ← sub_37ec73c (构造 a2，a2+0x120 由 sub_2f17f3c+204 填入)
//         ← sub_37f26ac (传入源结构体 [fp-0x40])
//         ← sub_37f266c (迭代器 wrapper)
//         ← sub_37fddb8 / sub_37fe74c (Contact 批量处理入口)
//     ① 主路径：YMCachedRoomName(roomID) 查缓存，偏移（2026-06-26 确认）：
//          a2+0x000 = roomID   (std::string, "19228060266@chatroom")
//          a2+0x120 = 群名     (std::string, "小马甲")
//     ② 兜底：缓存未命中时 RevokePatch 调 GetAllMemberDataList 主动加载，
//        触发 UpdateSessionCache 后缓存即被填充
//     ③ 最终回退：以上均失败则直接用 roomID
//     → 偏移失效时扫 a2[0..0x400] 重定位，或沿上面 Hopper 链重新确认
//
//  ★ 图片/视频/文件 转发（TODO，当前仅发文本通知）：
//     试错记录（2026-06-26）：
//     ⑧ sub_8d8be8 type=3 直调：+0x80 填 session 触发 prologue，CDN hex
//        数据填入 +0x0c0~+0x150，返回成功但接收端将 CDN hex 误判为链接——
//        请求对象字段布局不完整。
//     ⑨ sub_5699d0(service, request)：service 取 savedRegs[0]=0x100..无效、
//        savedRegs[4]=0xa.. 崩——x1 结构体字段要求不明。
//     ⑩ sub_486619c 解析 CDN XML：只填 hdlength/thumb 等元数据，不构造完整请求。
//     ⑪ sub_8d8be8 inline hook 探针：发新图不经过 sub_8d8be8（图片异步上传→回调
//        直调 sub_56b14c→sub_1f36da8，绕过总调度器）。
//     Hopper type dispatch（供后续参考）：
//       sub_8d8be8(0x8d8be8):
//         loc_8d93f4 type=3→sub_1f36da8   loc_8d925c type=5→sub_8da920
//       sub_5699d0(service,request):
//         type=3→sub_56b14c   type=5→sub_8da920
//     请求对象 type=3 已知字段（loc_8d93f4）：
//       +0x080=session, +0x0c0=aeskey, +0x0d8=md5,
//       +0x0f0=cdnbigimgurl, +0x108=cdnmidimgurl, +0x120=to, +0x150=from
//     outWrap 可用数据（撤回时）：
//       +0x130=CDN XML   +0x160=msgsource
//
//  loc_8d8e10: r8 = *(int32_t *)r19        ; r19 = 请求对象
//   type 0,1 → loc_8d8f48 → sub_1f3ab7c   (文本，本地)
//   type 2   → sub_1eca70c                (文件?)
//   type 3   → loc_8d93f4 → sub_1f36da8   (★ 图片!)
//   type 4   → sub_1f3fd08                (视频?)
//   type 5   → loc_8d925c → sub_8da920    (★ 文本，我们用的)
//   type 6   → sub_1f3dd78                (链接?)
//   type 7   → sub_1f3eae8                (位置?)
//   type 8   → loc_8d95c4                (表情/名片?)
//
//  ★ 门控：NSUserDefaults("kRevokeForwardToSelfRealSend.SOVIET")
//         或 /tmp/YMRevokeForwardToSelfRealSend 文件哨兵
//
//  ★ 日志：grep "RevokeAutoForward" /tmp/YMWeChatAntiRevokePatch.log
//

#import "ForwardToSelfPatch.h"
#import "RevokePatch.h"
#import <objc/message.h>

#include <string>
#include <new>

// ============================================================
// 门控
// ============================================================

BOOL YMRevokeRealSendForwardEnabled(void) {
    BOOL defaultsArmed = [[NSUserDefaults standardUserDefaults] boolForKey:@"kRevokeForwardToSelfRealSend.SOVIET"];
    BOOL fileArmed = [[NSFileManager defaultManager] fileExistsAtPath:@"/tmp/YMRevokeForwardToSelfRealSend"];
    return defaultsArmed || fileArmed;
}

// ============================================================
// 格式化辅助
// ============================================================

static BOOL YMForwardTextIsBuiltinEmoji(NSString *text) {
    NSString *value = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    return value.length >= 3 && value.length <= 32 &&
           [value hasPrefix:@"["] && [value hasSuffix:@"]"] &&
           [value rangeOfString:@"\n"].location == NSNotFound;
}

static BOOL YMForwardTextLooksUseless(NSString *text) {
    if (text.length == 0) return NO;
    return [text containsString:@"暂不支持该内容"] ||
           [text containsString:@"请在手机上查看"];
}

/// 群聊消息格式为 wxid_xxx:\n内容，拆出发送者和正文
static NSString *YMForwardCleanContent(NSString *rawContent, NSString **senderOut) {
    if (senderOut) *senderOut = @"";
    if (rawContent.length == 0) return @"";
    NSString *text = [rawContent stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    NSRange colonNewline = [text rangeOfString:@":\n"];
    if (colonNewline.location != NSNotFound && colonNewline.location > 0) {
        NSString *prefix = [text substringToIndex:colonNewline.location];
        NSString *body   = [text substringFromIndex:NSMaxRange(colonNewline)];
        prefix = [prefix stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        body   = [body stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (prefix.length > 0 && senderOut) *senderOut = prefix;
        if (body.length > 0) return body;
    }
    return text;
}

static NSString *YMForwardContentDisplay(uint32_t type, NSString *cleanContent) {
    switch (type) {
        case 1: return (YMForwardTextIsBuiltinEmoji(cleanContent) && cleanContent.length) ? cleanContent : (cleanContent.length > 0 ? cleanContent : @"（空）");
        case 3:  return @"[图片]";
        case 34: return @"[语音]";
        case 43: return @"[视频]";
        case 47: return @"[表情包]";
        case 48: return @"[位置]";
        case 49: return @"[文件/链接/卡片]";
        default: return [NSString stringWithFormat:@"[%u]", type];
    }
}

static NSString *YMForwardRevokerDisplay(NSString *displayName, NSString *wxid, NSString *sender) {
    if (displayName.length > 0) return displayName;
    if (wxid.length > 0) return wxid;
    if (sender.length > 0) return sender;
    return @"***";
}

// ============================================================
// 构建转发通知文本
// 格式：
//   --拦截到一条撤回消息--
//   群名:xxx
//   撤回人:xxx
//   内容:[文本/图片/视频/语音/表情包/…]
//   (请保证网络良好)
//
// 群聊时通过 YMCachedRoomName(sessionText) 查群名（缓存由
// UpdateSessionCache hook 喂入），未命中回退为 roomID。
// ============================================================

static NSString *YMBuildRevokeForwardNotice(NSString *sessionText,
                                      uint32_t    originType,
                                      NSString   *originRawContent,
                                      NSString   *revokerWxid,
                                      NSString   *revokerDisplayName)
{
    NSString *sender = @"";
    NSString *clean = originRawContent;
    if (originType == 1) {
        clean = YMForwardCleanContent(originRawContent, &sender);
        if (YMForwardTextLooksUseless(clean)) clean = @"";
    }
    if (clean.length > 1600) {
        clean = [[clean substringToIndex:1600] stringByAppendingString:@"…"];
    }
    NSString *contentDisplay = YMForwardContentDisplay(originType, clean);
    NSString *revokerDisplay = YMForwardRevokerDisplay(revokerDisplayName, revokerWxid, sender);

    NSMutableString *notice = [NSMutableString string];
    [notice appendString:@"--拦截到一条撤回消息--\n"];
    if ([sessionText containsString:@"@chatroom"]) {
        NSString *roomName = YMCachedRoomName(sessionText);
        [notice appendFormat:@"群名:%@\n", roomName.length > 0 ? roomName : (sessionText.length > 0 ? sessionText : @"未知群聊")];
    }
    [notice appendFormat:@"撤回人:%@\n", revokerDisplay.length > 0 ? revokerDisplay : @"***"];
    [notice appendFormat:@"内容:%@", contentDisplay.length > 0 ? contentDisplay : @"（空）"];
    if (originType != 1) {
        [notice appendString:@"\n(请保证网络良好)"];
    }
    return notice;
}

// ============================================================
// sub_8da920 type=5 发送：obj+0x000=type, +0x120=to, +0x138=content, +0x150=from
// ============================================================

static BOOL YMForwardViaSendMsgCGI(NSString *selfId, NSString *content) {
    if (!selfId.length || !content.length) return NO;

    uintptr_t fn = YMSendMsgCGIRuntimeAddress();
    if (!fn) return NO;

    uintptr_t obj[80] = {};
    *((uint32_t *)obj) = 5;
    new ((std::string *)((uintptr_t)obj + 0x120)) std::string(selfId.UTF8String);
    new ((std::string *)((uintptr_t)obj + 0x138)) std::string(content.UTF8String);
    new ((std::string *)((uintptr_t)obj + 0x150)) std::string(selfId.UTF8String);
    @try { ((int64_t(*)(uintptr_t,uintptr_t))fn)((uintptr_t)obj, 1); } @catch(...) {}
    ((std::string *)((uintptr_t)obj + 0x150))->~basic_string();
    ((std::string *)((uintptr_t)obj + 0x138))->~basic_string();
    ((std::string *)((uintptr_t)obj + 0x120))->~basic_string();
    return YES;
}

// ============================================================
// 统一入口
// ============================================================

BOOL YMForwardToSelfSend(uintptr_t outWrap,
                         uint32_t  originType,
                         NSString *originContent,
                         NSString *sessionText,
                         NSString *revokerWxid,
                         NSString *revokerDisplayName)
{
    if (!outWrap) return NO;

    // selfUser 偏移：+0x30(hex) 是自身号但图片/自己撤回时变 chatroom
    // +0x48(hex) 是发送者号，永不 chatroom
    NSString *hex30 = [NSString stringWithUTF8String:((std::string *)(outWrap + 0x30))->c_str()];
    NSString *hex48 = [NSString stringWithUTF8String:((std::string *)(outWrap + 0x48))->c_str()];
    BOOL revokeByMe = [revokerDisplayName isEqualToString:@"你"];
    NSString *selfId = revokeByMe ? hex48 : ([hex30 containsString:@"@chatroom"] ? hex48 : hex30);
    if (!selfId.length) return NO;

    // 图片消息时 FindRevokeXML 返回空，用 +0x48 补齐
    if (revokerWxid.length == 0) revokerWxid = hex48;
    if (revokerDisplayName.length == 0) revokerDisplayName = [hex48 isEqualToString:selfId] ? @"你" : hex48;

    // 发送文本通知（始终发送，含群名/撤回人/内容概要）
    NSString *notice = YMBuildRevokeForwardNotice(sessionText, originType,
                                                   originContent,
                                                   revokerWxid, revokerDisplayName);
    if (notice.length) {
        YMForwardViaSendMsgCGI(selfId, notice);
    }

    // TODO: 图片/视频实际内容转发 — 见文件头「图片/视频/文件 转发」试错记录

    return YES;
}
