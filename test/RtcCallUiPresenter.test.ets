import { describe, it, expect } from '@ohos/hypium'
import { RtcCallViewPhase, RtcCallViewState } from '../src/main/ets/model/RtcCallViewState'
import {
  RtcCallDeviceRole,
  RtcCallUiAction,
  RtcCallUiPresenter
} from '../src/main/ets/ui/RtcCallUiPresenter'

function findActionVisible(phase: RtcCallViewPhase, role: RtcCallDeviceRole, action: RtcCallUiAction): boolean {
  const state = new RtcCallViewState()
  state.visible = true
  state.phase = phase

  const model = RtcCallUiPresenter.present(state, { role })
  return model.actions.find(item => item.action === action)?.visible === true
}

export default function rtcCallUiPresenterTest() {
  describe('RtcCallUiPresenter', () => {
    it('shows hold and resume actions for host role only', 0, () => {
      expect(findActionVisible(RtcCallViewPhase.CONNECTED, RtcCallDeviceRole.HOST,
        RtcCallUiAction.HOLD)).assertEqual(true)
      expect(findActionVisible(RtcCallViewPhase.HELD, RtcCallDeviceRole.HOST,
        RtcCallUiAction.RESUME)).assertEqual(true)

      expect(findActionVisible(RtcCallViewPhase.CONNECTED, RtcCallDeviceRole.BED,
        RtcCallUiAction.HOLD)).assertEqual(false)
      expect(findActionVisible(RtcCallViewPhase.HELD, RtcCallDeviceRole.BED,
        RtcCallUiAction.RESUME)).assertEqual(false)
    })
  })
}
