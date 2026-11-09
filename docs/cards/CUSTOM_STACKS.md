# 自定义层数（mechanics-18，覆盖旧版“仅重甲”的限制）

modify_stacks / set_stacks 的 stack 可直接填写自定义名称，如 high、蓄力。名称1—32字，无首尾空格或控制字符，区分大小写、统一Unicode NFC。同名表示同一种计数，不同名独立；不必登记一个假内置词条。若需要复用完整机制，可像普通能力一样登记模板词条。层数本身没有伤害减免或其他隐含行为，不可把未知状态当成重甲。

自定义层数0—99，每次增减-99…99（非0），设定0…99；不足减到0，不累计负债。heavy_armor保留原来0—10范围与战斗减伤行为。最多16种自定义层数/单位。duration支持battle、end_of_turn、match，遵循已有期限语义；抑制清除，永久层可随同一张牌离场再入场，复制继承永久层数，不继承本次在场或本回合层数。限时加减层过期会撤销其变换；将层数清零也须明确期限。通过相同期限的状态合并避免连续加减不断堆积历史。自定义层数不允许while_active光环，避免自引用循环。

单位及衍生单位新增 trigger:on_stack_gained，并必须填写 stack 名称。只有显式modify_stacks/set_stacks使当前层数真正增加时才触发，达到上限的零增长、减少、清零、过期恢复、重新入场恢复不会触发。当前效果组完成后按队列执行，每次执行前重新检查premise；消费后其他排队事件不会因为旧条件重复领奖。limit可选1…9，按该能力本次在场的实际执行次数计数。单次增加6层只产生一次事件，不能擅自理解成“每3层转换两次”。无限自增仍受整次行动执行预算约束。

示例：每次获得high后，若已有至少3层，清空全部high，攻击+1，持续本次在场期间：
```json
{"trigger":"on_stack_gained","stack":"high","premise":{"test":"compare","left":{"stack_count":{"target":"self","stack":"high"}},"cmp":"gte","right":3},"effects":[{"op":"set_stacks","target":"self","stack":"high","amount":0,"duration":"battle"},{"op":"modify_stats","target":"self","attack_delta":1,"health_delta":0,"duration":"battle"}]}
```

premise比较值、damage/heal的amount、modify_stats的增量均可用 `{stack_count:{target:"self|chosen|trigger_unit|creator",stack:"high"}}`。也可用 `{unit_stat:{target:"self|chosen|trigger_unit|creator",stat:"attack|health|base_attack|base_health"}}`。都是每个效果开始时读取一次，不是光环。缺失单位使整个前提树无效（包括not）；缺失数值来源读0。不允许选总部读取单位属性。

target:creator 表示生成该衍生卡的实际单位实例，适用于已有单位效果目标与以上数值读取。由 create_card / summon 自动保存，无需模型填写UID；两只同名单位不混用。生成者离场后关联失效，返手重下不会连到新实例。由指令继续生成的后续衍生牌继承已有生成者关联；普通非衍生卡没有生成者，其creator效果无目标。生成者仍在时，可读取其当前攻击并增加其high：damage chosen amount:{unit_stat:{target:"creator",stat:"attack"}}，随后 modify_stacks creator high 1 battle。

`remove_hand`：{op:"remove_hand",player:"owner|opponent",card_name:"倒管子"}，移除该方当前手牌中所有准确同名卡，不进入弃牌区，不触发弃牌，不碰已经伏置的反制与牌组。单位 own_turn_end 可用它实现回合末临时手牌消失；本单位先离场则不再监听回合末，若玩家希望无论单位是否存活都消失，应继续澄清而不能擅自替代。

复述和生成都必须使用当前能力，不能再次报自定义high/层数阈值/生成者攻击力读取/按名字移除手牌均不支持。玩家未明确初始与当前攻击、目标是否包括总部、没有可牺牲单位时是否能出牌、其他衍生卡的卡面和来源，仍需追问；未知卡不能编造。每张牌仍最多3种衍生模板，不得悄悄省掉超额卡牌。


衍生卡在卡库单独展示，但来源仍是所属卡的 tokens。tokens[].deck_building 默认为 generated_only（不主动入组）；allowed 必须由玩家手工明确开启。助手创建的新衍生卡不得自作主张开启 allowed，已有蓝图的许可、稀有度、音效必须保留。衍生卡 tokens[].rarity 可用 standard/limited/special/elite，未指定普通。允许主动入组不凭空制造 creator；由牌组抽到的独立卡没有生成者。
