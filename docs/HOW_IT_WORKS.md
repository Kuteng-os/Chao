# 巢战运作说明

联机服务器已停用。现在的巢战由三部分组成：装在玩家电脑或手机上的**游戏客户端**、存放卡库和接收投稿的 **GitHub 仓库**，以及可选的 **DSH 制卡插件**。

```mermaid
flowchart TD
    A[玩家做卡<br>游戏内表单 / JSON<br>或 DSH 插件] --> B{本地校验}
    B -- 失败 --> C[修改，或发 Issue 反馈]
    B -- 通过 --> D[创建 Pull Request<br>文件进入 submissions/inbox]
    D --> E{GitHub Actions 校验}
    E -- 失败 --> F[自动开 Issue，并在 PR 留言]
    F -- 玩家修改后重新推送 --> E
    E -- 通过 --> G[维护者审核并合并 PR]
    G --> H[维护者运行 add_card 入库<br>写入 data/catalog.json]
    H --> I[git push 到 main]
    I --> J[玩家下次启动游戏<br>后台拉取新卡库]
```

## 一、游戏客户端

### 卡库从哪里来

| 来源 | 内容 | 使用时机 |
|---|---|---|
| 游戏包内 `data/` | 完整卡库、卡图、音效、表情 | 启动时安装，没有网络也能用 |
| GitHub `main` 分支 | 最新的 `data/catalog.json` | 启动后在后台拉取 |
| 本地档案 | 已安装的卡库、牌组和玩家自己做的卡 | 一直保留 |

### 启动时发生什么

1. 读取游戏包里的卡库并安装。首次启动会校验全部卡牌，之后只处理有变化的部分。
2. 进入游戏后，在后台请求 GitHub 上的卡库，不阻塞界面。
3. 进入卡库页时也会尝试更新，但最多 5 分钟检查一次。文件没变时 GitHub 返回 304，不会重复下载。

### 卡库更新的保护

- **版本号：** 每次入库，`catalog_version` 自动加一。客户端只接受比当前更高的版本，所以重启或读到 CDN 旧缓存都不会回退。
- **逐张校验：** 变化的卡牌都要核对指纹并重新编译。有一张不通过就整批放弃，继续用当前卡库。
- **网络失败：** 不影响游戏，静默保留现有卡库。

### 媒体文件

卡图和音效的文件名就是内容的 SHA-256。查找顺序是：游戏包 → 本地缓存 → 从 GitHub 下载。下载后必须核对哈希才会使用并缓存。表情不随卡库更新，改动表情需要发新客户端。

### 已停用的功能

在线对战、账号、共享牌组、战局统计、网页工坊和客户端自动更新。单人练习和局域网直连继续可用。新版本需要到 GitHub Releases 下载。

## 二、玩家如何做卡

| 方式 | 适合 | 需要 |
|---|---|---|
| 游戏内表单 | 已有词条加简单效果组合 | 只要游戏 |
| 游戏内 JSON | 手写复杂效果 | 只要游戏 |
| DSH 插件 | 用自然语言描述卡牌，AI 代写 | DSH Desktop 和自己的 DeepSeek 密钥 |

三种方式生成的是同一种卡牌定义（CardSpec），校验规则也相同。新词条不能由玩家自行创建，需要时发 Issue。

## 三、提交与校验

### 提交

玩家点击“提交”后，浏览器打开 GitHub 新建文件页，文件名和内容已经填好。玩家选择 Propose changes 并创建 PR，需要有 GitHub 账号。内容太长无法放进链接时，游戏会把内容复制到剪贴板，由玩家粘贴。

提交文件是 `submissions/inbox/card-<哈希前12位>.card.json`。想带卡图时，把同名 `.png` 上传到同一个 PR。

### PR 自动校验

工作流 `.github/workflows/validate-submission.yml` 在 PR 改动 `submissions/inbox/` 时运行，检查：

- 只改动了允许的路径，文件名符合规则。
- 卡牌能按游戏规则编译，内容哈希一致。
- 阵营存在，引用的媒体存在，卡库里没有完全相同的卡。
- 卡图是 PNG，不超过 2 MiB，边长不超过 1024。

失败时自动创建 `[报错] 卡牌提交 #<PR> 校验失败` Issue。玩家修改后重新校验，通过后 Issue 自动关闭。

**安全边界：** 工作流需要创建 Issue 的权限，因此使用 `pull_request_target`，只运行主分支上的代码。PR 里的文件只作为数据下载，不会被执行。

### 报错入口

| 场景 | 去向 |
|---|---|
| 游戏内校验失败 | 点击“把报错发到 Issue”，错误和卡牌自动填入 |
| 其他问题或需要新机制 | 设置 → 关于 → 反馈问题 |
| PR 校验失败 | 自动开 Issue |
| DSH 插件反复失败或机制不支持 | AI 生成预填的 Issue 链接，由玩家提交 |

## 四、维护者入库

校验通过的 PR 需要你审核并合并。合并后卡牌还没有进入游戏，还要执行：

```bash
git pull
cd server && npm ci && cd ..
node tools/library/add_card.mjs submissions/inbox/card-xxxxxxxxxxxx.card.json --dry-run
node tools/library/add_card.mjs submissions/inbox/card-xxxxxxxxxxxx.card.json
node tools/library/validate_catalog.mjs
git add -A
git commit -m "收录新卡"
git push
```

`add_card` 会写入 `data/catalog.json`、把卡图放进 `data/art/`、更新版本号，并把投稿文件移到 `submissions/accepted/`。推送后玩家下次启动就能拿到。

