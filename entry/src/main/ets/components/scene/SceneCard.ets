/**
 * 智寓 · 场景卡片（FR-05 / T-03 C4）
 * 类型、目标设备数、切换、编辑、删除全部有真实回调。
 */
import { Scene } from '../../model/Scene';
import { SceneApplyReport } from '../../model/Reports';
import { CommandResult } from '../../model/CommandResult';
import { SceneType } from '../../model/Enums';
import { ThemeTokens } from '../../common/ThemeTokens';
import { RouteMap } from '../../common/RouteMap';
import { ServiceFacade } from '../../service/ServiceFacade';
import { ToastHost } from '../common/ToastHost';
import { ConfirmDialog } from '../common/ConfirmDialog';

const PREVIEW_SCENE: Scene = {
  id: 'scn_preview_01',
  name: '学习模式（预览占位）',
  type: SceneType.STUDY,
  deviceStates: [],
  isPreset: true,
  returnSnapshot: [],
  createdAt: 0,
  updatedAt: 0
};

@Component
@Preview
export struct SceneCard {
  @Prop scene: Scene = PREVIEW_SCENE;
  @Prop active: boolean = false;
  /** 切换默认实现：调用 MI-14 契约占位，并把执行报告结果数反馈给用户。 */
  onApply: (sceneId: string) => void = (sceneId: string): void => {
    ServiceFacade.getInstance().applyScene(sceneId)
      .then((report: SceneApplyReport): void => {
        ToastHost.showMessage(
          '场景切换报告：共 ' + report.total + ' 项，成功 ' + report.appliedCount +
          ' 项，失败 ' + report.failedCount + ' 项（阶段二占位）'
        );
      });
  };
  /** 编辑默认实现：真实跳转场景编辑页。 */
  onEdit: (sceneId: string) => void = (sceneId: string): void => {
    RouteMap.push(RouteMap.SCENE_EDIT, { mode: 'edit', sceneId: sceneId });
  };
  /** 删除默认实现：二次确认 + 明确 Toast（预置场景不可删，给出原因）。 */
  onDelete: (sceneId: string, isPreset: boolean) => void =
    (sceneId: string, isPreset: boolean): void => {
      if (isPreset) {
        ToastHost.showMessage('预置场景不可删除，可进入编辑页修改目标状态');
        return;
      }
      ConfirmDialog.show('删除场景', '确认删除该自定义场景？', (): void => {
        ServiceFacade.getInstance().removeScene(sceneId)
          .then((result: CommandResult<void>): void => {
            ToastHost.showResult(result);
          });
      });
    };

  build() {
    Column() {
      Row() {
        Text(this.scene.name)
          .fontSize(ThemeTokens.FONT_TITLE_MEDIUM)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
        Blank()
        Text(this.active ? '当前场景' : (this.scene.isPreset ? '预置' : '自定义'))
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(this.active ? ThemeTokens.STATUS_RUNNING : ThemeTokens.TEXT_HINT)
      }
      .width('100%')

      Text('类型 ' + this.scene.type + '　·　目标设备 ' + this.scene.deviceStates.length + ' 台')
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.TEXT_SECONDARY)
        .margin({ top: 6, bottom: ThemeTokens.SPACE_ITEM_GAP })

      Row() {
        Button('切换场景')
          .fontSize(ThemeTokens.FONT_BODY)
          .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
          .backgroundColor(this.active ? ThemeTokens.ACCENT : ThemeTokens.PRIMARY)
          .borderRadius(ThemeTokens.RADIUS_CONTROL)
          .layoutWeight(1)
          .onClick(() => {
            this.onApply(this.scene.id);
          })
        Button('编辑')
          .fontSize(ThemeTokens.FONT_BODY)
          .fontColor(ThemeTokens.PRIMARY)
          .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
          .borderRadius(ThemeTokens.RADIUS_CONTROL)
          .layoutWeight(1)
          .margin({ left: ThemeTokens.SPACE_ITEM_GAP })
          .onClick(() => {
            this.onEdit(this.scene.id);
          })
        Button('删除')
          .fontSize(ThemeTokens.FONT_BODY)
          .fontColor(ThemeTokens.STATUS_FAULT)
          .backgroundColor(ThemeTokens.WARNING_BACKGROUND)
          .borderRadius(ThemeTokens.RADIUS_CONTROL)
          .layoutWeight(1)
          .margin({ left: ThemeTokens.SPACE_ITEM_GAP })
          .onClick(() => {
            this.onDelete(this.scene.id, this.scene.isPreset);
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(ThemeTokens.SPACE_CARD_PADDING)
    .backgroundColor(ThemeTokens.CARD_BACKGROUND)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .border({ width: this.active ? 2 : 1, color: this.active ? ThemeTokens.ACCENT : ThemeTokens.DIVIDER })
  }
}
