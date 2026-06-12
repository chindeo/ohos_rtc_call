import rtcAdminEntryControllerTest from './RtcAdminEntryController.test'
import rtcAudioControllerTest from './RtcAudioController.test'
import rtcCallAudioPolicyControllerTest from './RtcCallAudioPolicyController.test'
import rtcCallSessionStoreTest from './RtcCallSessionStore.test'
import rtcDefaultCallServiceTest from './RtcDefaultCallService.test'
import rtcHardwareCallControllerTest from './RtcHardwareCallController.test'
import rtcHostMultiCallControllerTest from './RtcHostMultiCallController.test'
import rtcIncomingCallQueueTest from './RtcIncomingCallQueue.test'
import rtcNetworkRequestRecoveryControllerTest from './RtcNetworkRequestRecoveryController.test'
import rtcPeerSessionRegistryTest from './RtcPeerSessionRegistry.test'
import rtcRuntimeConfigControllerTest from './RtcRuntimeConfigController.test'
import rtcStartupFallbackControllerTest from './RtcStartupFallbackController.test'
import rtcStartupDataCacheTest from './RtcStartupDataCache.test'
import rtcWebRtcSignalStateMachineTest from './RtcWebRtcSignalStateMachine.test'
import rtcWebRtcMediaControllerTest from './RtcWebRtcMediaController.test'

export default function testsuite() {
  rtcAdminEntryControllerTest()
  rtcAudioControllerTest()
  rtcCallAudioPolicyControllerTest()
  rtcCallSessionStoreTest()
  rtcDefaultCallServiceTest()
  rtcHardwareCallControllerTest()
  rtcHostMultiCallControllerTest()
  rtcIncomingCallQueueTest()
  rtcNetworkRequestRecoveryControllerTest()
  rtcPeerSessionRegistryTest()
  rtcRuntimeConfigControllerTest()
  rtcStartupFallbackControllerTest()
  rtcStartupDataCacheTest()
  rtcWebRtcSignalStateMachineTest()
  rtcWebRtcMediaControllerTest()
}
