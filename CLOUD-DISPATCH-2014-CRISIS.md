# 东艺危机反事实推演 · 云端权威运行派单（P2）

> 用途：在 CloudStudio 的 AgentTeams DSH Runtime（v040 主线）上做一次真实云端四岗运行，为复赛补齐「云端权威运行证据」。
> 操作员流程：① 云端终端跑 `bash dispatch-lifecycle-lease.sh arm 1800`（见迁移包 runbook）；② `bash verify-room-target.sh '<Element 真实 room_id>'`；③ 两门禁都 OK 后，把下方 text 代码块全文仅发送一次到 `Leader DM: juchang-v14-lead`。
> 诚实声明：本案件是 2014 历史事件的反事实演练，材料为脱敏冻结投影与合成虚拟闭源库；运行本身必须真实（真实模型、真实 Taskflow/Projectflow 状态、真实回执）。

## 案件简报（供四岗建立态势，全部标注证据层级）

2014-03-15 上海东方艺术中心，莱比锡布商大厦管弦乐团演出日。独奏钢琴家尼尔森·弗雷尔突发身体不适，医生禁止当晚上台（多源确认）。受影响核心曲目：贝多芬《第五钢琴协奏曲〈皇帝〉》（时长 42 分钟为单源口述）。现场满座，含多地高清转播与电台直播（部分验证）。医嘱休息时长存在 20 小时（口述）与 24 小时（报道）冲突，安全结论仅为「禁止当晚上台」，小时数保持冲突不得择一。历史实际结果：缩短节目 + 一个月内凭票退票面 50%。

候选方案（口述中均被考虑过）：A 寻找钢琴家替补；B 卡瓦科斯改奏门德尔松小提琴协奏曲（需本人/原邀请方上海音乐厅/指挥乐团三方许可，合作关系不构成许可）；C 补演马勒《第七交响曲》部分乐章（缺约二三十名不同编制乐手，无法召回）；D 缩短节目并退票面 50%（需具名经济授权人批准）。

四岗任务：material_intake 登记事实集与冲突；evidence_guard 逐条核对四方案的艺术/技术可行性与硬阻断；entity_matcher 厘清利益相关者关系与授权链（关系不等于许可）；approval_guard 评估观众影响、沟通口径与执行边界。所有动作禁止批准、退款、发布、外联、写生产系统。

## 派单（发送内容）

