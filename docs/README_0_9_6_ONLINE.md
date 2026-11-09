# 巢战 0.9.5

当前正式版：Windows [Frontline-0.9.5.exe](build/Frontline-0.9.5.exe)，Android [Frontline-0.9.5.apk](build/Frontline-0.9.5.apk)。旧客户端可安装累计资源补丁后重启，账号与本地牌组保留。

本版修复 CZ-000284：单位可以在己方回合主动发动一次能力，并选择友方可进化单位立即完成其自身进化。电脑右键、手机长按单位，在详情中发动。网页编辑与生成助手同步支持；原有卡牌不自动改写。联机双方需更新至0.9.5，详见 [发布说明](docs/RELEASE_0_9_5.md)。正式源码位于 `.runtime/release0905`；根目录仍含未发布工作，不应直接导出发布。

以下为早期版本功能与开发说明，历史安装包路径仅作记录。

## 0.8.1 安卓、战局统计与补丁更新

Windows 使用 `build/Frontline-0.8.1.exe`；Android 安装 `build/Frontline-0.8.1.apk`。同一账号登录两端，昵称、头像、个人档案和服务器对局记录共用。全服卡牌版本统计公开，个人对局明细仅对参赛双方开放。

游戏启动时检查签名更新，设置中也可手动检查。一般更新仅下载累计资源补丁，重启生效；首次从 0.7.0 升级需安装一次 0.8.1 基础版。统计从本版发布后的服务器对局开始记录。具体统计口径、Android 构建和补丁发布见 [0.8.1 说明](docs/ANDROID_STATS_UPDATES_0_8_1.md)。

# 当前制作入口

