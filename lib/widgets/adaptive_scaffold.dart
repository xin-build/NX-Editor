import 'package:flutter/material.dart';

/// 响应式布局自适应脚手架
/// 自动在 PC 桌面端 (>= 800px) 与 移动端 (< 800px) 之间平滑切换交互模式
class AdaptiveScaffold extends StatelessWidget {
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? drawer;
  final Widget? endDrawer;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final Widget? desktopSideBar;
  final Widget? desktopRightPanel;
  final Widget? desktopBottomBar;
  final List<Widget>? desktopTopActions;

  const AdaptiveScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.drawer,
    this.endDrawer,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.desktopSideBar,
    this.desktopRightPanel,
    this.desktopBottomBar,
    this.desktopTopActions,
  });

  static bool isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= 800;
  }

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktop(context);

    if (desktop) {
      // ─── PC 桌面端布局 ───
      return Scaffold(
        appBar: appBar,
        body: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  // 左侧 Dock / 侧边栏
                  if (desktopSideBar != null) desktopSideBar!,

                  // 主工作区 (地图/内容，严格裁剪边界防止向外溢出)
                  Expanded(child: ClipRect(clipBehavior: Clip.hardEdge, child: body)),

                  // 右侧属性 / NBT / 选区面板
                  if (desktopRightPanel != null) desktopRightPanel!,
                ],
              ),
            ),

            // 底部桌面状态栏 (实时坐标/内存/FPS)
            if (desktopBottomBar != null) desktopBottomBar!,
          ],
        ),
      );
    } else {
      // ─── 移动端布局 ───
      return Scaffold(
        appBar: appBar,
        drawer: drawer,
        endDrawer: endDrawer,
        body: body,
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: bottomNavigationBar,
      );
    }
  }
}
