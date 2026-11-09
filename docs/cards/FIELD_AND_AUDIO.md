# 场地卡与卡牌音效（mechanics-12 / 0.8.22）

卡牌、独立词条、客户端和权威服务器使用同一规则。所有修改保留卡牌修订，旧版定义不自动改写。

## 场地

`kind: "field"`，`appearance.emblem: "field"`，显示三角形。`unit_class: null`，攻击、防御和行动费均为 0；部署费照常支付。场地可以编入牌组，也可以通过 `create_card` 生成到手牌，不能用 `summon` 直接召唤。

双方共用一个场地位置，不占任何阵线单位格，不是可攻击单位，也不计入在场单位数。任何一方打出新场地，旧场地入弃牌堆，新场地控制者更新。此操作不触发单位登场或敌方打出指令的反制。

支持时机：`on_play`、`own_turn_start`、`own_turn_end`、`opponent_turn_start`、`opponent_turn_end`、`while_active`。己方、敌方始终相对于当前场地控制者。场地不触发阵亡或被召唤效果。登场选定目标沿用 `play_target`；回合效果的选定目标必须使用能力组 `target`，且 `timing: "trigger"`。

`while_active` 是持续加成，不会每回合叠加。支持固定整数或词条参数的 `modify_stats`、`modify_operation_cost`、`modify_stacks`（重甲），目标为 `all_friendly_units` / `all_enemy_units`，`duration: "battle"`。入场前后的单位都适用；替换时立即取消旧场地加成并应用新场地加成，保留单位已受伤害。因此失去生命上限加成可能使单位阵亡。重甲最终限制为 0–10，攻防 0–30，行动费 0–4。

登场或回合触发中的普通修改仍按所选持续时间执行，不随场地退出自动撤销；需随场地结束的效果应写成 `while_active`。任意条件光环、计数型持续公式、持续抽牌/伤害不属于本次支持范围；抽牌、伤害等使用登场或回合时机。

```json
{"trigger":"while_active","effects":[{"op":"modify_stats","target":"all_friendly_units","attack_delta":1,"health_delta":0,"duration":"battle"}]}
```

## 媒体

卡牌与衍生模板可选填 `media`；此对象属于冻结定义，会进入定义和程序哈希。只接受本服务器上传得到的 SHA-256 ID，不接受任意网址、本地路径或可执行资源。

```json
{"media":{"sounds":{"play":"上传所得的64位SHA256"},"background":"图片SHA256","music":"音频SHA256"}}
```

`sounds` 可独立配置 `select`（选择）、`draw`（进入己方手牌）、`play`（部署/公开出牌，反制揭示时）、`attack`、`move`、`damage`（该牌受伤）、`heal`（该牌被治疗）、`death`、`trigger`。触发效果音未设置时沿用原本的安静处理，其他事件沿用现有默认音效；静音、效果音量和后台静音仍然有效。对手暗置反制不产生公共音效或事件。普通指令离场不属于阵亡。

`background` / `music` 仅用于场地。新场地未填某项时，该项恢复默认战场背景/音乐，不继承旧场地。音乐渐变切换，重复收到同一场地快照不会重播；返回菜单后恢复菜单音乐。过期下载不会覆盖后来选定的场地。

网页支持浏览器可解码的 MP3、WAV、OGG 等格式，音效最长 12 秒，音乐最长 300 秒，输入文件最大 32 MiB。网页转码成 22050Hz 单声道 16-bit PCM WAV；服务端严格校验 WAV 头、实际字节、时长和账号配额（512 段 / 256 MiB）。上传 `POST /v1/card-sounds`，请求 `{kind:"sound"|"music",wav_base64:"..."}`，读取 `/v1/card-sounds/{sha256}.wav`。背景复用已有 PNG 卡面上传服务。

客户端同源下载，验证内容哈希并缓存到本机，最多同时下载 4 段。媒体没有加载成功时使用默认表现；音效不会在下载完成后延迟补播。媒体只影响表现，联机规则不依赖媒体下载、音量或播放进度。
