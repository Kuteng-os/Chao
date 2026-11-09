# 巢战 AI 制卡插件（DeepSeek Harness）

用对话的方式设计卡牌：描述想要的效果，AI 追问细节、按游戏规则校验并自动修正，最后生成可以提交到 GitHub 的文件。

## 安装

需要 [DSH Desktop](https://github.com/deepseek-ai/deepseek-harness) 0.2 版本和自己的 [DeepSeek API 密钥](https://platform.deepseek.com/api_keys)。密钥在 DSH 的“设置 → 模型”里填写，插件不接触密钥。

1. 启动一次 DSH Desktop，然后完全退出。
2. 下载 `dsh-plugin-chao-cards-0.2.0.tgz`，在文件所在目录运行：

   ```bash
   dsh plugin --profile desktop add ./dsh-plugin-chao-cards-0.2.0.tgz
   ```

3. 重新打开 DSH Desktop。

看到缺少 peer 依赖的提示是正常的，这些包由 DSH 自身提供。DSH 还是开发者预览版，升级后插件可能需要更新。

## 使用

在 DSH 里说“帮我做一张《巢战》的卡牌”，或调用 `chao-card-maker` 技能。完成后会得到：

- `submit_url`：打开后创建 Pull Request 完成提交。
- `game_preview_file`：在游戏“创作工坊 → JSON → 从文件读取”中打开，保存后可以组牌试玩。

文件保存在用户目录的 `巢战卡牌` 文件夹，可用环境变量 `CHAO_CARDS_OUTPUT` 修改。

实战试卡需要 Windows 版游戏 0.9.8 或更新版本，第一次试卡时 AI 会询问 `Frontline-*.exe` 的路径。

## 工具

| 工具 | 作用 |
|---|---|
| `chao_rules` | 分页读取制卡规则 |
| `chao_card_schema` | 查询卡牌和单个效果的结构 |
| `chao_catalog` | 查询词条、阵营和已有卡牌 |
| `chao_validate_card` | 按 PR 校验的同一套规则检查卡牌 |
| `chao_trial_card` | 在真实游戏引擎里试玩，返回逐步战报 |
| `chao_save_card` | 校验并保存，生成提交链接 |
| `chao_report_issue` | 生成预填的 Issue 链接 |

## 维护

```bash
cd plugins/chao-cards
node build.mjs
npm pack
```

`build.mjs` 把校验代码、规则文档和卡库复制到 `runtime/`。游戏规则变化后要重新打包并发布新版插件；已有卡牌的变化由插件在线读取，不需要更新。
