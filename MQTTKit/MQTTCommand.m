//
//  MQTTCommand.m
//  MQTTKit
//
//  Created by Jeff Mesnil on 21/03/2014.
//  Copyright (c) 2014 Jeff Mesnil. All rights reserved.
//

#import "MQTTCommand.h"

@interface MQTTCommand ()

+ (void)appendTo:(NSMutableData *)data byte:(UInt8)byte;
+ (void)appendTo:(NSMutableData *)data uint16BigEndian:(UInt16)val;
+ (void)appendTo:(NSMutableData *) data string:(NSString*)str;

@end

@implementation MQTTCommand

- (MQTTCommand *)initWithType: (MQTTCommandType )type
                      dupFlag: (BOOL)dupFlag
                          qos: (UInt8)qos
                   retainFlag: (BOOL)retainFlag {
    if ((self = [super init])) {
        self.type = type;
        self.dupFlag = dupFlag;
        self.qos = qos;
        self.retainFlag = retainFlag;
    }
    return self;
}
- (MQTTCommand *)initWithType:(MQTTCommandType )type
                       NSData:(NSData *)data {
    if ((self = [super init])) {
        self.type = type;
        self.data = data;
    }
    return self;
}

+ (MQTTCommand *)connectMessageWithClientID:(NSString *)clientID
                        userName:(NSString *)userName
                        password:(NSString *)password
                       keepAlive:(NSInteger)keepAlive
                    cleanSession:(BOOL)cleanSessionFlag
                     willMessage:(MQTTMessage *)willMessage
                         willQoS:(UInt8)willQoS;

{
    UInt8 flags = 0x04;

    if (willMessage) {
        flags |= (willQoS << 4 & 0x18);
        if (willMessage.retained) {
            flags |= 0x20;
        }
    }

    if (cleanSessionFlag) {
        flags |= 0x02;
    }
    if ([userName length] > 0) {
        flags |= 0x80;
        if ([password length] > 0) {
            flags |= 0x40;
        }
    }
    
    NSMutableData* data = [NSMutableData data];
    [MQTTCommand appendTo:data string:@"MQIsdp"];
    [MQTTCommand appendTo:data byte:3];
    [MQTTCommand appendTo:data byte:flags];
    [MQTTCommand appendTo:data uint16BigEndian:keepAlive];
    
    [MQTTCommand appendTo:data string:clientID];
    if (willMessage) {
        [MQTTCommand appendTo:data string:willMessage.topic];
        [MQTTCommand appendTo:data uint16BigEndian:willMessage.payload.length];
        [data appendData:willMessage.payload];
    }
    if (userName.length > 0) {
        [MQTTCommand appendTo:data string:userName];
        if (password.length > 0) {
            [MQTTCommand appendTo:data string:password];
        }
    }
    
    MQTTCommand *command = [[MQTTCommand alloc] initWithType:MQTTConnect
                                                      NSData:data];
    return command;
}

+ (MQTTCommand *)disconnect {
    return [[MQTTCommand alloc] initWithType:MQTTDisconnect NSData:nil];
}

+ (void)appendTo:(NSMutableData *)data byte:(UInt8)byte {
    [data appendBytes:&byte length:1];
}

+ (void)appendTo:(NSMutableData *)data uint16BigEndian:(UInt16)val {
    [MQTTCommand appendTo:data byte:val / 256];
    [MQTTCommand appendTo:data byte:val % 256];
}

+ (void)appendTo:(NSMutableData *)data string:(NSString*)str {
    UInt8 buf[2];
    const char* utf8String = [str UTF8String];
    int strLen = strlen(utf8String);
    buf[0] = strLen / 256;
    buf[1] = strLen % 256;
    [data appendBytes:buf length:2];
    [data appendBytes:utf8String length:strLen];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"MQTTCommand<type=%i, duplicated=%i, qos=%i, retained=%i, data.length=%lu",
            self.type,
            self.dupFlag,
            self.qos,
            self.retainFlag,
            self.data.length];
}
@end
