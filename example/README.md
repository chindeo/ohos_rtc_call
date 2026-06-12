# Examples

This directory contains small integration examples for `@chindeo/ohos-rtc-call`.

The examples intentionally use placeholder signaling addresses, device numbers, and adapter implementations. Inject real deployment configuration from the host application and do not hard-code credentials, bundle names, hospital identifiers, or vendor SDK details in this package.

## Basic Call Setup

`basic-call-setup.ets` demonstrates:

- routing `ws://` and `wss://` register addresses to WebRTC;
- routing plain `ip:port` register addresses to SIP;
- creating a WebRTC signaling session;
- guarding ringtone playback so SIP and WebRTC channels do not overlap.

Copy the relevant code into an OpenHarmony app module and replace the placeholder values with runtime configuration from your own settings store.

## call-gateway Basic

`call-gateway-basic.ets` demonstrates:

- creating `RtcCallGatewayClient` with host-provided call-gateway and WebRTC adapters;
- opening a multi-call session by call-gateway `uid`;
- routing inbound SDP with `uid`, `rtcUID`, and `channelType`;
- keeping deployment-specific gateway transport code outside the shared package.

Use this as a compile-time integration skeleton. Real projects must replace the placeholder adapter methods with the business call-gateway SDK or bridge implementation.
