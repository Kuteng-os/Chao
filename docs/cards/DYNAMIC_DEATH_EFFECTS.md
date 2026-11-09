# 初始防御力与阵亡选目标

能力修订 `mechanics-10`，最低客户端 0.8.18（build 818）。旧卡牌定义和编译哈希不变，旧版本保留。

## 定义

```json
{"trigger":"on_death","target":{"side":"enemy","row":"any"},"effects":[{"op":"damage","target":"chosen","amount":{"stat":"source_base_health"}}]}
```

可以直接写入单位牌的 `abilities`，或登记模板词条的 `implementation.abilities`。没有登场选目标时卡牌 `play_target=null`；模板可使用空 `parameters={}`。完整模板见 [example_last_salvo.json](examples/keywords/example_last_salvo.json)。模型无需要求玩家填写伤害常数。

`damage`、`heal` 的 `amount` 新增白名单引用 `{"stat":"source_base_health"}`，只接受来源单位卡牌，读取本局冻结版本定义的 `health`，范围 1–20。当前血量、增益后的上限、伤害和阵亡不改变它。旧固定数值 1–10 及词条参数保持原意。其他属性、计算公式和任意脚本仍不支持。

`on_death` 的 `chosen` 必须和本能力组 `target` 配对；`side=ally/enemy` 相对来源控制者，`row=any/support/front`。默认在部署或召唤入场时从存活单位选择并绑定，不选总部；`timing: "trigger"` 才在每次触发时选择。技能不受守护和攻击射程影响。`own_turn_start/end` 同样支持能力组目标；`on_summon` 在召唤时选择，`on_play` 可使用组内目标或共享 `play_target`。

## 结算与联网

- 绑定目标跨阵线移动仍有效；离场即失效，同卡再次登场不会替代，目标效果跳过而无关效果继续。入场无目标时绑定为空，不自动绑定之后出现的单位。
- 来源控制者选择，即使当前是对手回合；选择期间暂停普通行动，可以投降。
- 同一能力组只选择一次，按顺序执行全部效果。目标被第一条效果消灭后，后续针对该目标的效果跳过，不重新选择。
- 没有合法目标时不弹出选择，跳过 `chosen` 操作，抽牌等其他操作照常继续。
- 多个阵亡能力按原有确定顺序逐组处理。全体同时阵亡先移除，再产生合法候选；总部死亡已决出胜负时停止效果链。
- 云端选择期限 30 秒；超时按稳定单位 ID 顺序选择第一项。断线暂停期间冻结期限，恢复后继续原有期限；断线裁定沿用原规则。单机与直连由控制者选择，AI 自动选择。
- 请求为 `{"type":"choose_target","choice_id":"序号-选择序号","target_uid":123}`，复用 `action_id`、`expected_state_seq` 幂等和过期校验；错误控制者、旧选择 ID、非法单位不能改变局面。
- 私有续算上下文不下发。引擎从冻结原行动和已确认选择确定性续算，随机种子、预算及已导出的统计前缀不变，不重复收费、抽牌、击杀统计；整个行动最多 64 次选择，仍受原操作预算约束。
- 新效果牌组开局要求双方客户端 build 至少 818，客户端通过 `X-Frontline-Client-Build` 声明；局域网协议更新为 `frontline-lan-10`。服务端始终使用已发布定义重新编译。

网页效果编辑器提供“数值来源 → 本卡初始防御力”，阵亡选定单位提供阵营和战线设置。生成候选仍需玩家确认后登记；升级前已生成的“不支持”结果不会自动重写，需重新生成。

回归：`tests/test_death_choices.gd`、`tests/run_mechanics_parity.mjs`、`server/test/central_matches.test.js`、`tests/workshop_death_browser.mjs`、`tests/touch_ui.gd`。
