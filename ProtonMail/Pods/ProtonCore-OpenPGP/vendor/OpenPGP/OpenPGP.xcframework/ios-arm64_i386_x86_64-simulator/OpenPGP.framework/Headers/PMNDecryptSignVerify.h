// AUTOGENERATED FILE - DO NOT MODIFY!
// This file generated by Djinni from open_pgp.djinni

#import <Foundation/Foundation.h>

@interface PMNDecryptSignVerify : NSObject
- (nonnull instancetype)initWithPlainText:(nonnull NSString *)plainText
                                   verify:(BOOL)verify;
+ (nonnull instancetype)decryptSignVerifyWithPlainText:(nonnull NSString *)plainText
                                                verify:(BOOL)verify;

@property (nonatomic, readonly, nonnull) NSString * plainText;

@property (nonatomic, readonly) BOOL verify;

@end