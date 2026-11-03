import { RtcHostCallUiItem, RtcHostCallUiModel } from '../model/RtcHostCallUiModel'
import { RtcCallViewPhase } from '../model/RtcCallViewState'
import {
  RtcSubtitleLine,
  RtcSubtitleSessionView,
  RtcSubtitleStore
} from '../subtitle/RtcSubtitleStore'
import {
  rtcSubtitleBackgroundArgb,
  rtcSubtitleLineHeightFromFp,
  rtcSubtitleStrokeArgb,
  rtcSubtitleWithAlpha,
  RtcSubtitleStyleSpec
} from '../subtitle/RtcSubtitleStyle'

/** 右侧窄栏只有 300vp，字号超过这个值就一行放不下几个字。 */
const SIDE_FONT_SIZE_FP: number = 16

/** 字幕静默多久后自动收起整块（秒级轮询，下一帧到达立即恢复）。 */
const SUBTITLE_SILENCE_HIDE_MS: number = 12000

@Component
export struct RtcSubtitlePanel {
  @Prop @Watch('onUidChange') uid: string = ''
  @Prop compact: boolean = false
  /**
   * 面板挂在右侧窄栏还是主区。窄栏只有 300vp，按网关下发的字号一行只放得下十来个汉字，
   * 所以这一路端上降一档；主区仍完全照网关值。创建后不变，不需要响应式。
   */
  side: boolean = false
  store?: RtcSubtitleStore

  @State private view: RtcSubtitleSessionView = new RtcSubtitleSessionView()
  @State private followLatest: boolean = true
  @State private expanded: boolean = false
  @State private stale: boolean = false
  private scroller: Scroller = new Scroller()
  private unsubscribe?: () => void
  private programmaticScroll: boolean = false
  private releaseScrollGuard: number = -1
  private staleTimer: number = -1

  aboutToAppear(): void {
    this.attach()
    this.startStaleTimer()
  }

  aboutToDisappear(): void {
    this.detach()
    this.stopStaleTimer()
  }

  /**
   * 没人说话时最后两句不该一直糊在画面上：静默超过 SUBTITLE_SILENCE_HIDE_MS 就把字幕态整块收起，
   * 下一帧到达立即恢复（订阅一直在，不重新拉历史）。展开态是用户主动点开回看的，不自动收。
   */
  private startStaleTimer(): void {
    if (this.staleTimer >= 0) {
      return
    }
    this.refreshStale()
    this.staleTimer = setInterval((): void => {
      this.refreshStale()
    }, 1000)
  }

  private stopStaleTimer(): void {
    if (this.staleTimer >= 0) {
      clearInterval(this.staleTimer)
      this.staleTimer = -1
    }
  }

  private lastActivityMs(): number {
    const lines = this.view.lines
    let last = 0
    for (let i = 0; i < lines.length; i += 1) {
      last = Math.max(last, lines[i].updatedAt)
    }
    return last
  }

  private refreshStale(): void {
    const last = this.lastActivityMs()
    this.stale = last <= 0 || Date.now() - last > SUBTITLE_SILENCE_HIDE_MS
  }

