import rtcAdminEntryControllerTest from './RtcAdminEntryController.test'
import rtcAppVersionTest from './RtcAppVersion.test'
import rtcAudioControllerTest from './RtcAudioController.test'
import rtcBroadcastHistoryTest from './RtcBroadcastHistory.test'
import rtcCallAudioPolicyControllerTest from './RtcCallAudioPolicyController.test'
import rtcCallLifecycleStoreTest from './RtcCallLifecycleStore.test'
import rtcCallSessionStoreTest from './RtcCallSessionStore.test'
import rtcCallSettingControllerTest from './RtcCallSettingController.test'
import rtcCallSettingPolicyTest from './RtcCallSettingPolicy.test'
import rtcCallUiPresenterTest from './RtcCallUiPresenter.test'
import rtcDefaultCallServiceTest from './RtcDefaultCallService.test'
import rtcHostCallControllerTest from './RtcHostCallController.test'
import rtcHostMultiCallControllerTest from './RtcHostMultiCallController.test'
import rtcIncomingCallQueueTest from './RtcIncomingCallQueue.test'
import rtcNetworkRequestRecoveryControllerTest from './RtcNetworkRequestRecoveryController.test'
import rtcPeerSessionRegistryTest from './RtcPeerSessionRegistry.test'
import rtcRingtoneControllerTest from './RtcRingtoneController.test'
import rtcRuntimeConfigControllerTest from './RtcRuntimeConfigController.test'
import rtcStartupFallbackControllerTest from './RtcStartupFallbackController.test'
import rtcStartupDataCacheTest from './RtcStartupDataCache.test'
import rtcWebRtcCallControllerTest from './RtcWebRtcCallController.test'
import rtcWebRtcReconnectPolicyTest from './RtcWebRtcReconnectPolicy.test'
import rtcWebRtcSignalSessionTest from './RtcWebRtcSignalSession.test'
import rtcWebRtcSignalStateMachineTest from './RtcWebRtcSignalStateMachine.test'
import rtcWebRtcMediaControllerTest from './RtcWebRtcMediaController.test'
import rtcVideoRenderControllerTest from './RtcVideoRenderController.test'
import rtcVideoCaptureStopGateTest from './RtcVideoCaptureStopGate.test'

export default function testsuite() {
  rtcAdminEntryControllerTest()
  rtcAppVersionTest()
  rtcAudioControllerTest()
  rtcBroadcastHistoryTest()
  rtcCallAudioPolicyControllerTest()
  rtcCallLifecycleStoreTest()
  rtcCallSessionStoreTest()
  rtcCallSettingControllerTest()
  rtcCallSettingPolicyTest()
  rtcCallUiPresenterTest()
  rtcDefaultCallServiceTest()
  rtcHostCallControllerTest()
  rtcHostMultiCallControllerTest()
  rtcIncomingCallQueueTest()
  rtcNetworkRequestRecoveryControllerTest()
  rtcPeerSessionRegistryTest()
  rtcRingtoneControllerTest()
  rtcRuntimeConfigControllerTest()
  rtcStartupFallbackControllerTest()
  rtcStartupDataCacheTest()
  rtcWebRtcCallControllerTest()
  rtcWebRtcReconnectPolicyTest()
  rtcWebRtcSignalSessionTest()
  rtcWebRtcSignalStateMachineTest()
  rtcWebRtcMediaControllerTest()
  rtcVideoRenderControllerTest()
  rtcVideoCaptureStopGateTest()
}
