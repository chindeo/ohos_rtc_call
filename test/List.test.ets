import rtcAdminEntryControllerTest from './RtcAdminEntryController.test'
import rtcAudioControllerTest from './RtcAudioController.test'
import rtcCallAudioPolicyControllerTest from './RtcCallAudioPolicyController.test'
import rtcDefaultCallServiceTest from './RtcDefaultCallService.test'
import rtcHardwareCallControllerTest from './RtcHardwareCallController.test'
import rtcRuntimeConfigControllerTest from './RtcRuntimeConfigController.test'
import rtcWebRtcSignalStateMachineTest from './RtcWebRtcSignalStateMachine.test'

export default function testsuite() {
  rtcAdminEntryControllerTest()
  rtcAudioControllerTest()
  rtcCallAudioPolicyControllerTest()
  rtcDefaultCallServiceTest()
  rtcHardwareCallControllerTest()
  rtcRuntimeConfigControllerTest()
  rtcWebRtcSignalStateMachineTest()
}
