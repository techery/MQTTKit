//
//  MQTTKit.m
//  MQTTKit
//
//  Created by Jeff Mesnil on 22/10/2013.
//  Copyright (c) 2013 Jeff Mesnil. All rights reserved.
//  Copyright 2012 Nicholas Humfrey. All rights reserved.
//

#import "MQTTKit.h"
#import "MQTTCommand.h"
#import "GCDAsyncSocket.h"

#if 1 // set to 1 to enable logs

#define LogDebug(frmt, ...) NSLog(frmt, ##__VA_ARGS__);

#else

#define LogDebug(frmt, ...) {}

#endif

#define kDefaultTimeout 5

#pragma mark - MQTT Message

@interface MQTTMessage()

@property (readwrite, assign) unsigned short mid;
@property (readwrite, copy) NSString *topic;
@property (readwrite, copy) NSData *payload;
@property (readwrite, assign) MQTTQualityOfService qos;
@property (readwrite, assign) BOOL retained;

@end

@implementation MQTTMessage

-(id)initWithTopic:(NSString *)topic
           payload:(NSData *)payload
               qos:(MQTTQualityOfService)qos
            retain:(BOOL)retained
               mid:(short)mid
{
    if ((self = [super init])) {
        self.topic = topic;
        self.payload = payload;
        self.qos = qos;
        self.retained = retained;
        self.mid = mid;
    }
    return self;
}

- (NSString *)payloadString {
    return [[NSString alloc] initWithBytes:self.payload.bytes length:self.payload.length encoding:NSUTF8StringEncoding];
}

@end

#pragma mark - MQTT Client

@interface MQTTClient()

@property (nonatomic, retain) GCDAsyncSocket *socket;
@property (nonatomic, assign) BOOL connected;
@property (nonatomic, copy) void (^connectionCompletionHandler)(NSUInteger code);
@property (nonatomic, strong) NSMutableDictionary *subscriptionHandlers;
@property (nonatomic, strong) NSMutableDictionary *unsubscriptionHandlers;
// dictionary of mid -> completion handlers for messages published with a QoS of 1 or 2
@property (nonatomic, strong) NSMutableDictionary *publishHandlers;

- (void)send:(MQTTCommand *)command;

@end

@implementation MQTTClient

dispatch_queue_t queue;

#pragma mark - mosquitto callback methods

