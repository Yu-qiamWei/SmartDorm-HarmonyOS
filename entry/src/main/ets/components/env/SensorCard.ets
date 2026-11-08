/**
 * 智寓 · 传感器卡片（FR-03-03 / FR-03-09 / T-03 C4）
 * 当前值、单位、合法范围、手动调整控件（输入框 + 快捷步进 + 应用）全部真实可用。
 */
import { EnvironmentData } from '../../model/EnvironmentData';
import { CommandResult } from '../../model/CommandResult';
import { SensorType, EnvSource } from '../../model/Enums';
import { ThemeTokens } from '../../common/ThemeTokens';
import { Stage2ServiceFacade } from '../../service/ServiceContracts';
import { ToastHost } from '../common/ToastHost';

@Component
@Preview
export struct SensorCard {
  @Prop sensorType: SensorType = SensorType.TEMPERATURE;
  @Prop label: string = '温度';
  @Prop value: number = 25;
  @Prop unit: string = '℃';
  @Prop minValue: number = -10;
  @Prop maxValue: number = 50;
  @Prop step: number = 1;
  @State draft: string = '25';
  /** 调整默认实现：调用 MI-08 契约占位并 Toast 反馈（越界会返回 INVALID_PARAM）。 */
  onAdjust: (sensorType: SensorType, value: number) => void =
    (sensorType: SensorType, value: number): void => {
      Stage2ServiceFacade.getInstance()
        .adjustEnvironment(sensorType, value, EnvSource.MANUAL)
        .then((result: CommandResult<EnvironmentData>): void => {
          ToastHost.showResult<EnvironmentData>(result);
        });
    };

  private currentDraftNumber(): number {
    const parsed: number = Number.parseFloat(this.draft);
    return Number.isNaN(parsed) ? this.value : parsed;
  }

  build() {
    Column() {
      Row() {
        Text(this.label)
          .fontSize(ThemeTokens.FONT_TITLE_MEDIUM)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
        Blank()
        Text(this.value + this.unit)
          .fontSize(ThemeTokens.FONT_TITLE_MEDIUM)
          .fontColor(ThemeTokens.PRIMARY)
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')

      Text('合法范围 ' + this.minValue + ' — ' + this.maxValue + this.unit)
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.TEXT_HINT)
        .margin({ top: 6, bottom: ThemeTokens.SPACE_ITEM_GAP })

      TextInput({ placeholder: '输入新数值', text: this.draft })
        .type(InputType.Number)
        .fontSize(ThemeTokens.FONT_BODY)
        .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
        .borderRadius(ThemeTokens.RADIUS_CONTROL)
        .onChange((text: string): void => {
          this.draft = text;
        })

      Row() {
        Button('−' + this.step)
          .fontSize(ThemeTokens.FONT_BODY)
          .fontColor(ThemeTokens.PRIMARY)
          .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
          .borderRadius(ThemeTokens.RADIUS_CONTROL)
          .layoutWeight(1)
          .onClick(() => {
            const next: number = Math.max(this.minValue, this.currentDraftNumber() - this.step);
            this.draft = String(next);
            this.onAdjust(this.sensorType, next);
          })
        Button('+' + this.step)
          .fontSize(ThemeTokens.FONT_BODY)
          .fontColor(ThemeTokens.PRIMARY)
          .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
          .borderRadius(ThemeTokens.RADIUS_CONTROL)
          .layoutWeight(1)
          .margin({ left: ThemeTokens.SPACE_ITEM_GAP })
          .onClick(() => {
            const next: number = Math.min(this.maxValue, this.currentDraftNumber() + this.step);
            this.draft = String(next);
            this.onAdjust(this.sensorType, next);
          })
        Button('应用')
          .fontSize(ThemeTokens.FONT_BODY)
          .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
          .backgroundColor(ThemeTokens.PRIMARY)
          .borderRadius(ThemeTokens.RADIUS_CONTROL)
          .layoutWeight(1)
          .margin({ left: ThemeTokens.SPACE_ITEM_GAP })
          .onClick(() => {
            const next: number = this.currentDraftNumber();
            this.onAdjust(this.sensorType, next);
          })
      }
      .width('100%')
      .margin({ top: ThemeTokens.SPACE_ITEM_GAP })
    }
    .width('100%')
    .padding(ThemeTokens.SPACE_CARD_PADDING)
    .backgroundColor(ThemeTokens.CARD_BACKGROUND)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .border({ width: 1, color: ThemeTokens.DIVIDER })
  }
}
