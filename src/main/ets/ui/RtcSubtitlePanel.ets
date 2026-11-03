import { RtcHostCallUiItem, RtcHostCallUiModel } from '../model/RtcHostCallUiModel'
import { RtcCallViewPhase } from '../model/RtcCallViewState'
import {
  RtcSubtitleLine,
  RtcSubtitleSessionView,
  RtcSubtitleStore
} from '../subtitle/RtcSubtitleStore'
import {
  rtcSubtitleBackgroundArgb,
  rtcSubtitleLineHeightFp,
  rtcSubtitleStrokeArgb,
  RtcSubtitleStyleSpec
} from '../subtitle/RtcSubtitleStyle'

@Component
export struct RtcSubtitlePanel {
  @Prop @Watch('onUidChange') uid: string = ''
  @Prop title: string = ''
  @Prop showTitle: boolean = false
  @Prop compact: boolean = false
  store?: RtcSubtitleStore

  @State private view: RtcSubtitleSessionView = new RtcSubtitleSessionView()
  @State private followLatest: boolean = true
  @State private expanded: boolean = false
  private scroller: Scroller = new Scroller()
  private unsubscribe?: () => void
  private programmaticScroll: boolean = false
  private releaseScrollGuard: number = -1

  aboutToAppear(): void {
    this.attach()
  }

  aboutToDisappear(): void {
    this.detach()
  }

  private onUidChange(): void {
    // 通话切换时不能沿用上一路的跟随状态和历史行。
    this.followLatest = true
    this.expanded = false
    this.view = new RtcSubtitleSessionView()
    this.attach()
  }

  private attach(): void {
    this.detach()
    const store = this.store
    if (!store) {
      return
    }
    this.unsubscribe = store.subscribe((sessions: RtcSubtitleSessionView[]) => {
      this.applySnapshot(sessions)
    })
  }

  private detach(): void {
    this.unsubscribe?.()
    this.unsubscribe = undefined
    if (this.releaseScrollGuard >= 0) {
      clearTimeout(this.releaseScrollGuard)
      this.releaseScrollGuard = -1
    }
  }

  private applySnapshot(sessions: RtcSubtitleSessionView[]): void {
    const uid = this.uid
    let next: RtcSubtitleSessionView | undefined = undefined
    for (let i = 0; i < sessions.length; i += 1) {
      if (sessions[i].uid === uid) {
        next = sessions[i]
      }
    }
    if (!next) {
      return
    }
    this.view = next
    if (this.followLatest) {
      this.scrollToEnd()
    }
  }

