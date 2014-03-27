//
//  MQTTCommand.h
//  MQTTKit
//
//  Created by Jeff Mesnil on 21/03/2014.
//  Copyright (c) 2014 Jeff Mesnil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MQTTKit.h"

typedef enum MQTTCommandType : UInt8 {
    MQTTConnect = 1,
    MQTTConnack = 2,
    MQTTPublish = 3,
    MQTTPuback = 4,
    MQTTPubrec = 5,
    MQTTPubrel = 6,
    MQTTPubcomp = 7,
    MQTTSubscribe = 8,
    MQTTSuback = 9,
    MQTTUnsubscribe = 10,
    MQTTUnsuback = 11,
    MQTTPingreq = 12,
    MQTTPingresp = 13,
    MQTTDisconnect = 14
} MQTTCommandType;

@interface MQTTCommand : NSObject

@property (readwrite, assign) MQTTCommandType type;
@property (readwrite, assign) BOOL dupFlag;
@property (readwrite, assign) UInt8 qos;
@property (readwrite, assign) BOOL retainFlag;
@property (readwrite, copy) NSData *data;

- (MQTTCommand *)initWithType:(MQTTCommandType )type
                      dupFlag:(BOOL)dupFlag
                          qos:(UInt8)qoS
                   retainFlag:(BOOL)retainFlag;
- (MQTTCommand *)initWithType:(MQTTCommandType )type
                       NSData:(NSData *)data;

+ (MQTTCommand *)connectMessageWithClientID:(NSString *)clientID
                        userName:(NSString *)userName
                        password:(NSString *)password
                       keepAlive:(NSInteger)keepAlive
                    cleanSession:(BOOL)cleanSessionFlag
                     willMessage:(MQTTMessage *)willMessage
                         willQoS:(UInt8)willQoS;
+ (MQTTCommand *)disconnect;

@end
