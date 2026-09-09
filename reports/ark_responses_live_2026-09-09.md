# 豆包 Responses 低级模型真实测试

日期：2026-09-09

## 请求

- 端点：`https://ark.cn-beijing.volces.com/api/v3/responses`
- 模型：`doubao-seed-2-0-mini-260428`
- 输入：`ark_demo_img_1.png` 远程图片 URL + `你看见了什么？请用一句中文回答。`
- Key：仅从当前进程读取，未写入文件、日志或报告。

测试经过应用的 `ChatRepository → AiService → RoleplayTurn` 请求、响应和本地协议校验链路，共 20 轮。第一轮使用 `input_image` + `input_text`，后 19 轮携带最近 4 轮应用历史消息；每轮校验完成后把联系人连续性状态和 assistant 显示正文放入下一轮。Responses 返回内容从 `output_text` 或 `output[].content[].text` 提取。

## 结果

第一次请求使用 `max_output_tokens=256`。HTTP 请求成功，但模型返回 `status=incomplete`、`incomplete_details.reason=length`，输出上限被 reasoning 消耗完，没有最终 message。这不是格式错误；应用现在会提示“Responses 回复因输出上限截断”。

将上限调整为 `2048` 后，最终 20 轮连续真实调用结果为：20/20 返回完整的 `protocolVersion`、`reply` 和 `memoryPatch` JSON，20/20 通过 `RoleplayTurn` 本地协议校验，0 轮输出截断，0 轮解析失败。

内容偏移检测使用固定的图片事实问题序列，覆盖模型名、文本/图片/视频输入输出能力、重复提问、总结和“是否仍围绕图片”的自检。20 轮都命中了对应主题词，没有从图片事实转向无关主题；但这不代表事实完全一致：重复提问时，模型对 Doubao、DeepSeek、GLM 的输入能力出现过增减或互相矛盾的表述。例如前面回答称 DeepSeek/GLM 支持图片输入，后面又只称其支持文本；Doubao 的输入能力也出现过不同范围。结论是“20/20 可解析、主题未漂移，但存在事实级内容波动”，不能称为内容完全稳定。这个判定是针对本次提示序列和图片内容的稳定性观察，不等同于通用语义评测。

默认测试套件仍为 100/100；本测试是显式 opt-in，不计入默认数量。
