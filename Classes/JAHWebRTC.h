//
//  JAHWebRTC.h
//  
//
//  Created by Jon Hjelle on 1/20/14.
//  Copyright (c) 2014 Jon Hjelle. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "RTCSessionDescription.h"
#import "RTCICECandidate.h"
#import "RTCMediaStream.h"

@protocol JAHSignalDelegate;

@interface JAHWebRTC : NSObject

@property (nonatomic, weak) id <JAHSignalDelegate> signalDelegate;

- (void)addPeerConnectionForID:(NSString*)identifier;
- (void)removePeerConnectionForID:(NSString*)identifier;

- (void)createOfferForPeerWithID:(NSString*)peerID;
- (void)setRemoteDescription:(RTCSessionDescription*)remoteSDP forPeerWithID:(NSString*)peerID receiver:(BOOL)isReceiver;
- (void)addICECandidate:(RTCICECandidate*)candidate forPeerWithID:(NSString*)peerID;

@end


@protocol JAHSignalDelegate <NSObject>

- (void)sendSDPOffer:(RTCSessionDescription*)offer forPeerWithID:(NSString*)peerID;
- (void)sendSDPAnswer:(RTCSessionDescription*)answer forPeerWithID:(NSString*)peerID;
- (void)sendICECandidate:(RTCICECandidate*)candidate forPeerWithID:(NSString*)peerID;

- (void)addedStream:(RTCMediaStream*)stream;
- (void)removedStream:(RTCMediaStream*)stream;

@end