- 修改已有卡牌：加 `--replace <card_id>`。
- 指定卡包：加 `--series <编号>`。
- 不要手工编辑 `data/catalog.json`，指纹由脚本维护。

**只有新增规则或机制时才需要发新客户端。** 旧客户端校验不了新卡时，会保留当前卡库。

## 五、DSH 制卡插件

插件位于 `plugins/chao-cards`，运行在 DeepSeek Harness 里。DSH 负责密钥、模型和对话，插件提供一个技能和一组工具，密钥不经过插件。

```mermaid
sequenceDiagram
    participant 玩家
    participant AI as DSH 中的 AI
    participant 插件
    participant 游戏 as Frontline.exe
    玩家->>AI: 描述卡牌
    AI->>玩家: 追问缺少的细节
    AI->>插件: 读规则，查词条和阵营
    AI->>插件: 校验卡牌
    插件-->>AI: 错误路径和原因
    AI->>插件: 修改后实战试卡
    插件->>游戏: 无界面运行
    游戏-->>插件: 逐步战报
    插件-->>AI: 战报
    AI->>玩家: 展示规则和试卡结果，请求确认
    玩家->>AI: 确认并提供署名
    AI->>插件: 保存
    插件-->>玩家: 弹出确认框，创建 PR
    AI->>插件: 读取校验结果，失败时修改并更新 PR
```

| 工具 | 作用 |
|---|---|
| `chao_rules` | 分页读取制卡规则 |
| `chao_card_schema` | 查询卡牌和单个效果的结构 |
| `chao_catalog` | 查询词条、阵营和已有卡牌 |
| `chao_validate_card` | 按 PR 校验的同一套规则检查 |
| `chao_trial_card` | 在真实游戏引擎里试玩 |
| `chao_save_card` | 校验并保存，生成提交链接 |
| `chao_submit_pr` | 用玩家的 `gh` 登录创建 PR，需要确认 |
| `chao_pr_status` | 查询 PR 的校验结果和错误原因 |
| `chao_update_pr` | 把修改后的卡牌推送到自己的 PR，需要确认 |
| `chao_report_issue` | 生成预填的 Issue 链接，也可确认后直接发布 |

玩家安装并登录 GitHub CLI 后，AI 可以直接创建 PR 和 Issue，每次都会弹出确认框。没有 `gh` 时退回提交链接，由玩家在浏览器里完成。

文件保存在用户目录的 `巢战卡牌` 文件夹：

- `card-xxx.card.json`：用于提交。
- `card-xxx.preview.json`：在游戏“创作工坊 → JSON → 从文件读取”中打开试玩。

规则校验代码和规则文档都打包在插件里。卡牌数据优先在线读取最新版，连不上时用插件自带的版本。游戏规则变化后需要重新打包插件，见 [插件说明](../plugins/chao-cards/README.md)。

## 六、实战试卡

规则校验只能确认卡牌合法，实战试卡用来确认效果对不对。插件在后台启动游戏，不开窗口：

```text
Frontline-0.9.8.exe --headless -- --card-trial=<任务文件> --card-trial-out=<结果文件>
```

游戏用真实的战斗引擎搭局面，把卡放进手牌，再按卡牌类型执行：

| 类型 | 默认流程 |
|---|---|
| 单位 | 打出 → 过回合 → 推进 → 攻击 → 主动能力 → 过回合 → 被消灭 |
| 指令、场地 | 打出 → 过两个回合 |
| 反制 | 伏置 → 对手行动 → 过回合 |
| 总部 | 作为总部开局，过两个回合 |

每一步返回动作状态、战斗日志、双方总部血量、指挥点、手牌和场上单位。当前局面下不合法的动作标记为 `skipped`，不算失败。

AI 可以通过 `scenario` 调整局面，测试条件效果：

| 字段 | 含义 |
|---|---|
| `my_units`、`enemy_units` | 双方初始单位 |
| `credits` | 我方指挥点 |
| `actions` | 自定义步骤：`play`、`move`、`attack`、`activate`、`end_turn`、`enemy_ai`、`kill` |
| `target_index`、`attack_target_index`、`activate_index` | 选择第几个目标或能力 |
| `choices` | 依次回答效果中的选择 |

试卡需要 Windows 版 0.9.8 或更新版本。第一次使用时，AI 会询问 `Frontline-*.exe` 的路径，之后会记住。安卓版不支持。

## 七、发布新版本

| 改动 | 需要做什么 |
|---|---|
| 新卡、修改卡牌、新卡图 | `add_card` 后 `git push`，玩家自动更新 |
| 新规则、新机制、新表情、界面改动 | 导出新客户端，上传到 GitHub Releases |
| 规则变化且要用 AI 制卡 | 再运行 `node build.mjs` 和 `npm pack`，发布新版插件 |

安卓包使用 `交付/chao-android-release.keystore` 签名，这个文件和同目录的密码文件不在仓库里，请离线备份。丢失后玩家将无法覆盖升级。

## 八、目录速查

| 路径 | 内容 |
|---|---|
| `data/` | 内置卡库和媒体 |
| `submissions/inbox/` | 待入库的投稿 |
| `submissions/accepted/` | 已入库的投稿 |
| `tools/library/` | 入库和校验脚本 |
| `.github/` | PR 校验工作流和 Issue 模板 |
| `plugins/chao-cards/` | DSH 制卡插件 |
| `scripts/core/card_trial.gd` | 实战试卡 |
| `server/src/` | 仅保留给校验脚本使用，不需要部署 |
