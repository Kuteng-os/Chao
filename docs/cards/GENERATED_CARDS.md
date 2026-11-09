# 衍生卡合同 · mechanics-8 / 客户端 0.8.6

本合同补充 CardSpec 的 `tokens`。制作入口为网页卡牌编辑器的“衍生卡”：先定义子卡，再在本牌或词条效果中引用其标识。子卡保存在母卡的冻结版本中，不会自动登记为独立收藏卡，不能直接组入牌组。

## 定义和预算

一个母卡共享最多 3 个扁平模板。每个模板必填 `token_id/name/unit_class/attack/health/keywords`；标识必须唯一。新增可选字段为 `kind/cost/operation_cost/abilities/play_target/counter_trigger/flavor_text`。旧模板默认 unit、费用1、行动费用1、无能力，不改变旧源定义与编译哈希。

单位的兵种必须合法，攻击0–20、防御1–20、行动费用0–4；所有衍生卡费用0–12。指令和反制必须明确 kind/cost，兵种null、攻击防御0、行动费0，至少有一个合法效果。反制必须有现有三类之一的 counter_trigger，只允许 on_reveal；指令只允许 on_play。内置突击/守护不能绑定非单位，符合类型的已登记模板词条可以绑定任何类型。

每个主体（母卡或子卡）展开词条后各最多4能力、每能力4操作、合计12操作；4个主体合计最多48操作。每个模板最多8个词条引用。所有引用必须存在，所有模板必须可从母卡效果直接或间接到达；草稿 Blueprint 暂时允许未引用模板，保存时严格检查。循环引用有界执行，触发整次行动预算时回滚，不保留部分结果。

## 创建与打出

```json
{"op":"create_card","token_id":"supply","amount":1,"player":"owner"}
```

amount 为1–3；player 为 owner/opponent。按张加入对应手牌，满10张时多余烧毁；不从牌组移除、不增加疲劳。加入手牌不触发登场或反制。随后支付该子卡自己的费用，单位部署后援线、指令执行登场能力、反制秘密伏置并按条件触发。对手看不到未打出的衍生手牌或反制内容。单位、指令、反制均沿用各自正常的目标与打出合法性规则。

```json
{"token_id":"supply","name":"紧急补给","kind":"order","cost":2,"operation_cost":0,"unit_class":null,"attack":0,"health":0,"keywords":[],"play_target":null,"abilities":[{"trigger":"on_play","effects":[{"op":"draw","player":"owner","amount":2}]}]}
```

示例中母卡的 tokens 包含该模板，母卡能力包含上述 create_card 即可。关键词模板可以用 summon/create_card，但独立词条不含 tokens 字段；绑定卡牌必须提供相同 token_id 的定义。模板效果数量可使用声明过范围的整数参数。

## 直接召唤

`summon` 保持单位限定，只召唤到己方支援线。每次1–2个（以 schema 为准），满场跳过。`summon_from_deck` 仍检索实际牌组的冻结卡牌，和创造副本是不同操作。

直接召唤不执行普通 on_play。会初始化自己永久的攻击次数、行动费用、伤害倍率、层数规则，并触发新的 on_summon；从手牌正常部署只执行 on_play。支援单位创建后的 on_summon 进入 FIFO 队列，当前根能力组完成后先处理阵亡队列，再处理召唤队列。每个队列能力结算中也遵守整次行动预算和胜负终止规则。

被召唤时可选择单位：能力组使用 `target:{side:"enemy"或"ally",row:"any"或"support"或"front"}`，组内效果使用 chosen。与阵亡选择一样由来源控制者确认，重复网络请求不重复结算；无合法目标跳过该组选定效果。登场 chosen 使用子卡自己的 play_target。

子卡有自己的名称、攻防、词条、行动费、回合和阵亡效果。`amount:{stat:"source_base_health"}` 读取子卡自己冻结的基础防御，不读取母卡。子卡效果可继续引用同一母卡的扁平模板库。直接召唤的衍生单位阵亡后消失；先加入手牌再正常部署的单位使用通常弃牌记录。

## 统计、兼容与模型

创建成功记录 create，烧牌记录 burn，生成卡打出/部署单列 generated_play/generated_deploy，不增加母卡普通 play/deploy 次数。子卡贡献按最初母卡版本归因，事件保留实际子卡名称和 generated_token_id。旧统计缺失的新字段按0处理。

DeepSeek 使用官方高思考模式，先正式复述、允许多轮修改，再生成结构。应分清“直接召唤”与“加入手牌”；要求不明确时提问。已有模板由 Blueprint 固定，不擅自覆盖。新增模板可由模型补全，但最终必须经过双端编译校验。仍不执行模型生成的任意脚本。

新模板字段/create_card/on_summon 要求客户端 build806；云端在入房前拦截旧客户端。局域网协议为 frontline-lan-5。原来仅基础属性与内置词条的模板保持兼容。

验证入口：`test_generated_cards.gd`、`generated_cards.test.js`、`test_faction_filter.gd`、`workshop_generated_browser.mjs`、`central_matches.test.js`、双端编译一致性与 Windows/Android touch_ui。

## 0.8.39 衍生卡独立卡图

图片为展示元数据，不写入 DSL，不影响定义与编译哈希。先经 `POST /v1/card-art` 上传，确认来源卡或提交修订时发送 `token_art_ids: {"token_id": "64位图片哈希"}`。此字段为完整映射：省略沿用旧版的存续模板卡图；空映射移除全部衍生图。引用必须属于本卡模板，图片必须已由当前账号上传或已公开。仍需来源卡作者或管理员权限。

版本记录以 `token_art` 保存图片 ID、尺寸；卡库中的独立衍生记录以 `art` 返回本身的图片，以 `token_art` 返回后续可生成模板的图片。图片修订会产生新版本，旧牌组和旧卡牌版本保留原图。移除独立卡图后使用阵营背景，不使用母卡的图片。

运行时和局域网/云端信封采用 `token_art_ids`。生成卡读取自己的 ID 并携带冻结模板映射，确保连续生成、召唤、返回手牌、复制和总部产生的衍生卡图片一致。对手手牌与伏置反制仍隐藏。此功能不改动允许加入牌组的许可。

验证：`derived_art839.test.js`、`test_derived_art839.gd`、`central_matches.test.js` 与 `workshop_art839_browser.mjs`。规则和联机协议仍为 mechanics-26 / LAN 26。
