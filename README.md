# 巢战

Godot 4.7 制作的自定义卡牌对战游戏。联机服务已停用，游戏内置完整卡库，可以单人练习和局域网直连。

## 玩家

- 下载：[GitHub Releases](https://github.com/xiangwu738-design/Chao/releases)，Windows 运行 exe，Android 安装 apk。0.9.10 起可以在“设置 → 关于”中直接更新。
- 查卡：[卡库网页](https://xiangwu738-design.github.io/Chao/)，可以搜索和筛选全部卡牌，只能查看。
- 制卡：游戏内“创作工坊”，校验通过后可保存到本地卡库并组牌试玩。
- AI 制卡：安装 [DSH 制卡插件](plugins/chao-cards/README.md)，用对话描述卡牌。
- 图形化制卡：安装 [DSH 做卡工坊插件](plugins/chao-card-studio/README.md)，在左侧栏填表、校验并提交。
- 提交：在“我做的卡”勾选卡牌，点击“打包提交”，把卡包文件夹上传到打开的 GitHub 页面。提交前请先用这些卡组牌试玩。
- 报错：校验失败时点击“把报错发到 Issue”；其他问题在设置 → 关于 → 反馈问题。

完整流程见 [卡牌提交与入库](docs/CARD_SUBMISSIONS.md)。

## 维护

```powershell
cd server; npm ci; cd ..
node tools/library/validate_catalog.mjs
godot --headless --path . --script tests/test_bundled_catalog.gd
```

卡库位于 `data/catalog.json`，推送到 `main` 后客户端启动时自动拉取；卡图、音效和表情位于 `data/art`、`data/sounds`、`data/emotes`，文件名为内容 SHA-256。`server/src` 仅保留给卡牌校验脚本使用，不需要部署。

卡牌规则见 [卡牌接入文档](docs/cards/CARD_INTEGRATION.md) 与 [机制支持表](docs/cards/MECHANICS_SUPPORT.md)。在线时期的说明保存在 [旧版 README](docs/README_0_9_6_ONLINE.md)。
