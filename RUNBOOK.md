# 东艺危机云端权威运行 · 最终操作单（每步一次粘贴）

> 在 CloudStudio 终端执行。全部命令无管道符、可直接复制粘贴。

## 第 1 步：进入迁移目录并武装租约（30 分钟窗口）

```bash
cd /workspace/competition/juchang-agent-infra-v1.4/migration-v1.2.2 && bash dispatch-lifecycle-lease.sh arm 1800
```

期望输出含 `DISPATCH_LIFECYCLE_LEASE_OK`。

## 第 2 步：房间硬校验

在 CloudStudio 里打开 Element（如果 dashboard 的 Matrix 聊天不可用，用 Element 桌面端或云端 Element），进入 `Leader DM: juchang-v14-lead`，在房间设置里找到真实 room_id（以 `!` 开头），然后运行：

```bash
bash verify-room-target.sh '!把真实room_id贴在这里'
```

期望输出 `ROOM_TARGET_OK`。如果输出 `ROOM_TARGET_MISMATCH`，停止并告诉我。

## 第 3 步：发送派单（仅一次）

把下面文件里 ` ```text ` 代码块的**全部内容**（从 JUCHANG_CLOUD_DISPATCH 开始到 WORKFLOW_INCONSISTENT 结束）粘贴到该 Leader DM，发送一次：

桥接仓里的文件：`CLOUD-DISPATCH-2014-CRISIS.md`（也在 `/workspace` 如果在云端已解压桥接包）。

发送后：四岗会自动跑（DSH Headless）。等 5-15 分钟后，dashboard 或 Element 里应看到 `JUCHANG_CLOUD_TEAM_FINAL: READY_FOR_HUMAN_REVIEW`。

## 第 4 步：回收证据

把 `shared/projects/<project_id>/workspace/juchang-cloud-runtime-evidence.json` 和派单原文拷回本地仓库，然后本地跑：

```bash
node scripts/crisis-sim/export-verified-replay.mjs <evidence.json> --dispatch output/crisis-sim/cloud-dispatch-2014.txt --write
```

冻结为第三份 Verified Replay（云端权威版），页面回放区自动出现。

## 异常处理

- 任何一步报 `WORKFLOW_INCONSISTENT`：停止，把输出发我，不修补 meta.json。
- Worker 超时/失败：截图发我，这本身就是「异常处理演示」素材。
