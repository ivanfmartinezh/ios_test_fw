// AUTOGENERATED FILE - DO NOT MODIFY!
// This file generated by Djinni from open_pgp.djinni

#import "PMNAddress.h"
#import "PMNDecryptSignVerify.h"
#import "PMNEncryptPackage.h"
#import "PMNEncryptSignPackage.h"
#import "PMNOpenPgpKey.h"
#import <Foundation/Foundation.h>
@class PMNOpenPgp;


/**
 *open_pgp_key_manager = interface +c {
 *    static create_instance() : open_pgp_key_manager;
 *}
 *generat new key with email address. Fix the UserID issue in protonmail system. on Feb 28, 17
 *static generate_key_with_email(email : string, passphrase : string, bits : i32) : open_pgp_key;
 * generate new key
 *static generate_new_key(user_id : string, email : string, passphrase : string, bits : i32) : open_pgp_key;
 */
@interface PMNOpenPgp : NSObject

/**
 * create and init an instance those instance have addresses manager build in
 * if want deal with single key should use the static functions
 */
+ (nullable PMNOpenPgp *)createInstance;

/** create and init an instance with addresses */
+ (nullable PMNOpenPgp *)createInstanceWithAddress:(nonnull PMNAddress *)address;

+ (nullable PMNOpenPgp *)createInstanceWithAddresses:(nonnull NSArray<PMNAddress *> *)address;

/**update single private key password */
+ (nonnull NSString *)updateSinglePassphrase:(nonnull NSString *)privateKey
                               oldPassphrase:(nonnull NSString *)oldPassphrase
                               newPassphrase:(nonnull NSString *)newPassphrase;

/**disable/enable debug model */
+ (void)enableDebug:(BOOL)isDebug;

/**check is private key passphrase ok */
+ (BOOL)checkPassphrase:(nonnull NSString *)privateKey
             passphrase:(nonnull NSString *)passphrase;

/**update multiple pgp private keys return are new keys */
+ (nonnull NSArray<PMNOpenPgpKey *> *)updateKeysPassphrase:(nonnull NSArray<PMNOpenPgpKey *> *)privateKeys
                                             oldPassphrase:(nonnull NSString *)oldPassphrase
                                             newPassphrase:(nonnull NSString *)newPassphrase;

/**decrypt message use the address key ring with password */
+ (nonnull NSString *)decryptMessageWithAddress:(nonnull PMNAddress *)address
                                    encryptText:(nonnull NSString *)encryptText
                                      passphras:(nonnull NSString *)passphras;

/**decrypt attachment use the address key ring with password */
+ (nonnull NSData *)decryptAttachmentWithAddress:(nonnull PMNAddress *)address
                                             key:(nonnull NSData *)key
                                            data:(nonnull NSData *)data
                                       passphras:(nonnull NSString *)passphras;

/**Random bits */
+ (nonnull NSData *)randomBits:(int32_t)bits;

/**add a new address into addresses list */
- (BOOL)addAddress:(nonnull PMNAddress *)address;

/**remove a exsit address from the list based on address id */
- (BOOL)removeAddress:(nonnull NSString *)addressId;

/**clean address list */
- (BOOL)cleanAddresses;

/**generat new key pair */
- (nonnull PMNOpenPgpKey *)generateKey:(nonnull NSString *)userName
                                domain:(nonnull NSString *)domain
                            passphrase:(nonnull NSString *)passphrase
                                  bits:(int32_t)bits
                                  time:(int32_t)time;

/**
 * old functions blow
 *update the information carried in the packet. //TODO need add more parameters
 */
- (void)updatePrivateInfo:(nonnull NSString *)privateKey;

/**encrypt message use address id */
- (nonnull NSString *)encryptMessage:(nonnull NSString *)addressId
                           plainText:(nonnull NSString *)plainText
                           passphras:(nonnull NSString *)passphras
                                trim:(BOOL)trim;

/**encrypt message use public key */
- (nonnull NSString *)encryptMessageSingleKey:(nonnull NSString *)publicKey
                                    plainText:(nonnull NSString *)plainText
                                   privateKey:(nonnull NSString *)privateKey
                                    passphras:(nonnull NSString *)passphras
                                         trim:(BOOL)trim;

- (nonnull NSString *)encryptMessageSingleBinaryPubKey:(nonnull NSData *)publicKey
                                             plainText:(nonnull NSString *)plainText
                                            privateKey:(nonnull NSString *)privateKey
                                             passphras:(nonnull NSString *)passphras
                                                  trim:(BOOL)trim;

- (nonnull NSString *)decryptMessage:(nonnull NSString *)encryptText
                           passphras:(nonnull NSString *)passphras;

- (nonnull NSString *)decryptMessageSingleKey:(nonnull NSString *)encryptText
                                   privateKey:(nonnull NSString *)privateKey
                                    passphras:(nonnull NSString *)passphras;

/**for signature */
- (nonnull PMNEncryptSignPackage *)encryptMessageSignExternal:(nonnull NSString *)publicKey
                                                   privateKey:(nonnull NSString *)privateKey
                                                    plainText:(nonnull NSString *)plainText
                                                    passphras:(nonnull NSString *)passphras;