//static void on_connect(struct mosquitto *mosq, void *obj, int rc)
//{
//    MQTTClient* client = (__bridge MQTTClient*)obj;
//    LogDebug(@"on_connect rc = %d", rc);
//    client.connected = YES;
//    if (client.connectionCompletionHandler) {
//        client.connectionCompletionHandler(rc);
//    }
//}
//
//static void on_disconnect(struct mosquitto *mosq, void *obj, int rc)
//{
//    MQTTClient* client = (__bridge MQTTClient*)obj;
//    LogDebug(@"on_disconnect rc = %d", rc);
//    client.connected = NO;
//    if (client.disconnectionHandler) {
//        client.disconnectionHandler(rc);
//    }
//    [client.publishHandlers removeAllObjects];
//    [client.subscriptionHandlers removeAllObjects];
//    [client.unsubscriptionHandlers removeAllObjects];
//}
//
//static void on_publish(struct mosquitto *mosq, void *obj, int message_id)
//{
//    MQTTClient* client = (__bridge MQTTClient*)obj;
//    NSNumber *mid = [NSNumber numberWithInt:message_id];
//    void (^handler)(int) = [client.publishHandlers objectForKey:mid];
//    if (handler) {
//        handler(message_id);
//        if (message_id > 0) {
//            [client.publishHandlers removeObjectForKey:mid];
//        }
//    }
//}
//
//static void on_message(struct mosquitto *mosq, void *obj, const struct mosquitto_message *mosq_msg)
//{
//    NSString *topic = [NSString stringWithUTF8String: mosq_msg->topic];
//    NSData *payload = [NSData dataWithBytes:mosq_msg->payload length:mosq_msg->payloadlen];
//    MQTTMessage *message = [[MQTTMessage alloc] initWithTopic:topic
//                                                      payload:payload
//                                                          qos:mosq_msg->qos
//                                                       retain:mosq_msg->retain
//                                                          mid:mosq_msg->mid];
//    LogDebug(@"on message %@", message);
//    MQTTClient* client = (__bridge MQTTClient*)obj;
//    if (client.messageHandler) {
//        client.messageHandler(message);
//    }
//}
//
//static void on_subscribe(struct mosquitto *mosq, void *obj, int message_id, int qos_count, const int *granted_qos)
//{
//    MQTTClient* client = (__bridge MQTTClient*)obj;
//    NSNumber *mid = [NSNumber numberWithInt:message_id];
//    MQTTSubscriptionCompletionHandler handler = [client.subscriptionHandlers objectForKey:mid];
//    if (handler) {
//        NSMutableArray *grantedQos = [NSMutableArray arrayWithCapacity:qos_count];
//        for (int i = 0; i < qos_count; i++) {
//            [grantedQos addObject:[NSNumber numberWithInt:granted_qos[i]]];
//        }
//        handler(grantedQos);
//        [client.subscriptionHandlers removeObjectForKey:mid];
//    }
//}
//
//static void on_unsubscribe(struct mosquitto *mosq, void *obj, int message_id)
//{
//    MQTTClient* client = (__bridge MQTTClient*)obj;
//    NSNumber *mid = [NSNumber numberWithInt:message_id];
//    void (^completionHandler)(void) = [client.unsubscriptionHandlers objectForKey:mid];
//    if (completionHandler) {
//        completionHandler();
//        [client.subscriptionHandlers removeObjectForKey:mid];
//    }
//}

- (MQTTClient*) initWithClientId: (NSString*) clientId {
    if ((self = [super init])) {
        self.clientID = clientId;
        self.port = 1883;
        self.keepAlive = 60;
        self.cleanSession = YES;  //NOTE: this isdisable clean to keep the broker remember this client
        self.reconnectDelay = 1;
        self.reconnectDelayMax = 1;
        self.reconnectExponentialBackoff = NO;

        self.connected = NO;
        self.subscriptionHandlers = [[NSMutableDictionary alloc] init];
        self.unsubscriptionHandlers = [[NSMutableDictionary alloc] init];
        self.publishHandlers = [[NSMutableDictionary alloc] init];

        const char* cstrClientId = [self.clientID cStringUsingEncoding:NSUTF8StringEncoding];
        queue = dispatch_queue_create(cstrClientId, NULL);
        
        self.socket = [[GCDAsyncSocket alloc] initWithDelegate:self
                                                 delegateQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)];
    }
    return self;
}

- (void) setMessageRetry: (NSUInteger)seconds
{
    //
}

#pragma mark - Connection

- (void) connectWithCompletionHandler:(void (^)(MQTTConnectionReturnCode code))completionHandler {
    self.connectionCompletionHandler = completionHandler;

    NSError *err;
    if(![self.socket connectToHost:self.host onPort:self.port error:&err]) {
        if (self.connectionCompletionHandler) {
            self.connectionCompletionHandler([err code]);
        }
    }

//    mosquitto_reconnect_delay_set(mosq, self.reconnectDelay, self.reconnectDelayMax, self.reconnectExponentialBackoff);

    
    LogDebug(@"create CONNECT message");
    MQTTCommand *connect = [MQTTCommand connectMessageWithClientID:self.clientID
                                                          userName:self.username
                                                          password:self.password
                                                         keepAlive:self.keepAlive
                                                      cleanSession:self.cleanSession
                                                       willMessage:nil
                                                           willQoS:AtMostOnce];
    [self send:connect];
        //
//    mosquitto_connect(mosq, cstrHost, self.port, self.keepAlive);
//    
//    dispatch_async(queue, ^{
//        LogDebug(@"start mosquitto loop");
//        mosquitto_loop_forever(mosq, 10, 1);
//        LogDebug(@"end mosquitto loop");
//    });
}

