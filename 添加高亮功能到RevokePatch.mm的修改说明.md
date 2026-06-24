# 在 RevokePatch.mm 中添加高亮功能

## 需要修改的位置

在 `YMInsertLocalAntiRevokeNotice` 函数中，在插入本地通知后，保存撤回消息信息。

## 修改步骤

### 1. 添加头文件引用

在文件顶部的 `#import` 部分添加：

```objc
#import "RevokedMessageHighlight.h"
```

### 2. 在 YMInsertLocalAntiRevokeNotice 函数中添加保存逻辑

在 `YMLog(@"insertPaySysMsgToSession result=0x%llx", (unsigned long long)result);` 之后，添加：

```objc
// 保存被撤回的消息信息，用于高亮显示
if (msgID.length > 0) {
    [[RevokedMessageHighlight sharedInstance] saveRevokedMessageWithID:msgID
                                                             session:revokeSession
                                                         replaceMsg:replaceMsg];
}
```

### 3. 完整的修改位置

在 `YMInsertLocalAntiRevokeNotice` 函数的第 1508-1510 行附近：

```objc
YMLog(@"insertPaySysMsgToSession result=0x%llx", (unsigned long long)result);

// ========== 新增：保存撤回消息信息 ==========
if (msgID.length > 0) {
    [[RevokedMessageHighlight sharedInstance] saveRevokedMessageWithID:msgID
                                                             session:revokeSession
                                                         replaceMsg:replaceMsg];
}
// ========== 新增结束 =================================

ok = YES;
```

## 说明

1. `msgID` 是被撤回消息的原始 ID
2. `revokeSession` 是会话 ID
3. `replaceMsg` 是撤回提示消息（如 "XXX 撤回了一条消息"）

## 验证修改

修改后重新编译，日志中应该能看到类似：

```
[SovietExtension] Saved revoked message: 1234567890
```

## 注意事项

1. 这个修改只负责存储撤回消息信息
2. 高亮显示需要额外 hook 消息渲染逻辑（这部分需要根据微信版本适配）
3. 如果只需要存储记录，不需要高亮显示，这个修改就足够了