- (nonnull PMNDecryptSignVerify *)decryptMessageVerifySingleKey:(nonnull NSString *)privateKey
                                                      passphras:(nonnull NSString *)passphras
                                                      encrypted:(nonnull NSString *)encrypted
                                                      signature:(nonnull NSString *)signature;

- (nonnull PMNDecryptSignVerify *)decryptMessageVerify:(nonnull NSString *)passphras
                                             encrypted:(nonnull NSString *)encrypted
                                             signature:(nonnull NSString *)signature;

- (nonnull NSString *)signDetached:(nonnull NSString *)privateKey
                         plainText:(nonnull NSString *)plainText
                         passphras:(nonnull NSString *)passphras;

- (BOOL)signDetachedVerifySinglePubKey:(nonnull NSString *)publicKey
                             signature:(nonnull NSString *)signature
                             plainText:(nonnull NSString *)plainText;

- (BOOL)signDetachedVerifySingleBinaryPubKey:(nonnull NSData *)publicKey
                                   signature:(nonnull NSString *)signature
                                   plainText:(nonnull NSString *)plainText;

- (BOOL)signDetachedVerifySinglePrivateKey:(nonnull NSString *)privateKey
                                 signature:(nonnull NSString *)signature
                                 plainText:(nonnull NSString *)plainText;

- (BOOL)signDetachedVerify:(nonnull NSString *)signature
                 plainText:(nonnull NSString *)plainText;

+ (BOOL)findKeyid:(nonnull NSString *)encryptText
       privateKey:(nonnull NSString *)privateKey;

- (nonnull PMNEncryptPackage *)encryptAttachment:(nonnull NSString *)addressId
                                   unencryptData:(nonnull NSData *)unencryptData
                                        fileName:(nonnull NSString *)fileName
                                       passphras:(nonnull NSString *)passphras;

- (nonnull PMNEncryptPackage *)encryptAttachmentSingleKey:(nonnull NSString *)publicKey
                                            unencryptData:(nonnull NSData *)unencryptData
                                                 fileName:(nonnull NSString *)fileName
                                               privateKey:(nonnull NSString *)privateKey
                                                passphras:(nonnull NSString *)passphras;

- (nonnull PMNEncryptPackage *)encryptAttachmentSingleBinaryKey:(nonnull NSData *)publicKey
                                                  unencryptData:(nonnull NSData *)unencryptData
                                                       fileName:(nonnull NSString *)fileName
                                                     privateKey:(nonnull NSString *)privateKey
                                                      passphras:(nonnull NSString *)passphras;

- (nonnull NSData *)decryptAttachment:(nonnull NSData *)key
                                 data:(nonnull NSData *)data
                            passphras:(nonnull NSString *)passphras;

- (nonnull NSData *)decryptAttachmentSingleKey:(nonnull NSData *)key
                                          data:(nonnull NSData *)data
                                    privateKey:(nonnull NSString *)privateKey
                                     passphras:(nonnull NSString *)passphras;

- (nonnull NSData *)decryptAttachmentWithPassword:(nonnull NSData *)key
                                             data:(nonnull NSData *)data
                                         password:(nonnull NSString *)password;

- (nonnull NSData *)getPublicKeySessionKey:(nonnull NSData *)keyPackage
                                passphrase:(nonnull NSString *)passphrase;

- (nonnull NSData *)getPublicKeySessionKeySingleKey:(nonnull NSData *)keyPackage
                                         privateKey:(nonnull NSString *)privateKey
                                         passphrase:(nonnull NSString *)passphrase;

- (nonnull NSData *)getSymmetricSessionKey:(nonnull NSData *)keyPackage
                                  password:(nonnull NSString *)password;

- (nonnull NSData *)getNewPublicKeyPackage:(nonnull NSData *)session
                                 publicKey:(nonnull NSString *)publicKey;

- (nonnull NSData *)getNewPublicKeyPackageBinary:(nonnull NSData *)session
                                       publicKey:(nonnull NSData *)publicKey;

- (nonnull NSData *)getNewSymmetricKeyPackage:(nonnull NSData *)session
                                     password:(nonnull NSString *)password;

- (nonnull NSString *)encryptMessageAes:(nonnull NSString *)plainText
                               password:(nonnull NSString *)password;

- (nonnull NSString *)decryptMessageAes:(nonnull NSString *)encryptedMessage
                               password:(nonnull NSString *)password;

- (nonnull NSString *)encryptMailboxPwd:(nonnull NSString *)unencryptedPwd
                                   salt:(nonnull NSString *)salt;

- (nonnull NSString *)decryptMailboxPwd:(nonnull NSString *)encryptedPwd
                                   salt:(nonnull NSString *)salt;

- (nonnull NSString *)readClearsignedMessage:(nonnull NSString *)signedMessage;

+ (nonnull PMNEncryptPackage *)splitMessage:(nonnull NSString *)encrypted;

+ (nonnull NSString *)combinePackages:(nonnull NSData *)key
                                 data:(nonnull NSData *)data;

/**test functions */
- (int32_t)throwAnException;

/**PBE */
- (nonnull NSString *)encryptHashCbc:(nonnull NSString *)plainText
                            password:(nonnull NSString *)password;

- (nonnull NSString *)decryptHashCbc:(nonnull NSString *)encryptedText
                            password:(nonnull NSString *)password;

@end
