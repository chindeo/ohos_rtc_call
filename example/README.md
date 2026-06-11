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
