# 指挥官角色

角色只改变形象，不影响规则。玩家在主界面「更换角色」或 设置 → 显示与场景 里选择；角色由维护者预制，玩家不能导入。

目前内置的角色：

| id | 角色 | 来源 |
| --- | --- | --- |
| `commander` | 指挥官（绘制的默认形象） | 巢战 |
| `deepseek` | 大肥鱼（DeepSeek-chan），Live2D | 原画及拆分：神宫凉子；Live2D 建模：霓虹猫_NeonNeko；神宫凉子免费配布模型，经作者同意随巢战发布。作者的使用须知见 `assets/characters/deepseek/模型使用须知.txt` |

没有选过角色的玩家默认使用大肥鱼（`CharacterCatalog.DEFAULT_CHOICE`）；对方没有某个角色时显示指挥官。

角色出现在三个地方，都按**半身**取景：

| 位置 | 取景名 | 说明 |
| --- | --- | --- |
| 主界面左侧 | `home` | 大幅半身像 |
| 对局总部格 | `hq` | 头肩特写，格子里只叠加血量；总部名称和效果在悬停提示和点击查看里。玩家可在 设置 → 显示与场景 → 角色 里关掉，关掉后总部格恢复为总部卡样式 |
| 胜负特写 | `stage` | 对局结束时角色移到桌面中央 |

## 目录

```
assets/characters/<id>/
  character.json
  portrait.png          立绘（半身），安卓和没有 Live2D 组件时显示
  model/xxx.model3.json Live2D 模型（可选）及其 moc3、贴图、动作、表情
```

`<id>` 只能用小写字母、数字、`-`、`_`，最长 32 个字符。联机时只传这个 id；对方没有这个角色就显示默认指挥官。

## character.json

```json
{
  "name": "角色名",
  "title_en": "English Name",
  "credits": "原画：……\n建模：……",
  "portrait": "portrait.png",
  "model": "model/xxx.model3.json",
  "framing": {
    "home":  {"zoom": 2.7, "focus": [0.5, 0.28]},
    "hq":    {"zoom": 4.0, "focus": [0.5, 0.22]},
    "stage": {"zoom": 2.8, "focus": [0.5, 0.27]}
  },
  "portrait_framing": {"hq": {"zoom": 1.2, "focus": [0.5, 0.56]}},
  "actions": {
    "idle":   {"motion": ["Idle", 0]},
    "play":   {"gesture": ["HandUp", 0], "release": ["HandDown", 0], "hold": 1.0},
    "attack": {"gesture": ["FingerOut", 0], "release": ["FingerBack", 0], "hold": 0.8},
    "turn":   {},
    "hit":    {"expression": "流冷汗", "hold": 2.0},
    "win":    {"expression": "爱心眼"},
    "lose":   {"expression": "流泪"}
  },
  "home": {
    "idle":       [{"gesture": ["GrassOut", 0], "release": ["GrassBack", 0], "hold": 4.0}, {"motion": ["Show", 0]}],
    "touch_head": [{"expression": "脸红", "hold": 2.5}, {"expression": "爱心眼", "hold": 2.5}],
    "touch_body": [{"gesture": ["HandUp", 0], "release": ["HandDown", 0], "hold": 1.5}, {"expression": "圈圈眼", "hold": 2.0}]
  }
}
```

- `title_en`：主界面公告栏显示的英文名，不写时用 `name`。`credits`：作者与来源，第二行显示在选择角色的卡片下方，全文显示在 设置 → 声音与动效 →「角色来源」。
- `zoom`：模型**画布**（或立绘）高度是画框高度的几倍；`focus`：画布上哪一点（0–1）对准画框中心。VTube Studio 一类的全身模型画布通常比人物高出不少，默认值按这种模型裁到头顶至腰部；人物在画布里的位置差别大时再单独写。
- `portrait_framing`：立绘和模型裁法不同时单独写；不写时立绘按半身像的默认值取景。
- 动作组名和序号、表情名都来自 `model3.json` 的 `Motions` / `Expressions`。VTube Studio 导出的模型通常没有登记这两项，需要补上。
- 一条动作可以组合下面几项：
  - `gesture` + `release` + `hold`：**叠加手势**。在待机动作上层播放 `gesture`，停在最后一帧 `hold` 秒，再用 `release` 收回。待机的呼吸、晃动不会中断，进出各有约 0.35 秒的过渡。适合 VTube Studio 里成对的"切出 / 切回"动画（举手 / 放下、拿出道具 / 收起）。不写 `release` 时，停住后直接淡回。
  - `motion`：**整段动作**。暂时替换待机动作，结束前约 0.6 秒和待机交叉淡化，不会先落回静止姿势。只写组名（如 `["TapBody"]`）时从组里随机挑一段，并且不和上一段重复。官方示例模型的 `TapBody` 就适合这样用。
  - `idle` 只写组名（如 `{"motion": ["Idle"]}`）时，待机会在组里几段之间轮换。
  - `expression` + `hold`：表情保持 `hold` 秒后淡出，淡出时间取表情文件的 `FadeOutTime`。
  - 手势进行中再来新的手势会被忽略（表情照常切换），所以频繁出牌时不会抽搐式地连续举手。
