import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import http from "node:http";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createXiaoHetaoServer, loadContentManifest } from "./server.mjs";

const testDataRoot = mkdtempSync(join(tmpdir(), "walnut-events-test-"));
const testServerDir = dirname(fileURLToPath(import.meta.url));
const contentManifestPath = join(testServerDir, "..", "content-engine", "generated", "ai", "UNIT-DATA-GARDEN-LOOP.json");
const contentManifest = JSON.parse(readFileSync(contentManifestPath, "utf8"));
const inconsistentManifest = structuredClone(contentManifest);
inconsistentManifest.world.main_target += 1;
const inconsistentManifestPath = join(testDataRoot, "inconsistent-content.json");
writeFileSync(inconsistentManifestPath, JSON.stringify(inconsistentManifest), "utf8");
assert.throws(() => loadContentManifest(inconsistentManifestPath), /main_target.*target_count/u);
// 期望的答案次数来自内容包，避免内容版本升级后测试残留旧答案。
const mainTarget = Number(contentManifest.world.main_target);
const mainTargetChinese = { 1: "一", 2: "二", 3: "三", 4: "四", 5: "五", 6: "六", 7: "七", 8: "八", 9: "九", 10: "十" }[mainTarget] ?? "";
const answerLeakPattern = new RegExp(`重复\\s*${mainTarget}|${mainTarget}\\s*[次遍]${mainTargetChinese ? `|${mainTargetChinese}\\s*[次遍]` : ""}`, "u");
const finalAnswerPattern = new RegExp(`${mainTarget}\\s*次`, "u");

async function listen(server) {
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const address = server.address();
  return `http://127.0.0.1:${address.port}`;
}

async function close(server) {
  server.closeAllConnections();
  await new Promise((resolve) => server.close(resolve));
}