  private scrollToEnd(): void {
    this.programmaticScroll = true
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom)
    }, 0)
    // 触底回调没来也不能把用户滚动检测一直锁死。
    if (this.releaseScrollGuard >= 0) {
      clearTimeout(this.releaseScrollGuard)
    }
    this.releaseScrollGuard = setTimeout(() => {
      this.programmaticScroll = false
      this.releaseScrollGuard = -1
    }, 1500)
  }

  private cursorFor(line: RtcSubtitleLine): string {
    return line.isFinal ? '' : ' ▍'
  }

  private panelMaxHeight(): string {
    return this.compact ? '132vp' : '208vp'
  }

  private captionLines(): RtcSubtitleLine[] {
    const lines = this.view.lines
    if (lines.length <= 1) {
      return lines
    }
    return lines.slice(lines.length - 2)
  }

  /**
   * 字幕区挂在对应那一路通话的画面上，名称和区域标题重复，所以当前句和上一句都不加前缀，
   * 只靠分色区分发言人；展开成完整记录时才带名称，否则多方通话的历史回看分不清谁说的。
   */
  private transcriptLabel(line: RtcSubtitleLine): string {
    return line.label + ' '
  }

  /** 字号直接按网关给的 fp 用：不乘缩放系数，也不跟随页面字号设置。 */
  private styleFontSize(style: RtcSubtitleStyleSpec): string {
    return style.fontSize + 'fp'
  }

  private styleLineHeight(style: RtcSubtitleStyleSpec): string {
    return rtcSubtitleLineHeightFp(style) + 'fp'
  }

  private styleBackground(style: RtcSubtitleStyleSpec): string {
    return rtcSubtitleBackgroundArgb(style)
  }

  private entryPadding(): Padding {
    const padding: Padding = { left: 10, right: 10, top: 4, bottom: 4 }
    return padding
  }

  /**
   * 描边用 textShadow 模拟而不是 Canvas 两次描边：零偏移、blur 等于描边宽度的阴影画在字形
   * 后面，只露出字形外侧一圈，不会糊掉笔画；取舍是边缘偏软、没有 Canvas 硬边那么利落，
   * 换来的是保留模式渲染、不为每帧创建 Paint/Path 对象。
   * stroke_width=0 时半径 0 且颜色全透明，保证完全不出现阴影、也不残留上一次描边。
   */
  private styleStroke(style: RtcSubtitleStyleSpec): ShadowOptions {
    if (style.strokeWidth <= 0) {
      const none: ShadowOptions = { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 }
      return none
    }
    const shadow: ShadowOptions = {
      radius: style.strokeWidth + 'fp',
      color: rtcSubtitleStrokeArgb(style),
      offsetX: 0,
      offsetY: 0
    }
    return shadow
  }

  private captionColor(index: number, total: number): number {
    return index === total - 1 ? 1 : 0.55
  }

  build() {
    if (this.view.lines.length > 0) {
      Column() {
        if (this.showTitle && this.title.length > 0) {
          Text(this.title)
            .fontSize(this.compact ? '16fp' : '20fp')
            .fontColor('#FFC9CBD1')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .textAlign(TextAlign.Center)
        }

        if (this.expanded) {
          Scroll(this.scroller) {
            Column({ space: this.compact ? '4vp' : '8vp' }) {
              ForEach(this.view.lines, (line: RtcSubtitleLine) => {
                Text() {
                  Span(this.transcriptLabel(line))
                    .fontColor(line.color)
                  Span(line.text)
                    .fontColor(line.style.textColor)
                  Span(this.cursorFor(line))
                    .fontColor(line.color)
                }
                .width('100%')
                .fontSize(this.styleFontSize(line.style))
                .lineHeight(this.styleLineHeight(line.style))
                .textAlign(TextAlign.Start)
                .backgroundColor(this.styleBackground(line.style))
                .borderRadius(this.compact ? 8 : 10)
                .padding(this.entryPadding())
                .textShadow(this.styleStroke(line.style))
              }, (line: RtcSubtitleLine) => line.id + '|' + line.updatedAt + '|' + (line.isFinal ? 'f' : 'p'))
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .constraintSize({ maxHeight: this.panelMaxHeight() })
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.None)
          .onScrollStart(() => {
            if (!this.programmaticScroll) {
              this.followLatest = false
            }
          })
          .onReachEnd(() => {
            this.followLatest = true
            this.programmaticScroll = false
          })

          if (!this.followLatest) {
            Text('回到最新')
              .fontSize(this.compact ? '14fp' : '18fp')
              .fontColor('#FF1F2124')
              .backgroundColor('#FFE6E9EF')
              .borderRadius(this.compact ? '12vp' : '16vp')
              .padding({
                left: '12vp',
                right: '12vp',
                top: '4vp',
                bottom: '4vp'
              })
              .onClick(() => {
                this.followLatest = true
                this.scrollToEnd()
              })
          } else {
            Text('收起')
              .fontSize(this.compact ? '14fp' : '18fp')
              .fontColor('#FFB9BBBF')
              .onClick(() => {
                this.expanded = false
              })
          }
        } else {
          ForEach(this.captionLines(), (line: RtcSubtitleLine, index: number) => {
            Text() {
              Span(line.text)
                .fontColor(line.style.textColor)
              Span(this.cursorFor(line))
                .fontColor(line.color)
            }
            .constraintSize({ maxWidth: '100%' })
            .fontSize(this.styleFontSize(line.style))
            .lineHeight(this.styleLineHeight(line.style))
            .opacity(this.captionColor(index, this.captionLines().length))
            .textAlign(TextAlign.Center)
            .backgroundColor(this.styleBackground(line.style))
            .borderRadius(this.compact ? 8 : 10)
            .padding(this.entryPadding())
            .textShadow(this.styleStroke(line.style))
            .maxLines(this.compact ? 2 : 3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          }, (line: RtcSubtitleLine) => line.id + '|' + line.updatedAt + '|' + (line.isFinal ? 'f' : 'p'))
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        this.expanded = !this.expanded
      })
      .padding({
        left: this.compact ? '10vp' : '16vp',
        right: this.compact ? '10vp' : '16vp',
        top: this.compact ? '6vp' : '10vp',
        bottom: this.compact ? '6vp' : '10vp'
      })
    } else {
      Blank()
        .width(0)
        .height(0)
    }
  }
}

@Component
export struct RtcSubtitleOverlay {
  @Prop model: RtcHostCallUiModel = new RtcHostCallUiModel()
  @State private compact: boolean = false
  store?: RtcSubtitleStore

  private getAllCalls(): RtcHostCallUiItem[] {
    const calls: RtcHostCallUiItem[] = []
    if (this.model.activeCall) {
      calls.push(this.model.activeCall)
    }
    const sideCalls = this.model.sideCalls || []
    sideCalls.forEach((call: RtcHostCallUiItem) => {
      if (call) {
        calls.push(call)
      }
    })
    return calls
  }

  /**
   * 有待接听的通话时整条字幕带不渲染：待接听页是全屏卡片网格，压在上面会盖住接听按钮，
   * 铃声和按钮判定这类已验证行为不该被旁路能力碰到。
   */
  private hasPendingAnswerCall(): boolean {
    let pending = false
    this.getAllCalls().forEach((call: RtcHostCallUiItem): void => {
      if (call.phase === RtcCallViewPhase.INCOMING || call.phase === RtcCallViewPhase.OUTGOING) {
        pending = true
      }
    })
    return pending
  }

  private getSubtitleCalls(): RtcHostCallUiItem[] {
    const calls: RtcHostCallUiItem[] = []
    const seen: string[] = []
    this.getAllCalls().forEach((call: RtcHostCallUiItem): void => {
      const uid = (call.uid || '').trim()
      const answered = call.phase === RtcCallViewPhase.CONNECTING ||
        call.phase === RtcCallViewPhase.CONNECTED ||
        call.phase === RtcCallViewPhase.HELD
      if (uid.length > 0 && answered && seen.indexOf(uid) < 0) {
        seen.push(uid)
        calls.push(call)
      }
    })
    return calls
  }

  private getTitle(call: RtcHostCallUiItem): string {
    return call.displayName || call.peerNumber || '通话'
  }

  /**
   * 字幕贴在画面底部，但要让开通话控制条：控制条是图标 + 文字 + 内边距再加 20vp 下边距，
   * 这里按同一套尺寸留出净空，压住按钮就没法挂断了。
   * Edges 的字段是 `${number}vp | number`，返回 string 编不过，所以这里给数字 vp。
   */
  private captionBottomOffset(): number {
    return this.compact ? 170 : 240
  }

  private bandWidth(): string {
    return this.getSubtitleCalls().length > 1 ? '75%' : '100%'
  }

  build() {
    if (this.store && this.model.visible && !this.hasPendingAnswerCall()) {
      Row({ space: this.compact ? '6vp' : '12vp' }) {
        ForEach(this.getSubtitleCalls(), (call: RtcHostCallUiItem) => {
          Column() {
            RtcSubtitlePanel({
              uid: call.uid,
              title: this.getTitle(call),
              showTitle: this.getSubtitleCalls().length > 1,
              compact: this.compact,
              store: this.store
            })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
        }, (call: RtcHostCallUiItem) => call.uid)
      }
      .width(this.bandWidth())
      .alignItems(VerticalAlign.Bottom)
      .position({ left: 0, bottom: this.captionBottomOffset() })
      .padding({
        left: this.compact ? '10vp' : '20vp',
        right: this.compact ? '10vp' : '20vp'
      })
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.compact = Number(newArea.width) > 0 && Number(newArea.width) < 1280
      })
    } else {
      Blank()
        .width(0)
        .height(0)
    }
  }
}