- `turn` 每回合都会触发，建议留空或只用很轻的表情。
- 时机：`play` 出牌，`attack` 攻击，`hit` 总部受到伤害，`turn` 回合开始，`win` / `lose` 对局结束。每次局面更新每方只做一个反应（受击 > 攻击 > 出牌 > 回合开始）。
- 没有 Live2D 时，这些时机用立绘的轻微位移、闪色代替。有 Live2D 时整个模型不再跳动，只有受击时轻微抖一下。

## VTube Studio 模型

模型带有作者的 `*.vtube.json` 时，在 character.json 里写 `"vtube": "xxx.vtube.json"`，角色就按作者的设置动：
- 主界面的鼠标当作面部追踪输入，按作者的参数映射（输入范围、输出范围、平滑）驱动。通常是 `AngleX/Y/Z`、`PositionX/Y/Z` 这类总控参数，所以头、身体、头发会一起动。
- 主界面鼠标停住 `tracking_lost_after` 秒（默认 20，写 -1 关闭）视为“追踪丢失”，平滑过渡到作者设的 `IdleAnimationWhenTrackingLost`，鼠标一动就回来。这段动画常被作者做成“掉线”梗，所以总部格和胜负特写里不播，只播普通待机并保持正面。
- 呼吸只驱动作者打开了自动呼吸的参数。
- `gesture` / `release` / `expression` 可以直接写作者的快捷键名，例如 `"gesture": "抚胸手打开", "release": "抚胸手关闭"`、`"expression": "屑"`。
- 有这份配置时，不再叠加下面“全身动态”里的程序化动作。表情仍需登记在 `model3.json` 的 `Expressions` 里，名字用表情文件名（不含 `.exp3.json`）。

## 主界面互动

- **全身动态**：模型在自身动作之上，还会叠加几层程序化的动作，用的都是标准参数（`ParamAngleX/Y/Z`、`ParamBodyAngleX/Y/Z`、`ParamEyeBallX/Y`）。缺少的参数会自动跳过。
  - 视线：眼睛最快、头其次、身体最慢，跟着鼠标转。眼睛还会有细小的跳动（扫视）。
  - 环顾：鼠标停住 3.5 秒后，角色会自己四处看看，常常又看回玩家。
  - 晃动：缓慢的歪头和身体侧倾一直在进行。这一层在对局总部格和胜负特写里也有。
  - 点击时身体会被轻推一下。
- **闲置动作**：玩家 14–26 秒没有点击或按键时，从 `home.idle` 里随机播放一个。
- **点击互动**：模型在 `model3.json` 里登记了 `HitAreas`（名字含 Head / Body）时，按触摸区域判断，点在区域外不反应；没有登记时，点画框上部 42% 算头。点头播放 `home.touch_head`，点身体播放 `home.touch_body`，连续点击不会重复同一条。
- 对局里出牌、攻击、回合开始的动作不会打断还没播完的动作；受击和胜负会打断。
- 每条的写法和 `actions` 相同。不写 `home` 时，闲置用 `turn` / `play`，摸头用 `turn`，点身体用 `play` / `attack`。

## Live2D 组件

Live2D 由 [GDCubism](https://github.com/MizunagiKB/gd_cubism)（非官方 GDExtension）绘制，放在 `addons/gd_cubism/`。它需要用 Live2D 官方的 Cubism SDK for Native 编译，SDK 须由维护者本人在 Live2D 官网同意许可后下载。没有这个组件时游戏照常运行，只显示立绘。目前只编译 Windows 版；编译方法和巢战加的补丁（适配 SDK 5-r.5、绘制顺序、遮罩性能）见 `addons/gd_cubism/README.md`。

一个模型每帧的更新开销约 7 ms（测试模型 764 块网格、49 个遮罩）。对局里同时动的通常只有双方总部两个。

模型的使用许可以模型作者为准：不允许再分发的模型不能放进仓库或安装包，除非取得作者同意（大肥鱼即如此）。安卓版不打包 `model/` 文件夹（`export_presets.cfg` 的 exclude_filter），只带立绘。

## 本地测试

调试版会额外读取环境变量 `CHAO_CHARACTER_DIR` 指向的文件夹（结构同上，`model` / `portrait` 也可以写绝对路径），用来测试不能提交的模型。正式导出的版本不读这个变量。
