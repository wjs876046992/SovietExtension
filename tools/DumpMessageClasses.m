//
//  DumpMessageClasses.m
//  用于提取微信消息相关的 ObjC 类名
//
//  使用方法：
//  1. cd /path/to/SovietExtension/tools
//  2. clang -dynamiclib -framework Foundation -fobjc-arc DumpMessageClasses.m -o DumpMessageClasses.dylib
//  3. 退出微信
//  4. DYLD_INSERT_LIBRARIES=/path/to/DumpMessageClasses.dylib open /Applications/微信2.app
//  5. 等待3秒，查看 /tmp/wechat_message_classes.txt
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

__attribute__((constructor))
static void dumpMessageClasses() {
    NSString *outputPath = @"/tmp/wechat_message_classes.txt";
    NSMutableString *result = [NSMutableString string];
    
    [result appendString:@"=== 微信消息相关类名 ===\n\n"];
    
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    
    // 筛选关键词
    NSArray *keywords = @[
        @"Message", @"Chat", @"Cell", @"Bubble", @"Content",
        @"Session", @"Revoke", @"Wrap", @"Service", @"View",
        @"List", @"Table", @"Collection", @"DataSource", @"Delegate"
    ];
    
    NSMutableArray *matchedClasses = [NSMutableArray array];
    
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = NSStringFromClass(classes[i]);
        
        for (NSString *keyword in keywords) {
            if ([name rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [matchedClasses addObject:name];
                break;
            }
        }
    }
    
    // 排序
    [matchedClasses sortUsingSelector:@selector(compare:)];
    
    // 分类输出
    [result appendString:@"--- Message 相关 ---\n"];
    for (NSString *name in matchedClasses) {
        if ([name rangeOfString:@"Message" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [result appendFormat:@"%@\n", name];
        }
    }
    
    [result appendString:@"\n--- Chat 相关 ---\n"];
    for (NSString *name in matchedClasses) {
        if ([name rangeOfString:@"Chat" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [result appendFormat:@"%@\n", name];
        }
    }
    
    [result appendString:@"\n--- Cell 相关 ---\n"];
    for (NSString *name in matchedClasses) {
        if ([name rangeOfString:@"Cell" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [result appendFormat:@"%@\n", name];
        }
    }
    
    [result appendString:@"\n--- Session 相关 ---\n"];
    for (NSString *name in matchedClasses) {
        if ([name rangeOfString:@"Session" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [result appendFormat:@"%@\n", name];
        }
    }
    
    [result appendString:@"\n--- Content 相关 ---\n"];
    for (NSString *name in matchedClasses) {
        if ([name rangeOfString:@"Content" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [result appendFormat:@"%@\n", name];
        }
    }
    
    [result appendString:@"\n--- Wrap 相关 ---\n"];
    for (NSString *name in matchedClasses) {
        if ([name rangeOfString:@"Wrap" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [result appendFormat:@"%@\n", name];
        }
    }
    
    [result appendString:@"\n--- Service 相关 ---\n"];
    for (NSString *name in matchedClasses) {
        if ([name rangeOfString:@"Service" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [result appendFormat:@"%@\n", name];
        }
    }
    
    [result appendString:@"\n--- View 相关 ---\n"];
    for (NSString *name in matchedClasses) {
        if ([name rangeOfString:@"View" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [result appendFormat:@"%@\n", name];
        }
    }
    
    [result appendString:@"\n--- Revoke 相关 ---\n"];
    for (NSString *name in matchedClasses) {
        if ([name rangeOfString:@"Revoke" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [result appendFormat:@"%@\n", name];
        }
    }
    
    [result appendFormat:@"\n总计匹配: %lu 个类\n", (unsigned long)matchedClasses.count];
    [result appendFormat:@"总类数: %u\n", count];
    
    [result writeToFile:outputPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    
    NSLog(@"[DumpClasses] 已保存到 %@", outputPath);
    
    free(classes);
}
