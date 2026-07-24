import rtcAdminEntryControllerTest from './RtcAdminEntryController.test'
import rtcAudioControllerTest from './RtcAudioController.test'
import rtcCallAudioPolicyControllerTest from './RtcCallAudioPolicyController.test'
import rtcCallGatewayClientTest from './RtcCallGatewayClient.test'
import rtcCallLifecycleStoreTest from './RtcCallLifecycleStore.test'
import rtcCallSessionStoreTest from './RtcCallSessionStore.test'
import rtcCallUiPresenterTest from './RtcCallUiPresenter.test'
import rtcDefaultCallServiceTest from './RtcDefaultCallService.test'
import rtcDeviceCapabilityManagerTest from './RtcDeviceCapabilityManager.test'
import rtcHardwareCallControllerTest from './RtcHardwareCallController.test'
import rtcHostCallControllerTest from './RtcHostCallController.test'
import rtcHostMultiCallControllerTest from './RtcHostMultiCallController.test'
import rtcIncomingCallQueueTest from './RtcIncomingCallQueue.test'
import rtcNetworkRequestRecoveryControllerTest from './RtcNetworkRequestRecoveryController.test'
import rtcPeerSessionRegistryTest from './RtcPeerSessionRegistry.test'
import rtcRuntimeConfigControllerTest from './RtcRuntimeConfigController.test'
import rtcStartupFallbackControllerTest from './RtcStartupFallbackController.test'
import rtcStartupDataCacheTest from './RtcStartupDataCache.test'
import rtcWebRtcCallControllerTest from './RtcWebRtcCallController.test'
import rtcWebRtcReconnectPolicyTest from './RtcWebRtcReconnectPolicy.test'
import rtcWebRtcSignalSessionTest from './RtcWebRtcSignalSession.test'
import rtcWebRtcSignalStateMachineTest from './RtcWebRtcSignalStateMachine.test'
import rtcWebRtcMediaControllerTest from './RtcWebRtcMediaController.test'
import rtcVideoRenderControllerTest from './RtcVideoRenderController.test'

export default function testsuite() {
  rtcAdminEntryControllerTest()
  rtcAudioControllerTest()
  rtcCallAudioPolicyControllerTest()
  rtcCallGatewayClientTest()
  rtcCallLifecycleStoreTest()
  rtcCallSessionStoreTest()
  rtcCallUiPresenterTest()
  rtcDefaultCallServiceTest()
  rtcDeviceCapabilityManagerTest()
  rtcHardwareCallControllerTest()
  rtcHostCallControllerTest()
  rtcHostMultiCallControllerTest()
  rtcIncomingCallQueueTest()
  rtcNetworkRequestRecoveryControllerTest()
  rtcPeerSessionRegistryTest()
  rtcRuntimeConfigControllerTest()
  rtcStartupFallbackControllerTest()
  rtcStartupDataCacheTest()
  rtcWebRtcCallControllerTest()
  rtcWebRtcReconnectPolicyTest()
  rtcWebRtcSignalSessionTest()
  rtcWebRtcSignalStateMachineTest()
  rtcWebRtcMediaControllerTest()
  rtcVideoRenderControllerTest()
}
