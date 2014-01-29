//
//  JAHWebRTC.m
//
//
//  Created by Jon Hjelle on 1/20/14.
//  Copyright (c) 2014 Jon Hjelle. All rights reserved.
//

#import "JAHWebRTC.h"

#import <AVFoundation/AVFoundation.h>

#import "RTCPeerConnectionFactory.h"
#import "RTCPeerConnection.h"
#import "RTCICEServer.h"
#import "RTCPair.h"
#import "RTCMediaConstraints.h"
#import "RTCSessionDescriptonDelegate.h"
#import "RTCPeerConnectionDelegate.h"

#import "RTCAudioTrack.h"
#import "RTCVideoCapturer.h"
#import "RTCVideoSource.h"
#import "RTCVideoTrack.h"

@interface JAHWebRTC () <RTCSessionDescriptonDelegate, RTCPeerConnectionDelegate>
@property (nonatomic, strong) RTCPeerConnectionFactory* peerFactory;
@property (nonatomic, strong) NSMutableDictionary* peerConnections;
@property (nonatomic, strong) NSMutableDictionary* peerToRoleMap;
@property (nonatomic, strong) NSMutableDictionary* peerToICEMap;
@end

NSString* const JAHPeerConnectionRoleInitiator = @"JAHPeerConnectionRoleInitiator";
NSString* const JAHPeerConnectionRoleReceiver = @"JAHPeerConnectionRoleReceiver";

@implementation JAHWebRTC

- (id)init {
	self = [super init];
	if (self) {
        _peerFactory = [[RTCPeerConnectionFactory alloc] init];
        _peerConnections = [NSMutableDictionary dictionary];
        _peerToRoleMap = [NSMutableDictionary dictionary];
        _peerToICEMap = [NSMutableDictionary dictionary];

        [RTCPeerConnectionFactory initializeSSL];
	}
	return self;
}

#pragma mark - Add/remove peerConnections

- (void)addPeerConnectionForID:(NSString*)identifier {
	RTCPeerConnection* peer = [self.peerFactory peerConnectionWithICEServers:[self iceServers] constraints:[self mediaConstraints] delegate:self];
    [peer addStream:[self localStream] constraints:[self mediaConstraints]];

	[self.peerConnections setObject:peer forKey:identifier];
}

- (void)removePeerConnectionForID:(NSString*)identifier {
	[self.peerConnections removeObjectForKey:identifier];
    [self.peerToRoleMap removeObjectForKey:identifier];
}

#pragma mark -

- (void)createOfferForPeerWithID:(NSString*)peerID {
    RTCPeerConnection* peerConnection = [self.peerConnections objectForKey:peerID];
    [self.peerToRoleMap setObject:JAHPeerConnectionRoleInitiator forKey:peerID];
    [peerConnection createOfferWithDelegate:self constraints:[self mediaConstraints]];
}

- (void)setRemoteDescription:(RTCSessionDescription*)remoteSDP forPeerWithID:(NSString*)peerID receiver:(BOOL)isReceiver {
    RTCPeerConnection* peerConnection = [self.peerConnections objectForKey:peerID];
    if (isReceiver) {
        [self.peerToRoleMap setObject:JAHPeerConnectionRoleReceiver forKey:peerID];
    }
    [peerConnection setRemoteDescriptionWithDelegate:self sessionDescription:remoteSDP];
}

- (void)addICECandidate:(RTCICECandidate*)candidate forPeerWithID:(NSString*)peerID {
    RTCPeerConnection* peerConnection = [self.peerConnections objectForKey:peerID];
    if (peerConnection.iceGatheringState == RTCICEGatheringNew) {
        // Queue ICE candidates until both the local and remote description are set
        // When both are set, the ICE gathering state will be RTCICEGatheringGathering
        NSMutableArray* candidates = [self.peerToICEMap objectForKey:peerID];
        if (!candidates) {
            candidates = [NSMutableArray array];
            [self.peerToICEMap setObject:candidates forKey:peerID];
        }
        [candidates addObject:candidate];
    } else {
        [peerConnection addICECandidate:candidate];
    }
}

#pragma mark - RTCSessionDescriptionDelegate method

- (void)peerConnection:(RTCPeerConnection*)peerConnection didCreateSessionDescription:(RTCSessionDescription*)sdp error:(NSError*)error {
    [peerConnection setLocalDescriptionWithDelegate:self sessionDescription:sdp];
}

- (void)peerConnection:(RTCPeerConnection*)peerConnection didSetSessionDescriptionWithError:(NSError*)error {
    [self logPeerState:peerConnection];

    if (peerConnection.iceGatheringState == RTCICEGatheringGathering) {
        NSArray* keys = [self.peerConnections allKeysForObject:peerConnection];
        if ([keys count] > 0) {
            NSArray* candidates = [self.peerToICEMap objectForKey:keys[0]];
            for (RTCICECandidate* candidate in candidates) {
                [peerConnection addICECandidate:candidate];
            }
            [self.peerToICEMap removeObjectForKey:keys[0]];
        }
    }

    if (peerConnection.signalingState == RTCSignalingHaveLocalOffer) {
        NSArray* keys = [self.peerConnections allKeysForObject:peerConnection];
        if ([keys count] > 0) {
            [self.signalDelegate sendSDPOffer:peerConnection.localDescription forPeerWithID:keys[0]];
        }
    } else if (peerConnection.signalingState == RTCSignalingHaveRemoteOffer) {
        [peerConnection createAnswerWithDelegate:self constraints:[self mediaConstraints]];
    } else if (peerConnection.signalingState == RTCSignalingStable) {
        NSArray* keys = [self.peerConnections allKeysForObject:peerConnection];
        if ([keys count] > 0) {
            NSString* role = [self.peerToRoleMap objectForKey:keys[0]];
            if (role == JAHPeerConnectionRoleReceiver) {
                [self.signalDelegate sendSDPAnswer:peerConnection.localDescription forPeerWithID:keys[0]];
            }
        }
    }
}