  private onUidChange(): void {
    // 通话切换时不能沿用上一路的跟随状态和历史行。
    this.followLatest = true
    this.expanded = false
    this.stale = false
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
    // 新帧到了立刻把"静默已收起"状态清掉，不等下一次秒级轮询。
    this.refreshStale()
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

  /** 字幕态的净高：给标题 chip 和上下内边距留出位置后，剩下的就是这两句的空间。 */
  private captionMaxHeight(): string {
    return this.compact ? '104vp' : '160vp'
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

  /**
   * 生效字号：主区照网关下发值，窄栏那一路压到 SIDE_FONT_SIZE_FP 以内。
   * 行高跟着生效字号走，否则 16fp 的字配 28fp 的行高会散。
   */
  private effectiveFontSizeFp(style: RtcSubtitleStyleSpec): number {
    return this.side ? Math.min(style.fontSize, SIDE_FONT_SIZE_FP) : style.fontSize
  }

  /** 字号按网关给的 fp 用（窄栏见上）：不乘缩放系数，也不跟随页面字号设置。 */
  private styleFontSize(style: RtcSubtitleStyleSpec): string {
    return this.effectiveFontSizeFp(style) + 'fp'
  }

  private styleLineHeight(style: RtcSubtitleStyleSpec): string {
    return rtcSubtitleLineHeightFromFp(this.effectiveFontSizeFp(style)) + 'fp'
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
      // ShadowOptions.radius 只收 number|Resource，不收 '2fp' 这类字符串；数字按 vp 取。
      radius: style.strokeWidth,
      color: rtcSubtitleStrokeArgb(style),
      offsetX: 0,
      offsetY: 0
    }
    return shadow
  }

  private captionAlpha(index: number, total: number): number {
    return index === total - 1 ? 1 : 0.55
  }

  build() {
    if (this.view.lines.length > 0 && !(this.stale && !this.expanded)) {
      Column() {
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
          Column({ space: this.compact ? '4vp' : '6vp' }) {
            ForEach(this.captionLines(), (line: RtcSubtitleLine, index: number) => {
              Text() {
                Span(line.text)
                  .fontColor(rtcSubtitleWithAlpha(line.style.textColor,
                    this.captionAlpha(index, this.captionLines().length)))
                Span(this.cursorFor(line))
                  .fontColor(rtcSubtitleWithAlpha(line.color,
                    this.captionAlpha(index, this.captionLines().length)))
              }
              .constraintSize({ maxWidth: '100%' })
              .fontSize(this.styleFontSize(line.style))
              .lineHeight(this.styleLineHeight(line.style))
              .textAlign(TextAlign.Center)
              .backgroundColor(this.styleBackground(line.style))
              .borderRadius(this.compact ? 8 : 10)
              .padding(this.entryPadding())
              .textShadow(this.styleStroke(line.style))
              .maxLines(this.compact ? 2 : 3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            }, (line: RtcSubtitleLine) => line.id + '|' + line.updatedAt + '|' + (line.isFinal ? 'f' : 'p'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          // 底对齐 + 限高：两句各 2–3 行时原来能一路往上长到画面中部，现在超出先挤掉
          // 顶上的上一句，正在说的当前句不被裁（缺字比少一行历史严重）。
          .justifyContent(FlexAlign.End)
          .constraintSize({ maxHeight: this.captionMaxHeight() })
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

  /**
   * 字幕贴在画面底部，但要让开通话控制条：控制条是图标 + 文字 + 内边距再加 20vp 下边距，
   * 这里按同一套尺寸留出净空，压住按钮就没法挂断了。
   * Edges 的字段是 `${number}vp | number`，返回 string 编不过，所以这里给数字 vp。
   */
  private captionBottomOffset(): number {
    return this.compact ? 170 : 240
  }

  /** 除主区那一路以外的各路都进右侧窄栏。 */
  private sideSubtitleCalls(): RtcHostCallUiItem[] {
    const calls = this.getSubtitleCalls()
    const side: RtcHostCallUiItem[] = []
    for (let i = 1; i < calls.length; i += 1) {
      side.push(calls[i])
    }
    return side
  }

  /** 与 RtcReferenceCallLayout 的侧栏同宽，侧路字幕才贴在它自己的侧卡上。 */
  private sideZoneWidth(): string {
    return this.compact ? '220vp' : '300vp'
  }

  /**
   * 只有在整组还没有接通的一路时才整带不渲染：那时待接听页是全屏卡片网格，
   * 字幕压上去会盖住接听按钮。多路时待接听的第二路显示成侧栏小卡，
   * 已接通那一路的字幕不该被它连坐藏掉。
   */
  private hasEstablishedCall(): boolean {
    let established = false
    this.getAllCalls().forEach((call: RtcHostCallUiItem): void => {
      if (call.phase === RtcCallViewPhase.CONNECTED || call.phase === RtcCallViewPhase.HELD) {
        established = true
      }
    })
    return established
  }

  private shouldSuppressForPendingCall(): boolean {
    return this.hasPendingAnswerCall() && !this.hasEstablishedCall()
  }

  build() {
    if (this.store && this.model.visible && !this.shouldSuppressForPendingCall()) {
      Row({ space: this.compact ? '6vp' : '12vp' }) {
        // 主画面的那一路占主区；其余各路叠在右侧窄区，贴着它们自己的小窗画面，
        // 不再让第二路的字幕跑到主画面里、和它的视频分离。
        // 是否建面板只看这一路是否已接通，不能看"当前有没有字幕行"：帧到达不会
        // 触发本组件重渲染，等首帧把面板"等出来"侧栏那一路就永远不出现（真机回归）。
        // 空行由面板自己按 view.lines 长度收起，不占位。
        if (this.getSubtitleCalls().length > 0) {
          Column() {
            // 面板不带标题 chip：主区和窄栏的字幕都贴着各自画面的下方，画面左上角已经有
            // 同名 NameTag，再顶一个 chip 是同一件事说两遍（真机截图上出现过两次）。
            RtcSubtitlePanel({
              uid: this.getSubtitleCalls()[0].uid,
              compact: this.compact,
              store: this.store
            })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
        }
        if (this.sideSubtitleCalls().length > 0) {
          Column({ space: this.compact ? '4vp' : '8vp' }) {
            ForEach(this.sideSubtitleCalls(), (call: RtcHostCallUiItem) => {
              RtcSubtitlePanel({
                uid: call.uid,
                compact: true,
                side: true,
                store: this.store
              })
            }, (call: RtcHostCallUiItem) => call.uid)
          }
          .width(this.sideZoneWidth())
          .alignItems(HorizontalAlign.Center)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      .position({ left: 0, bottom: this.captionBottomOffset() })
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