async function postHint(baseUrl, payload) {
  return fetch(`${baseUrl}/api/xiao-hetao/hint`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
}

async function postEvent(baseUrl, payload) {
  return fetch(`${baseUrl}/api/learning-events`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
}

const baseState = {
  student_id: "student_test_001",
  age_band: "9-11",
  stage: "main_loop",
  repeat_count: 2,
  lit_targets: 0,
  failed_attempts: 0,
  hint_requests: 1,
  hint_level: 1,
  observation_done: true,
  action_selected: true,
  action_name: "生长",
  learning_phase: "build_blocks",
  current_program: "重复 2 次 { 生长 }",
  last_change: "把执行次数改为 2",
  error_type: "执行次数偏少",
  diagnosis_id: "COUNT_TOO_SMALL",
  execution_trace_summary: {
    execution_steps: 4,
    completed_targets: 2,
    no_target_actions: 0,
    goal_met: false,
  },
  prediction: "亮起 1 颗",
  needs_review: false,
};

const mockEventDataDir = join(testDataRoot, "mock");
const mockAssignmentDir = join(testDataRoot, "review-assignments");
mkdirSync(mockAssignmentDir, { recursive: true });
const testStudentHash = `walnut_${createHash("sha256").update(baseState.student_id).digest("hex").slice(0, 24)}`;
const testVariant = contentManifest.transfer_variants.find((variant) => variant.misconception_id === "MIS-LOOP-UNDER");
writeFileSync(join(mockAssignmentDir, `${testStudentHash}.json`), JSON.stringify({
  assignment_id: "assignment_test_under",
  variant_id: testVariant.variant_id,
  unit_id: contentManifest.unit_id,
  content_version: contentManifest.version,
}), "utf8");
const mockServer = createXiaoHetaoServer({ mock: true, port: 0, maxRequestsPerMinute: 100, eventDataDir: mockEventDataDir, reviewAssignmentDir: mockAssignmentDir });
const mockBaseUrl = await listen(mockServer);
try {
  const health = await fetch(`${mockBaseUrl}/health`).then((response) => response.json());
  assert.equal(health.status, "ok");
  assert.equal(health.mode, "mock");
  assert.equal(health.unit_id, "UNIT-DATA-GARDEN-LOOP");
  assert.match(health.content_version, /^\d+\.\d+\.\d+$/);
  assert.match(health.content_hash, /^[a-f0-9]{64}$/);
  assert.equal(health.event_schema_version, "1.0.0");
  assert.equal(health.event_store, "ready");

  const assignmentResponse = await fetch(`${mockBaseUrl}/api/review-assignment?student_id=${encodeURIComponent(baseState.student_id)}`);
  assert.equal(assignmentResponse.status, 200);
  const assignment = await assignmentResponse.json();
  assert.equal(assignment.assignment_id, "assignment_test_under");
  assert.equal(assignment.variant_id, testVariant.variant_id);
  assert.equal(assignment.unit_id, contentManifest.unit_id);
  assert.equal((await fetch(`${mockBaseUrl}/api/review-assignment?student_id=unknown_student`)).status, 404);

  const earlyResponse = await postHint(mockBaseUrl, baseState);
  assert.equal(earlyResponse.status, 200);
  const early = await earlyResponse.json();
  assert.equal(early.hint_level, 1);
  assert.equal(early.answer_revealed, false);
  assert.equal(early.needs_review, false);
  assert.equal(early.content_version, health.content_version);
  assert.equal(answerLeakPattern.test(early.message), false);

  const finalResponse = await postHint(mockBaseUrl, { ...baseState, failed_attempts: 5, hint_requests: 5, hint_level: 5 });
  assert.equal(finalResponse.status, 200);
  const final = await finalResponse.json();
  assert.equal(final.hint_level, 5);
  assert.equal(final.answer_revealed, true);
  assert.equal(final.needs_review, true);
  assert.match(final.message, finalAnswerPattern);

  const invalidResponse = await postHint(mockBaseUrl, { stage: "unknown" });
  assert.equal(invalidResponse.status, 400);

  const staleContentResponse = await postHint(mockBaseUrl, { ...baseState, content_version: "9.9.9" });
  assert.equal(staleContentResponse.status, 400);

  const sessionId = "session_test_content_engine_001";
  const eventBase = {
    event_schema_version: "1.0.0",
    occurred_at: "2026-07-19T14:00:00",
    anonymous_student_id: "student_test_001",
    session_id: sessionId,
    unit_id: health.unit_id,
    version: health.content_version,
    content_hash: health.content_hash,
    stage: "program",
    payload: {},
  };
  const events = [
    { event_id: "evt_test_0001", event_name: "session_started", stage: "arrival", elapsed_ms: 0, payload: { age_band: "8-12", experiment_variant: "A" } },
    { event_id: "evt_test_0002", event_name: "program_run", elapsed_ms: 1_000, payload: { diagnosis_id: "SUCCESS" } },
    { event_id: "evt_test_0003", event_name: "hint_requested", elapsed_ms: 2_000, payload: { hint_level: 2 } },
    { event_id: "evt_test_0004", event_name: "hint_delivered", elapsed_ms: 2_100, payload: { source: "deepseek" } },
    { event_id: "evt_test_0005", event_name: "surprise_triggered", elapsed_ms: 5_000, payload: { student_triggered: true } },
    { event_id: "evt_test_0006", event_name: "counterfactual_run", elapsed_ms: 8_000, payload: { diagnosis_id: "COUNT_TOO_SMALL", repeat_count: mainTarget - 1, target_count: mainTarget } },
    { event_id: "evt_test_0007", event_name: "transfer_run", stage: "transfer", elapsed_ms: 12_000, payload: { first_attempt: true, diagnosis_id: "SUCCESS" } },
    { event_id: "evt_test_0008", event_name: "concept_revealed", stage: "concept", elapsed_ms: 13_000, payload: {} },
    { event_id: "evt_test_0009", event_name: "boss_debug_run", stage: "boss", elapsed_ms: 18_000, payload: { success: true } },
    { event_id: "evt_test_0010", event_name: "optional_explore_completed", stage: "transfer", elapsed_ms: 20_000, payload: {} },
    { event_id: "evt_test_0011", event_name: "session_completed", stage: "complete", elapsed_ms: 25_000, payload: { main_run_attempts: 1, hint_requests: 1, transfer_attempts: 1, counterfactual_pass: true, concept_revealed: true, optional_explore_completed: true, needs_review: false } },
  ];
  let completed;
  for (const event of events) {
    const response = await postEvent(mockBaseUrl, { ...eventBase, ...event });
    assert.equal(response.status, 202);
    completed = await response.json();
  }
  assert.equal(completed.summary.effectiveness_score, 100);
  assert.equal(completed.summary.delight_proxy_score, 90);
  assert.equal(completed.summary.transfer_first_pass_without_hint, true);
  assert.equal(completed.summary.ai_hint_source, "DeepSeek");
  assert.equal(completed.summary.post_surprise_exploration_seconds, 20);

  const duplicate = await postEvent(mockBaseUrl, { ...eventBase, ...events[0] });
  assert.equal(duplicate.status, 200);
  assert.equal((await duplicate.json()).duplicate, true);
  const sessionSummary = await fetch(`${mockBaseUrl}/api/learning-sessions/${sessionId}`).then((response) => response.json());
  assert.equal(sessionSummary.event_count, events.length);
  assert.equal(sessionSummary.experiment_variant, "A");
  const outboxPath = join(mockEventDataDir, "feishu-outbox", `${sessionId}.json`);
  assert.equal(existsSync(outboxPath), true);
  const outbox = JSON.parse(readFileSync(outboxPath, "utf8"));
  assert.equal(outbox["效果得分"], 100);
  assert.equal(outbox["趣味代理得分"], 90);
  assert.equal(outbox["内容哈希"], health.content_hash);
  assert.equal(outbox["数据来源"], "自动事件聚合");

  const reviewSessionId = "session_test_review_variant_001";
  const reviewEvents = [
    { event_id: "evt_review_0001", event_name: "session_started", stage: "arrival", elapsed_ms: 0, payload: { age_band: "8-12" } },
    { event_id: "evt_review_0002", event_name: "program_run", elapsed_ms: 1_000, payload: { diagnosis_id: "COUNT_TOO_SMALL" } },
    { event_id: "evt_review_0003", event_name: "program_run", elapsed_ms: 2_000, payload: { diagnosis_id: "COUNT_TOO_SMALL" } },
    { event_id: "evt_review_0004", event_name: "session_completed", stage: "complete", elapsed_ms: 3_000, payload: { needs_review: true } },
  ];
  let reviewCompleted;
  for (const event of reviewEvents) {
    const response = await postEvent(mockBaseUrl, { ...eventBase, ...event, session_id: reviewSessionId });
    assert.equal(response.status, 202);
    reviewCompleted = await response.json();
  }
  assert.equal(reviewCompleted.summary.dominant_diagnosis_id, "COUNT_TOO_SMALL");
  assert.equal(reviewCompleted.summary.recommended_variant_id, testVariant.variant_id);

  const staleEvent = await postEvent(mockBaseUrl, { ...eventBase, ...events[0], event_id: "evt_test_stale", version: "9.9.9" });
  assert.equal(staleEvent.status, 400);
  const staleSchemaEvent = await postEvent(mockBaseUrl, { ...eventBase, ...events[0], event_id: "evt_test_schema", event_schema_version: "9.9.9" });
  assert.equal(staleSchemaEvent.status, 400);
  const sensitiveEvent = await postEvent(mockBaseUrl, { ...eventBase, ...events[0], event_id: "evt_test_pii", payload: { school_name: "不应采集" } });
  assert.equal(sensitiveEvent.status, 400);

  const restartedServer = createXiaoHetaoServer({ mock: true, port: 0, maxRequestsPerMinute: 100, eventDataDir: mockEventDataDir });
  const restartedBaseUrl = await listen(restartedServer);
  try {
    const duplicateAfterRestart = await postEvent(restartedBaseUrl, { ...eventBase, ...events[0] });
    assert.equal(duplicateAfterRestart.status, 200);
    assert.equal((await duplicateAfterRestart.json()).duplicate, true);
    const restoredSummary = await fetch(`${restartedBaseUrl}/api/learning-sessions/${sessionId}`).then((response) => response.json());
    assert.equal(restoredSummary.event_count, events.length);
    assert.equal(restoredSummary.effectiveness_score, 100);
  } finally {
    await close(restartedServer);
  }
} finally {
  await close(mockServer);
}

const hotReloadRoot = join(testDataRoot, "hot-reload");
mkdirSync(hotReloadRoot, { recursive: true });
const hotReloadManifestPath = join(hotReloadRoot, "manifest.json");
const originalManifest = JSON.parse(readFileSync(join(testServerDir, "..", "content-engine", "generated", "ai", "UNIT-DATA-GARDEN-LOOP.json"), "utf8"));
writeFileSync(hotReloadManifestPath, JSON.stringify(originalManifest), "utf8");
const hotReloadServer = createXiaoHetaoServer({
  mock: true,
  port: 0,
  maxRequestsPerMinute: 100,
  eventDataDir: join(hotReloadRoot, "events"),
  contentManifestPath: hotReloadManifestPath,
});
const hotReloadBaseUrl = await listen(hotReloadServer);
try {
  const before = await fetch(`${hotReloadBaseUrl}/health`).then((response) => response.json());
  const changedManifest = { ...originalManifest, version: "9.8.7", content_hash: "b".repeat(64) };
  writeFileSync(hotReloadManifestPath, JSON.stringify(changedManifest), "utf8");
  const after = await fetch(`${hotReloadBaseUrl}/health`).then((response) => response.json());
  assert.equal(before.content_version, originalManifest.version);
  assert.equal(after.content_version, "9.8.7");
  assert.equal(after.content_hash, "b".repeat(64));
} finally {
  await close(hotReloadServer);
}

const upstreamReplies = [
  { message: "你已经找到生长动作了，再观察目标之间的关系。", mood: "encourage", answer_revealed: false, next_action: "继续观察" },
  { message: `直接把重复改成${mainTarget}次。`, mood: "calm", answer_revealed: true, next_action: "运行" },
  { message: `把重复改成 ${mainTarget} 次，再由你亲手运行。`, mood: "calm", answer_revealed: true, next_action: "运行程序" },
];
const upstreamRequests = [];
const fakeDeepSeek = http.createServer(async (request, response) => {
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  const body = JSON.parse(Buffer.concat(chunks).toString("utf8"));
  upstreamRequests.push({
    path: request.url,
    authorization: request.headers.authorization,
    body,
  });
  const reply = upstreamReplies[Math.min(upstreamRequests.length - 1, upstreamReplies.length - 1)];
  const payload = JSON.stringify({
    id: `fake-${upstreamRequests.length}`,
    model: "deepseek-v4-flash",
    choices: [{ index: 0, finish_reason: "stop", message: { role: "assistant", content: JSON.stringify(reply) } }],
    usage: { prompt_tokens: 100, completion_tokens: 20, total_tokens: 120 },
  });
  response.writeHead(200, { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(payload) });
  response.end(payload);
});
const fakeBaseUrl = await listen(fakeDeepSeek);

const liveProxy = createXiaoHetaoServer({
  apiKey: "test-key-never-sent-to-godot",
  baseUrl: fakeBaseUrl,
  model: "deepseek-v4-flash",
  port: 0,
  maxRequestsPerMinute: 100,
  eventDataDir: join(testDataRoot, "live"),
});
const liveBaseUrl = await listen(liveProxy);
try {
  const health = await fetch(`${liveBaseUrl}/health`).then((response) => response.json());
  assert.equal(health.mode, "deepseek");

  const safeResponse = await postHint(liveBaseUrl, baseState);
  const safe = await safeResponse.json();
  assert.equal(safe.source, "deepseek");
  assert.equal(safe.answer_revealed, false);
  assert.equal(upstreamRequests[0].path, "/chat/completions");
  assert.equal(upstreamRequests[0].authorization, "Bearer test-key-never-sent-to-godot");
  assert.equal(upstreamRequests[0].body.model, "deepseek-v4-flash");
  assert.deepEqual(upstreamRequests[0].body.thinking, { type: "disabled" });
  assert.deepEqual(upstreamRequests[0].body.response_format, { type: "json_object" });
  assert.match(upstreamRequests[0].body.user_id, /^walnut_[a-f0-9]{24}$/);
  assert.match(upstreamRequests[0].body.messages[1].content, /COUNT_TOO_SMALL/);
  assert.match(upstreamRequests[0].body.messages[1].content, /UNIT-DATA-GARDEN-LOOP/);

  const leakedResponse = await postHint(liveBaseUrl, { ...baseState, hint_requests: 2, hint_level: 2 });
  const leaked = await leakedResponse.json();
  assert.equal(leaked.source, "provider_fallback");
  assert.equal(leaked.answer_revealed, false);
  assert.equal(answerLeakPattern.test(leaked.message), false);

  const finalResponse = await postHint(liveBaseUrl, { ...baseState, failed_attempts: 5, hint_requests: 5, hint_level: 5 });
  const final = await finalResponse.json();
  assert.equal(final.source, "deepseek");
  assert.equal(final.answer_revealed, true);
  assert.equal(final.needs_review, true);
  assert.match(final.message, finalAnswerPattern);

  console.log("XIAO_HETAO_SERVER_TEST_OK");
} finally {
  await close(liveProxy);
  await close(fakeDeepSeek);
  rmSync(testDataRoot, { recursive: true, force: true });
}