#pragma mark - RTCPeerConnectionDelegate methods

- (void)peerConnectionOnError:(RTCPeerConnection *)peerConnection {
    NSLog(@"peerConnectionOnError:");
}

- (NSString*)stringForSignalingState:(RTCSignalingState)state {
    switch (state) {
        case RTCSignalingStable:
            return @"Stable";
            break;
        case RTCSignalingHaveLocalOffer:
            return @"Have Local Offer";
            break;
        case RTCSignalingHaveRemoteOffer:
            return @"Have Remote Offer";
            break;
        case RTCSignalingClosed:
            return @"Closed";
            break;
        default:
            return @"Other state";
            break;
    }
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection signalingStateChanged:(RTCSignalingState)stateChanged {
    NSLog(@"peerConnection:signalingStateChanged: state-> %@", [self stringForSignalingState:stateChanged]);
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection addedStream:(RTCMediaStream *)stream {
    NSLog(@"peerConnection:addedStream:");

    [self.signalDelegate addedStream:stream];
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection removedStream:(RTCMediaStream *)stream {
    NSLog(@"peerConnection:removedStream:");

    [self.signalDelegate removedStream:stream];
}

- (void)peerConnectionOnRenegotiationNeeded:(RTCPeerConnection *)peerConnection {
    NSLog(@"peerConnectionOnRenegotiationNeeded:");
}

- (NSString*)stringForConnectionState:(RTCICEConnectionState)state {
    switch (state) {
        case RTCICEConnectionNew:
            return @"New";
            break;
        case RTCICEConnectionChecking:
            return @"Checking";
            break;
        case RTCICEConnectionConnected:
            return @"Connected";
            break;
        case RTCICEConnectionCompleted:
            return @"Completed";
            break;
        case RTCICEConnectionFailed:
            return @"Failed";
            break;
        case RTCICEConnectionDisconnected:
            return @"Disconnected";
            break;
        case RTCICEConnectionClosed:
            return @"Closed";
            break;
        default:
            return @"Other state";
            break;
    }
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection iceConnectionChanged:(RTCICEConnectionState)newState {
    NSLog(@"peerConnection:iceConnectionChanged: state-> %@", [self stringForConnectionState:newState]);
}

- (NSString*)stringForGatheringState:(RTCICEGatheringState)state {
    switch (state) {
        case RTCICEGatheringNew:
            return @"New";
            break;
        case RTCICEGatheringGathering:
            return @"Gathering";
            break;
        case RTCICEGatheringComplete:
            return @"Complete";
            break;
        default:
            return @"Other state";
            break;
    }
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection iceGatheringChanged:(RTCICEGatheringState)newState {
    NSLog(@"peerConnection:iceGatheringChanged: state-> %@", [self stringForGatheringState:newState]);
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection gotICECandidate:(RTCICECandidate *)candidate {
    NSArray* keys = [self.peerConnections allKeysForObject:peerConnection];
    if ([keys count] > 0) {
        [self.signalDelegate sendICECandidate:candidate forPeerWithID:keys[0]];
    }
}

#pragma mark -

- (NSArray*)iceServers {
    RTCICEServer* stunServer = [[RTCICEServer alloc] initWithURI:[NSURL URLWithString:@"stun:stun.l.google.com:19302"] username:@"" password:@""];
    return @[stunServer];
}

- (RTCMediaConstraints*)mediaConstraints {
    RTCPair* audioConstraint = [[RTCPair alloc] initWithKey:@"OfferToReceiveAudio" value:@"true"];
    RTCPair* videoConstraint = [[RTCPair alloc] initWithKey:@"OfferToReceiveVideo" value:@"true"];
    RTCPair* sctpConstraint = [[RTCPair alloc] initWithKey:@"internalSctpDataChannels" value:@"true"];
    RTCPair* dtlsConstraint = [[RTCPair alloc] initWithKey:@"DtlsSrtpKeyAgreement" value:@"true"];

    return [[RTCMediaConstraints alloc] initWithMandatoryConstraints:@[audioConstraint, videoConstraint] optionalConstraints:@[sctpConstraint, dtlsConstraint]];
}

- (RTCMediaStream*)localStream {
    RTCMediaStream* stream = [self.peerFactory mediaStreamWithLabel:@"localStream"];

    RTCAudioTrack* audioTrack = [self.peerFactory audioTrackWithID:@"localAudio"];
    [stream addAudioTrack:audioTrack];

    //    AVCaptureDevice* device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    AVCaptureDevice* device = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo][1];
    RTCVideoCapturer* capturer = [RTCVideoCapturer capturerWithDeviceName:[device localizedName]];
    RTCVideoSource *videoSource = [self.peerFactory videoSourceWithCapturer:capturer constraints:nil];
    RTCVideoTrack* videoTrack = [self.peerFactory videoTrackWithID:@"localVideo" source:videoSource];
    [stream addVideoTrack:videoTrack];

    return stream;
}

@end
