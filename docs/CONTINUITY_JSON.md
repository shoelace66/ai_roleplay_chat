# Continuity JSON

创建窗口中的“使用 JSON 创建”已内置[完整示例](examples/contact-detailed.json)，包含角色设定、世界知识、物品和六个状态：时间、地点、天气、关系阶段、当前行动、已确认线索。

```json
{
  "continuity": {
    "schemaVersion": 2,
    "revision": 1,
    "definitions": [
      {
        "id": "time_of_day",
        "label": "当前时间",
        "type": "string",
        "enum": ["清晨", "上午", "中午", "下午", "傍晚", "深夜", "凌晨"],
        "description": "当前场景的时间段，影响光线、氛围和角色的身体状态。",
        "defaultValue": "下午",
        "updateRule": "只有叙事明确经过较长时间或发生时间跳转时才改变。"
      },
      {
        "id": "location",
        "label": "当前位置",
        "type": "string",
        "description": "角色实际所在地点；计划前往的地点不算当前位置。",
        "defaultValue": "雨城 · 电车站",
        "updateRule": "只有实际到达新地点时更新。"
      }
    ],
    "values": {
      "time_of_day": "傍晚",
      "location": "雨城 · 河岸步道"
    }
  }
}
```

| 字段 | 用途 |
| --- | --- |
| `schemaVersion` | 当前结构版本为 2。 |
| `revision` | 当前状态版本，非负整数；新对象通常使用 0，导入可以携带已有版本，之后由系统维护。 |
| `id` | 稳定唯一标识，`values` 及模型更新都使用它；更改显示名称时保持 ID 不变。 |
| `label` | 显示名称，同一对象中不能重名。 |
| `type` | 当前支持 `string`，省略按 string 处理；其他类型会明确报错。 |
| `enum` | 可选文本数组；不填或空数组允许自由文本。非空值须精确匹配选项，选项不能为空或重复。 |
| `description` | 记录什么，以及该项代表的含义。 |
| `defaultValue` | 未提供当前值时使用的初值，不会覆盖已有当前值。 |
| `updateRule` | 可选更新规则，说明何时改变或保持。 |
| `values` | 按 ID 保存当前值，优先于默认值；导入时省略某项则使用其默认值。显式 `""` 表示清空，也适用于 enum 项。 |

旧格式 `name / initialValue` 仍然可读，分别对应 `label / defaultValue`。同时提供新旧字段且内容冲突时会报错，避免静默覆盖。完整备份的顶层联系人定义和提示词使用新结构；内部日志保留兼容表示，以便旧剧情继续回滚。

导入校验会具体到字段，例如 `$.continuity.definitions[0].enum[1]`，或 `$.continuity.values.time_of_day`，并显示实际值与允许的选项。JSON 语法错误沿用行、列、字符及 Unicode 编码定位。全角标点、空格等兼容处理保留；ID 和枚举值不会进行语义模糊猜测。
