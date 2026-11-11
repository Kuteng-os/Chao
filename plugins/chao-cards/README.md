# 巢战 AI 制卡插件（DeepSeek Harness）

用对话的方式设计卡牌：描述想要的效果，AI 追问细节、按游戏规则校验并自动修正，最后生成可以提交到 GitHub 的文件。

> 不想写对话？装 [做卡工坊](../chao-card-studio/README.md)，用表单填完卡牌，校验和提交走的是同一套规则。

## 安装

需要 [DSH Desktop](https://github.com/deepseek-ai/deepseek-harness) 0.2 版本和自己的 [DeepSeek API 密钥](https://platform.deepseek.com/api_keys)。密钥在 DSH 的“设置 → 模型”里填写，插件不接触密钥。

1. 打开 DSH Desktop，在应用菜单选择 **Manage dsh Command… → Install**，注册 `dsh` 命令。
2. 完全退出 DSH Desktop，然后打开一个**新的**终端，运行 `dsh --version` 确认命令可用。
3. 下载 `dsh-plugin-chao-cards-0.5.1.tgz`，放到以后不会移动的位置，在文件所在目录运行：

   ```bash
   dsh plugin --profile desktop add ./dsh-plugin-chao-cards-0.5.1.tgz
   ```

4. 重新打开 DSH Desktop。

### 更新插件

0.5.1 起，在 DSH 里说“更新插件”，AI 会检查 GitHub 上的新版本，确认后自动下载、校验并安装，重启 DSH Desktop 即可生效。AI 每次开始制卡时也会检查一次。

从更早的版本升级，或者不想通过 AI 操作时，在 PowerShell 里运行：

```powershell
irm https://raw.githubusercontent.com/xiangwu738-design/Chao/main/tools/update_plugin.ps1 | iex
```

安装包下载到 `%LOCALAPPDATA%ChaoCardsplugins`，请不要删除，DSH 会记住这个位置。

提示找不到 `dsh` 时，说明第 1 步没有完成，或者还在用注册之前打开的终端。看到缺少 peer 依赖的提示是正常的，这些包由 DSH 自身提供。DSH 还是开发者预览版，升级后插件可能需要更新。

### 可选：让 AI 直接提交

安装 GitHub CLI 并登录一次后，AI 可以替你创建 PR 和 Issue，校验失败时也能自己修改并更新 PR：

```bash
winget install GitHub.cli
```

```bash
gh auth login
```

登录信息由 `gh` 保管，插件读取不到。每次提交都会弹出确认框，拒绝就不会执行。没有安装 `gh` 时，AI 会给出链接，由你在浏览器里提交。

## 使用

在 DSH 里说“帮我做一张《巢战》的卡牌”，或调用 `chao-card-maker` 技能。完成后会得到：

- `submit_url`：打开后创建 Pull Request 完成提交。
- `game_preview_file`：在游戏“创作工坊 → JSON → 从文件读取”中打开，保存后可以组牌试玩。

文件保存在用户目录的 `巢战卡牌` 文件夹，可用环境变量 `CHAO_CARDS_OUTPUT` 修改。

实战试卡需要 Windows 版游戏 0.9.10 或更新版本（试用复生、充能等新机制需要 0.9.10），第一次试卡时 AI 会询问 `Frontline-*.exe` 的路径。

### 规则

- **必须通过程序校验。** 提交工具会重新校验，未通过时不会连接 GitHub。AI 用 `gh`、`git push` 或手写卡牌文件的方式提交巢战卡牌会被拦截。
- **基本信息必填。** 名称、署名、类型、数值、稀有度、阵营、罪孽都要有。确实没有罪孽时要明确选择“无罪孽”。
- **可以提交卡面。** 告诉 AI 图片路径即可，要求 PNG、不超过 2 MiB、边长不超过 1024。

### 修改旧牌

说“帮我修改《卡名》”。AI 会读取这张牌，改完后走同样的校验和提交流程。卡牌沿用原作者和原卡包，版本号加一，玩家牌组自动跟随新版本。只换卡面也可以。衍生卡要改来源卡。

### 审核和发布

有仓库写入权限的成员可以说“看看待审核的卡牌”。AI 会列出 PR、校验状态和卡牌内容，你指定通过哪个 PR 后，确认框通过即合并并发布给所有玩家。没有通过校验的 PR 不能合并。Issue 的处理不在插件范围内。

## 工具

| 工具 | 作用 |
|---|---|
| `chao_rules` | 分页读取制卡规则 |
| `chao_card_schema` | 查询卡牌和单个效果的结构 |
| `chao_catalog` | 查询词条、阵营和已有卡牌 |
| `chao_get_card` | 读取已有卡牌的完整定义，用于修改 |
| `chao_validate_card` | 按 PR 校验的同一套规则检查卡牌 |
| `chao_trial_card` | 在真实游戏引擎里试玩，返回逐步战报 |
| `chao_save_card` | 校验并保存，生成提交链接 |
| `chao_submit_pr` | 用玩家的 `gh` 登录创建 PR，需要确认 |
| `chao_pr_status` | 查询 PR 的校验结果和错误原因 |
| `chao_update_pr` | 把修改后的卡牌推送到自己的 PR，需要确认 |
| `chao_review_queue` | 列出待审核的 PR 和待发布的投稿，需要写入权限 |
| `chao_approve_pr` | 通过并合并校验通过的 PR，然后发布，需要确认和写入权限 |
| `chao_publish_inbox` | 发布已合并但未入库的投稿，需要确认和写入权限 |
| `chao_plugin_update` | 检查新版插件，确认后下载并安装 |
| `chao_report_issue` | 生成预填的 Issue 链接，也可确认后直接发布 |

## 维护

```bash
cd plugins/chao-cards
node build.mjs
npm pack
```

测试先运行 `node build.mjs`，再运行 `node --test test/rules.test.mjs`。

`build.mjs` 把校验代码、规则文档和卡库复制到 `runtime/`。游戏规则变化后要重新打包并发布新版插件；已有卡牌的变化由插件在线读取，不需要更新。
