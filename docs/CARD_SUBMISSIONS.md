# 卡牌提交与入库

联机服务已停用。卡牌由玩家在本地制作，经 GitHub 提交，维护者确认后并入内置卡库，随新版本发布。

## 玩家

0.10 起所有卡牌都以**卡包**提交：一个卡包 1 至 20 张卡，作为一个 Pull Request，整包一起审核、一起入库。单张卡就是只有一张卡的卡包。

1. 打开游戏的“创作工坊”，用表单或 JSON 制作卡牌，点击“校验并预览”，然后“保存到本地卡库”。
2. 用这些卡组一副牌，实际打几局，确认效果符合预期。
3. 在右侧“我做的卡”勾选要提交的卡，点击“打包提交”，填写卡包名称和简介。每张卡可以选一张 PNG 卡面（不超过 2 MiB，边长不超过 1024）。勾选“我已经用这些卡组牌试玩过”后生成卡包。
4. 游戏会打开卡包文件夹和 GitHub 上传页面。登录后把文件夹里的全部文件拖进网页，选择 Propose changes，再创建 Pull Request。
5. 别人的卡包也可以用“导入卡包”导入本地卡库，组牌试玩后再审核。

手机端会复制卡包内容并打开 GitHub 新建文件页，卡面需要在电脑上补充。

需要 GitHub 账号，游戏不保存任何 GitHub 凭据。

## 用 AI 制卡

想用自然语言描述卡牌时，安装 [DSH 制卡插件](../plugins/chao-cards/README.md)。AI 会追问细节并按同一套规则校验，打包、试玩和提交走上面相同的卡包流程。不想安装插件也可以继续使用游戏内的表单和 JSON。

## 报错

- 游戏内校验失败：点击“把报错发到 Issue”，错误和卡牌 JSON 会自动填入 Issue。
- 需要新机制或发现其他问题：设置 → 关于 → 反馈问题。
- PR 校验失败：GitHub Actions 自动创建 `[报错] 卡牌提交 #<PR> 校验失败` Issue，并在 PR 下留言。玩家修改后再次推送会自动复查，通过后 Issue 自动关闭。

## 维护者入库

PR 校验通过并合并后，用一键入库最省事：

```bash
node tools/library/sync_inbox.mjs
```

先加 `--dry-run` 可以只预览，加 `--all` 不逐张询问，推送前都会再确认。需要单独处理某张卡时：

```bash
git pull
cd server && npm ci && cd ..
node tools/library/add_card.mjs submissions/inbox/pack-xxxxxxxxxxxx.pack.json --dry-run
node tools/library/add_card.mjs submissions/inbox/pack-xxxxxxxxxxxx.pack.json
node tools/library/validate_catalog.mjs
```

- 卡包整包入库：任何一张卡校验失败，整包都不入库。
- 修改已有卡牌：卡包里带 `replaces` 字段的卡自动替换那张牌；旧的单卡文件手动处理时可追加 `--replace <card_id>`。版本号自动加一，原作者、卡包和登记时间保持不变，衍生卡同步更新。
- 指定卡包：追加 `--series <编号>`。
- 卡包的卡面 `pack-<卡包哈希>-<卡牌哈希>.png` 放在同目录时会自动入库。

入库后文件移到 `submissions/accepted/`，卡牌写入 `data/catalog.json`，卡库版本号自动加一。

把改动 `git push` 到 `main` 后，玩家下次启动游戏会自动拉取新卡库，新卡的卡图和音效按需下载并核对哈希。只有新增规则或机制时才需要导出新客户端并发布到 GitHub Releases；旧客户端校验不了新卡时会保留当前卡库。

拉取失败不影响游戏，继续使用已安装的卡库。表情不随卡库更新，需要发新客户端。

`data/catalog.json` 每张卡一行，指纹由脚本维护，不要手工编辑。

## 投稿格式

卡包文件 `submissions/inbox/pack-<哈希前12位>.pack.json`，哈希是按顺序排列的各卡 `definition_hash` 数组的 SHA-256（规范化 JSON）：

| 字段 | 说明 |
|---|---|
| `format` | 固定为 `chao-card-pack-v1` |
| `game_version` | 来源，游戏版本号或 `dsh-plugin-<版本>` |
| `author` | 署名，1 至 64 个字符 |
| `name` | 卡包名称，1 至 32 个字符 |
| `description` | 可选，卡包简介，最多 300 个字符 |
| `cards` | 1 至 20 项，每项为 `{definition, definition_hash, replaces?}` |

`replaces` 为 `{"card_id":…,"revision":…}`，表示修改这张牌的这个版本；卡牌已有更新版本时校验失败。卡包内不能有相同的卡、重名的卡或同一张旧牌被改两次。

卡面 `pack-<卡包哈希前12位>-<卡牌哈希前12位>.png`，不属于卡包里任何一张卡的 PNG 会被拒绝。

0.9.x 时期的单卡文件 `card-<哈希>.card.json` 仍然能被校验和入库，但游戏和插件不再生成。

所有投稿都要有名称和稀有度。DSH 插件的投稿还必须有阵营，并明确写出罪孽（没有时为 `null`）。游戏内表单保留“无阵营”“无罪孽”选项。

## 安全边界

校验工作流使用 `pull_request_target` 以获得创建 Issue 的权限，因此只运行主分支的代码。PR 里的文件只通过 API 下载为数据，路径必须是 `submissions/inbox/` 下的卡包文件、卡包卡面或旧的单卡文件，其他路径会被拒绝。