- (void)connectToHost:(NSString *)host
    completionHandler:(void (^)(MQTTConnectionReturnCode code))completionHandler {
    self.host = host;
    [self connectWithCompletionHandler:completionHandler];
}

- (void) reconnect {
//    mosquitto_reconnect(mosq);
}

- (void) disconnectWithCompletionHandler:(MQTTDisconnectionHandler)completionHandler {
    LogDebug(@"create DISCONNECT message");
    [self send:[MQTTCommand disconnect]];

    [self.socket disconnectAfterWriting];

    if (completionHandler) {
        completionHandler(0);
    }
//    mosquitto_disconnect(mosq);
}

- (void)setWillData:(NSData *)payload
            toTopic:(NSString *)willTopic
            withQos:(MQTTQualityOfService)willQos
             retain:(BOOL)retain
{
    const char* cstrTopic = [willTopic cStringUsingEncoding:NSUTF8StringEncoding];
//    mosquitto_will_set(mosq, cstrTopic, payload.length, payload.bytes, willQos, retain);
}

- (void)setWill:(NSString *)payload
        toTopic:(NSString *)willTopic
        withQos:(MQTTQualityOfService)willQos
         retain:(BOOL)retain;
{
    [self setWillData:[payload dataUsingEncoding:NSUTF8StringEncoding]
              toTopic:willTopic
              withQos:willQos
               retain:retain];
}

- (void)clearWill
{
//    mosquitto_will_clear(mosq);
}

#pragma mark - Publish

- (void)publishData:(NSData *)payload
            toTopic:(NSString *)topic
            withQos:(MQTTQualityOfService)qos
             retain:(BOOL)retain
  completionHandler:(void (^)(int mid))completionHandler {
    const char* cstrTopic = [topic cStringUsingEncoding:NSUTF8StringEncoding];
    if (qos == 0 && completionHandler) {
        [self.publishHandlers setObject:completionHandler forKey:[NSNumber numberWithInt:0]];
    }
    int mid = -1;
//    mosquitto_publish(mosq, &mid, cstrTopic, payload.length, payload.bytes, qos, retain);
    if (completionHandler) {
        if (qos == 0) {
            completionHandler(mid);
        } else {
            [self.publishHandlers setObject:completionHandler forKey:[NSNumber numberWithInt:mid]];
        }
    }
}

- (void)publishString:(NSString *)payload
              toTopic:(NSString *)topic
              withQos:(MQTTQualityOfService)qos
               retain:(BOOL)retain
    completionHandler:(void (^)(int mid))completionHandler; {
    [self publishData:[payload dataUsingEncoding:NSUTF8StringEncoding]
              toTopic:topic
              withQos:qos
               retain:retain
    completionHandler:completionHandler];
}

#pragma mark - Subscribe

- (void)subscribe: (NSString *)topic withCompletionHandler:(MQTTSubscriptionCompletionHandler)completionHandler {
    [self subscribe:topic withQos:0 completionHandler:completionHandler];
}

- (void)subscribe: (NSString *)topic withQos:(MQTTQualityOfService)qos completionHandler:(MQTTSubscriptionCompletionHandler)completionHandler
{
    const char* cstrTopic = [topic cStringUsingEncoding:NSUTF8StringEncoding];
    int mid = -1;
//    mosquitto_subscribe(mosq, &mid, cstrTopic, qos);
    if (completionHandler) {
        [self.subscriptionHandlers setObject:[completionHandler copy] forKey:[NSNumber numberWithInteger:mid]];
    }
}

- (void)unsubscribe: (NSString *)topic withCompletionHandler:(void (^)(void))completionHandler
{
    const char* cstrTopic = [topic cStringUsingEncoding:NSUTF8StringEncoding];
    int mid = -1;
//    mosquitto_unsubscribe(mosq, &mid, cstrTopic);
    if (completionHandler) {
        [self.unsubscriptionHandlers setObject:[completionHandler copy] forKey:[NSNumber numberWithInteger:mid]];
    }
}

