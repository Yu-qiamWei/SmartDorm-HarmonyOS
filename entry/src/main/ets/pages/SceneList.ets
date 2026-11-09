/**
 * 智寓 · 场景模式列表（FR-05 / T-04）
 * 4 预置场景 + 自定义场景、切换、编辑、删除、新建入口全部真实回调。
 */
import { Scene } from '../model/Scene';
import { AppState } from '../model/AppState';
import { AppDataRepository } from '../store/AppDataRepository';
import { ThemeTokens } from '../common/ThemeTokens';
import { RouteMap } from '../common/RouteMap';
import {
  StateChangeHandler, Unsubscribe, ChangeSet
} from '../common/StateChangeTypes';
import { PageHeader } from '../components/common/PageHeader';
import { SectionCard } from '../components/common/SectionCard';
import { SceneCard } from '../components/scene/SceneCard';
import { EmptyView } from '../components/common/EmptyView';
import { ToastHost } from '../components/common/ToastHost';

@Entry
@Component
struct SceneList {
  @State scenes: Scene[] = [];
  @State currentSceneId: string = '';
  @State currentMode: string = 'MANUAL';

  private unsubscribe: Unsubscribe | undefined = undefined;
  private onStateChange: StateChangeHandler = (change: ChangeSet): void => {
    this.refresh();
  };

  aboutToAppear(): void {
    this.unsubscribe = AppDataRepository.getInstance().subscribe(this.onStateChange);
    this.refresh();
  }

  aboutToDisappear(): void {
    if (this.unsubscribe !== undefined) {
      this.unsubscribe();
      this.unsubscribe = undefined;
    }
  }

  private refresh(): void {
    const state: AppState = AppDataRepository.getInstance().getState();
    this.scenes = state.scenes.slice();
    this.currentSceneId = state.currentSceneId;
    this.currentMode = state.currentMode;
  }

  build() {
    Scroll() {
      Column() {
        PageHeader({
          title: '场景模式',
          subtitle: '当前运行模式：' + this.currentMode,
          showBack: true,
          actionLabel: '首页'
        })

        SectionCard({
          title: '一键切换',
          caption: '切换会按场景目标逐设备应用状态；离寝先保存当前状态快照、回寝按快照恢复，并返回逐设备执行报告'
        }) {
          Row() {
            Button('新建自定义场景')
              .fontSize(ThemeTokens.FONT_BODY)
              .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
              .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
              .backgroundColor(ThemeTokens.PRIMARY)
              .borderRadius(ThemeTokens.RADIUS_CONTROL)
              .layoutWeight(1)
              .onClick(() => {
                RouteMap.push(RouteMap.SCENE_EDIT, { mode: 'create' });
              })
            Button('查看切换日志')
              .fontSize(ThemeTokens.FONT_BODY)
              .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
              .fontColor(ThemeTokens.PRIMARY)
              .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
              .borderRadius(ThemeTokens.RADIUS_CONTROL)
              .layoutWeight(1)
              .margin({ left: ThemeTokens.SPACE_ITEM_GAP })
              .onClick(() => {
                RouteMap.push(RouteMap.STATISTICS);
              })
          }
          .width('100%')
          Button('回寝状态恢复说明')
            .fontSize(ThemeTokens.FONT_CAPTION)
            .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
            .fontColor(ThemeTokens.TEXT_SECONDARY)
            .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
            .borderRadius(ThemeTokens.RADIUS_CONTROL)
            .width('100%')
            .margin({ top: ThemeTokens.SPACE_ITEM_GAP })
            .onClick(() => {
              ToastHost.showMessage(
                'FR-05-04：回寝读取离寝前的 returnSnapshot 恢复用户预设状态，ST-03 实现'
              );
            })
        }

        SectionCard({
          title: '全部场景',
          caption: '共 ' + this.scenes.length + ' 个 · 预置场景不可删除但可编辑'
        }) {
          if (this.scenes.length === 0) {
            EmptyView({
              message: '暂无场景',
              hint: '首次启动应包含 4 个预置场景',
              actionLabel: '新建场景',
              onAction: (): void => {
                RouteMap.push(RouteMap.SCENE_EDIT, { mode: 'create' });
              }
            })
          } else {
            ForEach(this.scenes, (scene: Scene): void => {
              SceneCard({
                scene: scene,
                active: scene.id === this.currentSceneId
              }).margin({ bottom: ThemeTokens.SPACE_ITEM_GAP })
            }, (scene: Scene): string => SceneCard.keyOf(scene, scene.id === this.currentSceneId))
          }
        }
      }
      .width('100%')
      .padding({
        left: ThemeTokens.SPACE_PAGE_X,
        right: ThemeTokens.SPACE_PAGE_X,
        bottom: ThemeTokens.SPACE_SECTION_GAP
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
  }
}