```text
JUCHANG_CLOUD_DISPATCH: {"schema":"juchang-cloud-dispatch@1","dispatchId":"cloud_chg-crisis-sim-2014-east-art-center_crisis-2014-east-art-center-cloud-p2","projectId":"cloud_chg-crisis-sim-2014-east-art-center_crisis-2014-east-art-center-cloud-p2","idempotencyKey":"cloud_chg-crisis-sim-2014-east-art-center_crisis-2014-east-art-center-cloud-p2","changeRef":"chg-crisis-sim-2014-east-art-center","projectRef":"zhuantang-yixun","adapterRef":"yixun-local","decisionRunId":"crisis-2014-east-art-center-cloud-p2","riskRoute":"TEAM","runtimeEnvironment":"cloudstudio","targetTeam":"juchang-change-control-v14","targetLeaderDMRoomId":"!GKL4XFzVKBFE6bqGad:matrix-local.agentteams.io:18080","external_write_allowed":false,"sourceLocators":["call-transcript-20260902","http://xmwb.xinmin.cn/html/2014-03/16/content_9_1.htm","http://culture.people.com.cn/n/2014/0319/c22219-24672584.html","https://xmwb.xinmin.cn/html/2014-03/17/content_12_2.htm","output/briefing/林宏鸣沟通材料/2014-东艺危机-AgentTeams反事实模拟-v0.json"],"affectedObjects":["2014·3·15 东艺演出危机反事实复盘"],"unresolvedQuestions":["是否采纳方案：寻找钢琴家替补","是否采纳方案：卡瓦科斯演奏门德尔松小提琴协奏曲","是否采纳方案：补演马勒《第七交响曲》部分乐章","是否采纳方案：保留剩余节目并退还票面金额 50%"],"tasks":[{"taskId":"cloud_chg-crisis-sim-2014-east-art-center_crisis-2014-east-art-center-cloud-p2-01","role":"material_intake","dependsOn":[],"output":"status + summary + deliverables"},{"taskId":"cloud_chg-crisis-sim-2014-east-art-center_crisis-2014-east-art-center-cloud-p2-02","role":"evidence_guard","dependsOn":["material_intake"],"output":"status + summary + deliverables"},{"taskId":"cloud_chg-crisis-sim-2014-east-art-center_crisis-2014-east-art-center-cloud-p2-03","role":"entity_matcher","dependsOn":["material_intake"],"output":"status + summary + deliverables"},{"taskId":"cloud_chg-crisis-sim-2014-east-art-center_crisis-2014-east-art-center-cloud-p2-04","role":"approval_guard","dependsOn":["evidence_guard","entity_matcher"],"output":"status + summary + deliverables"}],"authority":{"mayApprove":false,"mayExecute":false,"publicWriteAllowed":false}}

执行契约：
1. `ROOM_TARGET_OK` 是发送端在消息进入 Matrix 之前完成的前置授权证明：发送者已从当前 CloudStudio Runtime 读取 `agt get teams juchang-change-control-v14` 的 `LeaderDMRoomID`，并与 Element 当前房间解析后的真实 `room_id`、派单中的 `targetLeaderDMRoomId` 三方精确核对，同时确认 `runtimeEnvironment=cloudstudio`。Leader 收到本消息即表示发送端门禁已经完成；Leader 只需核对派单内的 `targetTeam`、`targetLeaderDMRoomId` 与当前接收房间身份，不得在 Leader 容器内寻找、运行或要求 `verify-room-target.sh`，也不得因该发送端脚本不在 Leader workspace 而创建 Project 后中止。若消息实际来自其他房间或身份不一致，才输出 `ROOM_TARGET_MISMATCH` 并禁止创建对象。`127.0.0.1:18088` 的本机 Element 与其中同名房间标记为 local/retired，不得作为本派单目标。
2. 定义 `runtimeProjectId = dispatchId`。所有 projectflow/taskflow 生命周期操作必须使用已分配的 `juchang-lifecycle-control` Skill，通过 `$HOME/.qwenpaw/workspaces/default/skills/juchang-lifecycle-control/scripts/lifecycle.mjs --request <绝对路径>` 执行；禁止直接调用当前会话里的 ambient driver。调用 create_project 时必须在请求中显式传入 `projectId=<dispatchId>`，并核对响应的 `project.project_id` 与 dispatchId 完全相同后才可继续。`projectRef=zhuantang-yixun` 只是编辑器业务引用，仅用于最终聚合回执；禁止把 projectRef 作为 projectflow 的 projectId、name、title 或 Task 前缀。任一身份不一致立即输出 `PROJECT_ID_MISMATCH`，禁止继续创建或委派。
3. 调用 projectflow 前必须确认四个 taskId 均以 `<dispatchId>-` 开头。随后通过 projectflow plan_dag，并按 ready_nodes 委派；派单中的四个 taskId 与 role 必须逐项原样保留。运行 DAG 时，将 dependsOn 中的 role 引用映射到对应的原始 taskId，但不得修改派单原文。
4. material_intake → evidence_guard 与 entity_matcher 并行 → approval_guard。每个 Worker 必须先 ack_task，把领域收据写入 shared/tasks/<taskId>/workspace/receipt.json，再使用已分配的 `juchang-task-submit` Skill 及其固定脚本提交；脚本必须显式接收 `project-id=<dispatchId>` 与原始 taskId，并在本地拒绝 project/task 前缀不一致。禁止直接手写 submit_task。只有脚本输出 `JUCHANG_TASK_SUBMIT_VERIFIED` 才能回报完成。
5. Worker 只能报告证据可支持的结论。本案件为历史反事实演练：事实以派单简报的证据层级为准（多源确认 / 单源口述 / 冲突 / 假设）；冲突不得抹平，未知写明未知。无法确认时应明确返回 HUMAN_REVIEW；不得把"任务有效提交"冒充"方案获批"。
6. 每份 Worker 收据必须含 safetyCounters：productionWrites=0、publicPublishes=0、realRefunds=0、externalMessages=0。禁止回写转塘艺讯活动库、公开日程、PocketBase、公众号或其他外部系统；禁止批准、退款、公开发布和外发消息。
7. Leader 对每个完成任务只调用 juchang-lifecycle-control 的 accept_task_result 操作；该 Skill 必须在一个受控动作中依次执行 check_task、accept_task_result，再读回该 Task 的权威状态。只有脚本输出 JUCHANG_LIFECYCLE_VERIFIED，且 auditEvents 依次证明 effective=true、accept 成功与 Task status=completed 才可继续，并把三步真实响应按顺序写入 shared/projects/<真实 Project ID>/workspace/juchang-cloud-audit.json（schema=juchang-cloud-audit@1，事件名固定为 check_task、accept_task_result、task_terminal_observed）。effective=false、validationErrors 非空、状态为 submitted/cancelled/pending、effective 缺失、WORKFLOW_INCONSISTENT 或审计响应缺失时，立即停止，不得改用 ambient driver 或手工修补 meta.json/result.md。
8. complete_project 前必须确认四次 check_task.effective=true、四次 accept_task_result 成功、四次 task_terminal_observed=completed 全部有权威审计记录。任一项不满足，禁止写 Project 汇总、禁止 complete_project、禁止生成聚合回执。硬门禁通过后只允许调用 juchang-lifecycle-control 的 complete_project 操作，并传入精确有序的四个 expectedTaskIds；Skill 必须先读回四个 status 均为 completed，才调用 complete_project，随后再读回 Project=completed 和四个 Task 仍为 completed，并返回 complete_project、project_terminal_observed 两个真实事件。不能只根据聊天文本、Worker 摘要或自报回执判断成功。
9. 禁止在四个 Task 均为 completed 之前生成聚合回执。只有审计时序、Project/Task 权威终态和四份真实 Worker 收据全部通过后，才能生成 shared/projects/<真实 Project ID>/workspace/juchang-cloud-receipt.json。严格使用 juchang-cloud-receipt@1，仅包含 schema、dispatchId、changeRef、projectRef、status、workers、completeProject、leader、counters、receivedAt；receivedAt 必须严格晚于四个 Task 终态、complete_project 和 project_terminal_observed 的时间。编辑器接收口径固定为：顶层 status=completed；四个 workers[*].status=completed；leader.status=READY_FOR_HUMAN_REVIEW。这里的 completed 只表示本次协作运行及收据生成完成，不表示变更已批准或已执行。projectRef 必须保持 zhuantang-yixun；四个 role 固定为 material_intake、evidence_guard、entity_matcher、approval_guard；每个 role 的 taskId 必须与派单中该 role 的 taskId 逐项完全相同；所有 counters 必须由运行收据汇总且为 0。
10. juchang-cloud-audit.json 与聚合回执写入后必须读回验证，并运行协议包的 `build-runtime-evidence.mjs <Leader workspace绝对路径> <project_id> <本次派单文件>` 生成 shared/projects/<真实 Project ID>/workspace/juchang-cloud-runtime-evidence.json；随后分别运行 `validate-cloud-receipt.mjs <聚合回执> <本次派单文件>` 与 `validate-runtime-evidence.mjs <runtime evidence> <本次派单文件>`。只有生成器输出 JUCHANG_RUNTIME_EVIDENCE_BUILT、两个 validator 都返回 valid=true、审计顺序完整、四个 Task 权威状态均为 completed、四个 Worker effective=true、四次 accept 成功、complete_project 成功且服务端 Project 状态为 completed 时，才单独输出：
JUCHANG_CLOUD_TEAM_FINAL: READY_FOR_HUMAN_REVIEW
否则单独输出：
JUCHANG_CLOUD_TEAM_FINAL: WORKFLOW_INCONSISTENT
```

## 运行后回收

运行结束后把 `juchang-cloud-runtime-evidence.json` 与派单文件带回本仓库，用 `node scripts/crisis-sim/export-verified-replay.mjs <evidence> --dispatch output/crisis-sim/cloud-dispatch-2014.txt --write` 冻结为第二份 Verified Replay（云端权威版），页面回放区自动列出。