- (void)handleCommand:(MQTTCommand *)command {
    switch (command.type) {
        case MQTTConnack: {
            UInt8 code[1];
            [command.data getBytes:&code range:NSMakeRange(1, 1)];
            if (self.connectionCompletionHandler) {
                self.connectionCompletionHandler(code[0]);
            }
            break;
        }
        default:
            NSLog(@"unhandled type: %i", command.type);
            break;
    }
}

- (void)readFrame {
	[[self socket] readDataToData:[GCDAsyncSocket ZeroData] withTimeout:-1 tag:0];
}

#pragma mark - GCDAsyncSocketDelegate

- (void)socket:(GCDAsyncSocket *)sock
   didReadData:(NSData *)data
       withTag:(long)tag {
    UInt8 header[1];
    [data getBytes:&header length:1];

    UInt8 type = (header[0] >> 4) & 0x0f;
    BOOL duplicated = ((header[0] & 0x08) == 0x08);
    // XXX qos > 2
    UInt8 qos = (header[0] >> 1) & 0x03;
    BOOL retained = ((header[0] & 0x01) == 0x01);

    /*
     multiplier = 1
     value = 0
     do
     digit = 'next digit from stream'
     value += (digit AND 127) * multiplier
     multiplier *= 128
     while ((digit AND 128) != 0)
     */

    int n = 0;
    int length = 0;
    int lengthMultiplier = 1;
    UInt8 digit[1];
    
    do {
        n++;
        [data getBytes:&digit range:NSMakeRange(n, 1)];
        length += (digit[0] & 127) * lengthMultiplier;
        lengthMultiplier *= 128;
    } while ((digit[0] & 128) != 0);
    
    NSLog(@"length = %i", length);
    MQTTCommand *command = [[MQTTCommand alloc] initWithType:type dupFlag:duplicated qos:qos retainFlag:retained];
    if (length > 0) {
        command.data = [data subdataWithRange:NSMakeRange(n, length)];
    }
    [self handleCommand:command];
    NSLog(@"command = %@", command);
}

- (void)socket:(GCDAsyncSocket *)sock didReadPartialDataOfLength:(NSUInteger)partialLength tag:(long)tag {
    LogDebug(@"didReadPartialDataOfLength");
}

- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port {
    LogDebug(@"didConnectToHost %@:%d", host, port);
    [self readFrame];
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock
                  withError:(NSError *)err {
    LogDebug(@"socket did disconnect %@", err);
    if (!self.connected && self.connectionCompletionHandler) {
        self.connectionCompletionHandler(ConnectionRefusedServerUnavailable);
    } else if (self.connected) {
        if (self.disconnectionHandler) {
            self.disconnectionHandler(err.code);
        }
    }
    
    self.connected = NO;
}
    
#pragma mark - Private Methods
    
- (void)send:(MQTTCommand *)command {
    NSLog(@"command=%@", command);
    if ([self.socket isDisconnected]) {
        NSLog(@"nothing");
        return;
    }
    
    NSMutableData *buffer = [[NSMutableData alloc] init] ;
    // encode fixed header
    UInt8 header = command.type << 4;
    if (command.dupFlag) {
        header |= 0x08;
    }
    header |= command.qos << 1;
    if (command.retainFlag) {
        header |= 0x01;
    }
    [buffer appendBytes:&header length:1];
    
    // encode remaining length
    NSUInteger length = command.data.length;
    do {
        UInt8 digit = length % 128;
        length /= 128;
        if (length > 0) {
            digit |= 0x80;
        }
        [buffer appendBytes:&digit length:1];
    }
    while (length > 0);
    
    // encode message data
    if (command.data) {
        [buffer appendData:command.data];
    }
    
    [self.socket writeData:buffer withTimeout:kDefaultTimeout tag:123];
}


@end
