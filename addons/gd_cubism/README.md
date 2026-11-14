# GDCubism（巢战构建）

[GDCubism](https://github.com/MizunagiKB/gd_cubism) 是 Live2D 模型的非官方 GDExtension（MIT，见 `LICENSE.adoc`）。巢战用它在 Windows 上显示 Live2D 角色。这里放的是按巢战需要编译的 Windows 版，随游戏一起发布。

构建来源：

- 源码：GDCubism `3aaa3c9`（0.9 分支合并点）
- Cubism SDK for Native `5-r.5`（维护者在 Live2D 官网同意许可后自行下载，SDK 不进仓库）
- 补丁：`patches/chao-cubism-sdk-5-r.5.patch`

只登记了 Windows 的库。安卓等平台不加载这个扩展，角色显示立绘。

## 补丁内容

1. **适配 SDK 5-r.5**：渲染器构造函数和 `Create` 带宽高、补上两个新的纯虚函数、`GetRenderOrders`、颜色混合类型换算回三种混合着色器、表情 `StartMotion`、`SetLoop` / `SetLoopFadeIn`。
2. **绘制顺序**：原版用 `z_index` 排网格，会把模型抬到同一画布层里所有界面之上（总部血量、拖动中的卡牌）。改成按子节点顺序排。
3. **表情淡出**：`stop_expression()` 原来是立刻清空表情，改为按表情自己的淡出时间退出。
4. **视线组件越界**：`GDCubismEffectTargetPoint` 遇到模型没有的参数时会用 -1 下标写参数（Cubism SDK 不检查），改为跳过。巢战会把它的部分通道留空，用几层组件分别驱动眼、头、身体。
5. **性能**：剪贴遮罩用的 SubViewport 原来每帧随遮罩范围改尺寸，每次都会重新分配渲染目标（测试模型每帧约 85 ms）。改为尺寸够用就不改，按 64 像素取整；离开屏幕的遮罩暂停渲染，不再缩小。另外，没变化的网格和材质参数不再重复上传。
6. **按需更新**：被遮罩的部件都没显示时（比如只在某个表情里出现的部件），对应遮罩不再渲染，和官方渲染器一致；遮罩改为每次模型更新时只画一次，不再每个画面帧都画；看不见、也不当遮罩用的部件不再更新顶点；每帧按名字查节点改成开局建好按编号取。巢战另外用手动播放模式，自己控制模型更新频率（主页 60 次/秒、总部格 30 次/秒、不在屏幕上不更新）。

## 编译

```bash
git clone https://github.com/MizunagiKB/gd_cubism && cd gd_cubism && git checkout 3aaa3c9 && git submodule update --init
```

把 `CubismSdkForNative-5-r.5` 解压到 `thirdparty/`，应用补丁后用 VS 2022 + SCons 编译：

```bash
git apply <巢战仓库>/addons/gd_cubism/patches/chao-cubism-sdk-5-r.5.patch
py -m SCons platform=windows arch=x86_64 target=template_debug
py -m SCons platform=windows arch=x86_64 target=template_release
```

产物在 `demo/addons/gd_cubism/bin/`，复制两个 `.dll` 到这里的 `bin/`。着色器来自 `demo/addons/gd_cubism/res/shader/`。

## 许可

DLL 里静态链接了 Live2D Cubism Core，发布带它的安装包须遵守 Live2D Proprietary Software License；按 Live2D 的出版许可规定，营收达到门槛的发行方还需要另签出版许可。模型本身的许可另看模型作者。