阵营创建、卡牌、词条、DeepSeek 效果组合、可选卡面上传与 JSON 编辑已迁至[网页工坊](https://wzb.rainplay.cn:52371/workshop/)。启动 `build/Frontline-0.8.1.exe`，点击“打开网页工坊”沿用游戏身份。阵营规则见 [0.7.0 说明](docs/FACTIONS_0_7_0.md)。拖拽组牌、本地保存与共享见 [0.6.0 说明](docs/DECKS_AND_ART_0_6_0.md)。

# 巢战

一个使用 Godot 制作的自定义卡牌对战游戏：军事桌面界面、总部与前线战斗、卡牌工坊、单人 AI 演练、公网权威服务器对战，以及双人局域网直连。

**初始卡库为空。** 卡牌由玩家手工编辑、导入 JSON，或通过 DeepSeek 官方 API 理解描述后生成。模型可以继续询问细节；新词条独立登记，玩家确认后通过自动校验，卡牌还需单独预览并确认导入。项目不包含 KARDS 的卡池、原版素材或全部机制。

## 在 Windows 启动

双击 **`start.cmd`**，或直接运行 **`build/Frontline-0.8.1.exe`**。导出程序包含运行时，不需要安装 Godot 或 Node；从源码运行需要 Godot 4.7。更新时先保存并关闭旧客户端，再打开新版；玩家档案保留。

默认连接 **`https://wzb.rainplay.cn:36410`**。在“设置”注册或登录账号，无需邀请码；已有旧玩家身份可以绑定账号。网站与游戏共用身份，不需要 DeepSeek 密钥。令牌保存在自己的本地档案中，不能放进公共客户端包。

`start-game.ps1` 默认只启动游戏。开发本机服务时使用 `-LocalServer`（服务和游戏）或 `-ServerOnly`（仅服务），需要 Node.js 22 及 `server/.env`；本机服务默认 `http://127.0.0.1:8787`，可在设置中切换。`-GodotPath` 可指定源码运行所用 Godot。部署配置、备份与证书续签见 [服务器维护文档](docs/DEPLOYMENT.md)。

## 卡牌与词条

1. 在“卡牌工坊 → 制作卡牌”填写名称、兵种、部署费、行动费、攻击和防御。
2. 选择已有词条，填写词条参数；也可在“效果组合”添加“抽 X 张牌”、总部回复、总部伤害或指挥点，并选择触发时机。普通卡牌直接点击“校验并预览”，不调用模型。
3. 若有附加能力，填写“其他机制”。DeepSeek 只完善效果和词条；基础数值、已选词条和已有的效果组合冻结，不由模型重写。细节不足时继续问答。
4. 新词条在“词条图鉴”单独澄清、确认和校验登记，之后可反复用于卡牌。
5. 卡牌预览确认归档后同步到共享卡库。草稿和创作原文不公开。离线制作的牌会保留并在连接后同步。
6. 在“收藏与牌组”拖入 **40 张牌（不含总部）**；同名卡/同一卡牌的多个版本合并计算上限：普通 4、限定 3、特殊 2、精英 1。可命名保存到本地，或上传供其他玩家选用。

高级编辑和 JSON 导入仍可用。模型输出是经过校验的规则数据，游戏不执行模型返回的脚本。DeepSeek 官方模型通过服务器配置；已部署模型为 `deepseek-flash`。

当前新增支持每回合多次攻击、直接消灭单位、调整场上单位行动费用；可通过词条或“其他机制”使用。支持边界、组合语义与后续机制的分批路线见 [常见机制支持表](docs/cards/MECHANICS_SUPPORT.md)。常用效果组合界面仍保持精简。

## 对战

在“战斗 → 在线对战”创建房间，把 **六位房间号** 给对手。双方使用各自已同步的牌组；服务器从自己的卡库加载规则、执行 Godot 战斗引擎并发送各自可见的局面。客户端不能自行提交卡牌定义或裁定结果。

支持短暂断线恢复：持续离线会暂停对局，超过恢复期限按规则结束。当前房间保存在内存中，服务重启会中止在途对局；已归档卡牌、词条和身份会持久保存。暂未提供自动匹配和排行；跨设备可用同一账号登录，忘记密码可由管理员重置。

“镜像练习”使用自己的牌组与电脑对战。“局域网直连”保留旧房主模式，默认 UDP **24567**，填写房主 IP 加入。完整实现及限制见 [联网说明](docs/NETWORK_IMPLEMENTATION.md)。

对局中可拖动手牌到支援线部署、拖动单位到前线推进或敌军目标攻击，也支持点击操作。总部位于双方支援阵线中央，初始 20 生命；回合开始增加并刷新资源，最多 12 点。卡面可以在网站上传，也可留空；规则从右上角菜单查看。

## 测试与开发

后端测试不访问真实 DeepSeek API。设置 `GODOT_BIN` 后还会执行真实 Godot 子进程的云对局测试：

```powershell
Set-Location server
npm test
```

从项目根目录，用实际 Godot 可执行文件路径运行：

```powershell
$godot = 'C:\Tools\Godot\Godot_v4.7-stable_win64.exe'
& $godot --headless --path . --editor --import | Out-Host
& $godot --headless --path . --script tests/test_engine.gd | Out-Host
& $godot --headless --path . --script tests/test_network.gd -- --role=unit | Out-Host
& $godot --headless --path . --script tests/test_ui.gd | Out-Host
& $godot --headless --path . --script tests/test_creator.gd | Out-Host
.\tests\run_service_bridge.ps1 -GodotPath $godot
```

双进程 ENet 测试、实现范围、文件布局和存储说明见 [实现与验收说明](docs/IMPLEMENTATION.md)。测试临时卡牌只存在于测试环境，不会加入玩家初始卡库。

## 给开发 agent 的接入文档

原始契约文档继续作为扩展规则的依据；其中“待实现”历史表述应结合 [当前实现说明](docs/IMPLEMENTATION.md) 阅读，不代表下表每项生产要求均已完成。

| 文档 | 内容 |
| --- | --- |
| [卡牌接入主文档](docs/cards/CARD_INTEGRATION.md) | DSL、解释器语义、生成流程、冻结与 API 合同 |
| [基础配置与 AI 机制分工](docs/cards/CARD_BLUEPRINT.md) | 玩家填写数值、选择词条，模型只完善附加机制；Blueprint 请求合同 |
| [常见机制支持范围](docs/cards/MECHANICS_SUPPORT.md) | 实际能力、未实现清单、组合边界与分批扩展顺序 |
| [卡牌 Schema](docs/cards/card.schema.json) / [模型输出 Schema](docs/cards/generation.schema.json) | 卡牌结构与四种生成结果 |
| [独立词条登记](docs/cards/KEYWORD_REGISTRY.md) | 提案、澄清、确认、参数与版本 |
| [词条 Schema](docs/cards/keyword.schema.json) / [词条生成 Schema](docs/cards/keyword-generation.schema.json) | 独立定义及模型候选结构 |
| [模型提示词](docs/cards/COMPILER_PROMPT.md) | 由服务端组装的编译协议 |
| [生产联网协议设计](docs/cards/NETWORK_PROTOCOL.md) | 后续 `net-1` 协议目标；当前为 `cloud-1` 与 LAN 协议 |
| [53 项验收设计](docs/cards/ACCEPTANCE_TESTS.md) | 完整接入的目标用例，不能等同于本版全部通过 |
| [契约测试夹具](docs/cards/examples/) | 结构、编码与编译哈希测试数据 |

## 账号

游戏设置和网页工坊支持账号登录、开放注册、改密码及旧身份绑定。四个管理员的权限与接口见 [账号系统](docs/ACCOUNTS.md)。当前客户端为 `build/Frontline-0.8.1.exe`，启动脚本优先使用此版本。
