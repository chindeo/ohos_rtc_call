# Examples

This directory contains small integration examples for `@chindeo/ohos-rtc-call`.

The examples intentionally use placeholder signaling addresses, device numbers, and adapter implementations. Inject real deployment configuration from the host application and do not hard-code credentials, bundle names, hospital identifiers, or vendor SDK details in this package.

## Basic Call Setup

`basic-call-setup.ets` demonstrates:

- resolving a `ws://` or `wss://` register address into a WebRTC route, and rejecting anything else
  with the reason carried on the resolved address;
- creating a WebRTC signaling session;
- guarding ringtone playback through the controller policy.

Copy the relevant code into an OpenHarmony app module and replace the placeholder values with runtime configuration from your own settings store.

## call-gateway Basic

Moved out with the gateway client: see `call-gateway/client-ohos/example/call-gateway-basic.ets`.
