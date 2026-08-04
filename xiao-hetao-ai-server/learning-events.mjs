import { createHash } from "node:crypto";
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const MAX_SESSION_MS = 6 * 60 * 60 * 1000;
const MAX_STRING_LENGTH = 240;
const MAX_ARRAY_LENGTH = 64;
const MAX_OBJECT_KEYS = 48;
const SENSITIVE_KEY = /(^|_)(name|school|phone|email|contact|address)($|_)|姓名|学校|电话|邮箱|地址|联系方式/iu;
const SAFE_ID = /^[A-Za-z0-9_-]{8,96}$/u;

function boundedInteger(value, minimum, maximum, fallback = minimum) {
  const parsed = Number.parseInt(String(value), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(maximum, Math.max(minimum, parsed));
}

function cleanText(value, maximumLength = MAX_STRING_LENGTH) {
  return String(value ?? "")
    .replace(/[\u0000-\u001f\u007f]/gu, " ")
    .replace(/\s+/gu, " ")
    .trim()
    .slice(0, maximumLength);
}

function sanitizePayload(value, depth = 0) {
  if (depth > 5) throw new Error("事件 payload 嵌套过深");
  if (value === null || typeof value === "boolean") return value;
  if (typeof value === "number") return Number.isFinite(value) ? value : 0;
  if (typeof value === "string") return cleanText(value);
  if (Array.isArray(value)) {
    return value.slice(0, MAX_ARRAY_LENGTH).map((item) => sanitizePayload(item, depth + 1));
  }
  if (!value || typeof value !== "object") return null;
  const entries = Object.entries(value);
  if (entries.length > MAX_OBJECT_KEYS) throw new Error("事件 payload 字段过多");
  const sanitized = {};
  for (const [rawKey, rawValue] of entries) {
    const key = cleanText(rawKey, 64);
    if (!key || SENSITIVE_KEY.test(key)) throw new Error("事件 payload 含敏感或无效字段");
    sanitized[key] = sanitizePayload(rawValue, depth + 1);
  }
  return sanitized;
}

function studentHash(value) {
  const source = cleanText(value, 128);
  if (!source) throw new Error("缺少匿名学生 ID");
  return `walnut_${createHash("sha256").update(source).digest("hex").slice(0, 24)}`;
}

function validateContentContract(input, manifest) {
  const unitId = cleanText(input.unit_id, 80);
  const version = cleanText(input.version, 24);
  const contentHash = cleanText(input.content_hash, 80);
  if (unitId !== manifest.unit_id) throw new Error("事件内容单元与发布版本不一致");
  if (version !== manifest.version) throw new Error("事件内容版本与发布版本不一致");
  if (contentHash !== manifest.content_hash) throw new Error("事件内容哈希与发布版本不一致");
  return { unitId, version, contentHash };
}

export function normalizeLearningEvent(input, manifest, receivedAt = new Date()) {
  if (!input || typeof input !== "object" || Array.isArray(input)) throw new Error("课堂事件必须是 JSON 对象");
  const eventId = cleanText(input.event_id, 100);
  const sessionId = cleanText(input.session_id, 100);
  if (!SAFE_ID.test(eventId) || !eventId.startsWith("evt_")) throw new Error("事件 ID 格式无效");
  if (!SAFE_ID.test(sessionId) || !sessionId.startsWith("session_")) throw new Error("会话 ID 格式无效");

  const eventName = cleanText(input.event_name, 64);
  const allowedEvents = new Set(manifest.evidence?.events ?? []);
  if (!allowedEvents.has(eventName)) throw new Error("未知课堂事件");
  const stage = cleanText(input.stage, 48);
  if (!stage) throw new Error("事件缺少阶段");
  const occurredAt = cleanText(input.occurred_at, 40);
  if (!occurredAt || Number.isNaN(Date.parse(occurredAt))) throw new Error("事件时间格式无效");

  const contract = validateContentContract(input, manifest);
  const expectedEventSchemaVersion = manifest.evidence?.event_schema_version ?? "1.0.0";
  const eventSchemaVersion = cleanText(input.event_schema_version, 16) || expectedEventSchemaVersion;
  if (eventSchemaVersion !== expectedEventSchemaVersion) throw new Error("事件 schema 版本与服务端不一致");
  return {
    event_schema_version: eventSchemaVersion,
    event_id: eventId,
    occurred_at: occurredAt,
    received_at: receivedAt.toISOString(),
    elapsed_ms: boundedInteger(input.elapsed_ms, 0, MAX_SESSION_MS, 0),
    anonymous_student_id: studentHash(input.anonymous_student_id),
    session_id: sessionId,
    unit_id: contract.unitId,
    version: contract.version,
    content_hash: contract.contentHash,
    event_name: eventName,
    stage,
    payload: sanitizePayload(input.payload ?? {}),
  };
}

function newSession(event) {
  return {
    session_id: event.session_id,
    student_hash: event.anonymous_student_id,
    unit_id: event.unit_id,
    content_version: event.version,
    content_hash: event.content_hash,
    event_schema_version: event.event_schema_version,
    classroom_at: event.occurred_at,
    received_at: event.received_at,
    experiment_variant: "基线",
    variant_id: "",
    data_source: "自动事件聚合",
    event_count: 0,
    main_run_attempts: 0,
    diagnosis_counts: {},
    hint_requests: 0,
    ai_hint_sources: [],
    counterfactual_pass: false,
    transfer_attempts: 0,
    transfer_first_pass_without_hint: false,
    concept_revealed: false,
    boss_debug_pass: false,
    optional_explore_completed: false,
    surprise_triggered: false,
    post_surprise_exploration_seconds: 0,
    needs_review: false,
    completed: false,
    last_elapsed_ms: 0,
    surprise_elapsed_ms: null,
  };
}

function truthy(value) {
  return value === true || value === 1 || value === "true";
}

function aggregateEvent(session, event) {
  const payload = event.payload ?? {};
  session.event_count += 1;
  session.last_elapsed_ms = Math.max(session.last_elapsed_ms, event.elapsed_ms);
  if (event.event_name === "session_started") {
    session.experiment_variant = ["A", "B", "基线"].includes(payload.experiment_variant) ? payload.experiment_variant : "基线";
    session.data_source = ["自动事件聚合", "自动化QA"].includes(payload.data_source) ? payload.data_source : "自动事件聚合";
    session.variant_id = cleanText(payload.variant_id, 96);
  } else if (event.event_name === "program_run") {
    session.main_run_attempts += 1;
    const diagnosisId = cleanText(payload.diagnosis_id, 64);
    if (diagnosisId) session.diagnosis_counts[diagnosisId] = Number(session.diagnosis_counts[diagnosisId] ?? 0) + 1;
  } else if (event.event_name === "hint_requested") {
    session.hint_requests += 1;
    if (Number(payload.hint_level) >= 5 || truthy(payload.answer_revealed)) session.needs_review = true;
  } else if (event.event_name === "hint_delivered") {
    const source = cleanText(payload.source, 32);
    if (source && !session.ai_hint_sources.includes(source)) session.ai_hint_sources.push(source);
  } else if (event.event_name === "surprise_triggered") {
    session.surprise_triggered = true;
    session.surprise_elapsed_ms = event.elapsed_ms;
  } else if (event.event_name === "counterfactual_run") {
    session.counterfactual_pass ||= payload.diagnosis_id === "COUNT_TOO_SMALL"
      && Number(payload.repeat_count) === Number(payload.target_count) - 1;
  } else if (event.event_name === "transfer_run") {
    session.transfer_attempts += 1;
    const diagnosisId = cleanText(payload.diagnosis_id, 64);
    if (diagnosisId) session.diagnosis_counts[diagnosisId] = Number(session.diagnosis_counts[diagnosisId] ?? 0) + 1;
    if (!session.variant_id) session.variant_id = cleanText(payload.variant_id, 96);
    session.transfer_first_pass_without_hint ||= truthy(payload.first_attempt) && payload.diagnosis_id === "SUCCESS";
  } else if (event.event_name === "concept_revealed") {
    session.concept_revealed = true;
  } else if (event.event_name === "boss_debug_run") {
    session.boss_debug_pass ||= truthy(payload.success);
  } else if (event.event_name === "optional_explore_completed") {
    session.optional_explore_completed = true;
  } else if (event.event_name === "session_completed") {
    session.main_run_attempts = boundedInteger(payload.main_run_attempts, 0, 100, session.main_run_attempts);
    session.hint_requests = boundedInteger(payload.hint_requests, 0, 100, session.hint_requests);
    session.counterfactual_pass ||= truthy(payload.counterfactual_pass);
    session.transfer_attempts = boundedInteger(payload.transfer_attempts, 0, 100, session.transfer_attempts);
    session.concept_revealed ||= truthy(payload.concept_revealed);
    session.optional_explore_completed ||= truthy(payload.optional_explore_completed);
    session.needs_review ||= truthy(payload.needs_review);
    session.completed = true;
  }

  if (session.surprise_elapsed_ms !== null) {
    session.post_surprise_exploration_seconds = Math.max(
      session.post_surprise_exploration_seconds,
      Math.round((session.last_elapsed_ms - session.surprise_elapsed_ms) / 1000),
    );
  }
  return session;
}

function metricWeight(metrics, key, fallback) {
  const value = Number(metrics?.[key]);
  return Number.isFinite(value) && value >= 0 ? value : fallback;
}

function recommendedVariantId(session, transferVariants) {
  const diagnosisToMisconception = {
    COUNT_TOO_SMALL: "MIS-LOOP-UNDER",
    COUNT_TOO_LARGE: "MIS-LOOP-OVER",
    WRONG_ACTION: "MIS-LOOP-ACTION",
    MISSING_REPEAT: "MIS-LOOP-ACTION",
    EMPTY_LOOP_BODY: "MIS-LOOP-ACTION",
  };
  const dominant = Object.entries(session.diagnosis_counts ?? {})
    .filter(([diagnosis]) => diagnosis !== "SUCCESS")
    .sort((left, right) => Number(right[1]) - Number(left[1]) || left[0].localeCompare(right[0]))[0]?.[0];
  const misconceptionId = diagnosisToMisconception[dominant] ?? (session.needs_review ? "MIS-LOOP-UNDER" : "");
  if (!misconceptionId) return "";
  return String((transferVariants ?? []).find((variant) => variant.misconception_id === misconceptionId)?.variant_id ?? "");
}

export function finalizeSessionSummary(session, sessionMetrics = {}, transferVariants = []) {
  const effectiveness = sessionMetrics.effectiveness ?? {};
  const delight = sessionMetrics.delight ?? {};
  const effectivenessScore = (
    (session.transfer_first_pass_without_hint ? metricWeight(effectiveness, "transfer_first_pass_without_hint", 40) : 0)
    + (session.counterfactual_pass ? metricWeight(effectiveness, "counterfactual_pass", 20) : 0)
    + (session.concept_revealed ? metricWeight(effectiveness, "concept_revealed", 10) : 0)
    + (session.boss_debug_pass ? metricWeight(effectiveness, "boss_debug_pass", 20) : 0)
    + (!session.needs_review ? metricWeight(effectiveness, "no_review_required", 10) : 0)
  );
  const explorationSecondCap = metricWeight(delight, "post_surprise_exploration_second_cap", 30);
  const delightProxyScore = Math.min(100, (
    (session.surprise_triggered ? metricWeight(delight, "surprise_triggered", 35) : 0)
    + (session.optional_explore_completed ? metricWeight(delight, "optional_explore_completed", 35) : 0)
    + Math.min(explorationSecondCap, session.post_surprise_exploration_seconds)
  ));
  return {
    ...session,
    dominant_diagnosis_id: Object.entries(session.diagnosis_counts ?? {}).sort((left, right) => Number(right[1]) - Number(left[1]))[0]?.[0] ?? "",
    recommended_variant_id: recommendedVariantId(session, transferVariants),
    effectiveness_score: effectivenessScore,
    delight_proxy_score: delightProxyScore,
    evidence_quality: session.completed ? "completed_session" : "partial_session",
    ai_hint_source: session.ai_hint_sources.includes("deepseek")
      ? "DeepSeek"
      : session.ai_hint_sources.some((source) => source.includes("fallback"))
        ? "服务端回退"
        : "本地回退",
  };
}

export function summaryToFeishuFields(summary, unitRecordId = "recvpNewUffa1G") {
  return {
    "会话ID": summary.session_id,
    "关联单元": [{ id: unitRecordId }],
    "内容版本": summary.content_version,
    "内容哈希": summary.content_hash,
    "课堂日期": summary.classroom_at.replace("T", " ").slice(0, 19),
    "学生哈希": summary.student_hash,
    "实验变体": summary.experiment_variant,
    "变式ID": summary.variant_id,
    "主任务运行次数": summary.main_run_attempts,
    "主动求助次数": summary.hint_requests,
    "AI提示来源": summary.ai_hint_source,
    "反事实通过": summary.counterfactual_pass,
    "无提示迁移首过": summary.transfer_first_pass_without_hint,
    "概念显形": summary.concept_revealed,
    "Boss调试通过": summary.boss_debug_pass,
    "需要复练": summary.needs_review,
    "推荐变式ID": summary.recommended_variant_id,
    "主动探索": summary.optional_explore_completed,
    "惊喜后继续探索秒数": summary.post_surprise_exploration_seconds,
    "效果得分": summary.effectiveness_score,
    "趣味代理得分": summary.delight_proxy_score,
    "数据来源": summary.data_source,
  };
}

export class LearningEventStore {
  constructor({ dataDir, manifest, now = () => new Date(), unitRecordId = "recvpNewUffa1G" }) {
    this.dataDir = dataDir;
    this.manifest = manifest;
    this.now = now;
    this.unitRecordId = unitRecordId;
    this.rawDir = join(dataDir, "raw");
    this.sessionDir = join(dataDir, "sessions");
    this.outboxDir = join(dataDir, "feishu-outbox");
    this.rawPath = join(this.rawDir, "learning-events.jsonl");
    this.sessions = new Map();
    this.seenEventIds = new Set();
    mkdirSync(this.rawDir, { recursive: true });
    mkdirSync(this.sessionDir, { recursive: true });
    mkdirSync(this.outboxDir, { recursive: true });
    this.restoreFromDisk();
  }

  restoreFromDisk() {
    if (!existsSync(this.rawPath)) return;
    for (const line of readFileSync(this.rawPath, "utf8").split(/\r?\n/u)) {
      if (!line.trim()) continue;
      try {
        const event = JSON.parse(line);
        if (event.unit_id !== this.manifest.unit_id
          || event.version !== this.manifest.version
          || event.content_hash !== this.manifest.content_hash
          || !SAFE_ID.test(event.event_id)
          || !SAFE_ID.test(event.session_id)) continue;
        this.seenEventIds.add(event.event_id);
        const current = this.sessions.get(event.session_id) ?? newSession(event);
        this.sessions.set(event.session_id, aggregateEvent(current, event));
      } catch {
        // 单行损坏不能阻断后续课堂；原文件保留供运维审计。
      }
    }
  }

  ingest(input) {
    const event = normalizeLearningEvent(input, this.manifest, this.now());
    if (this.seenEventIds.has(event.event_id)) {
      return { accepted: true, duplicate: true, event_id: event.event_id, session_id: event.session_id };
    }
    this.seenEventIds.add(event.event_id);
    appendFileSync(this.rawPath, `${JSON.stringify(event)}\n`, "utf8");
    const current = this.sessions.get(event.session_id) ?? newSession(event);
    const session = aggregateEvent(current, event);
    this.sessions.set(event.session_id, session);

    let summary;
    if (event.event_name === "session_completed") {
      summary = finalizeSessionSummary(session, this.manifest.evidence?.session_metrics, this.manifest.transfer_variants);
      const sessionPath = join(this.sessionDir, `${event.session_id}.json`);
      const outboxPath = join(this.outboxDir, `${event.session_id}.json`);
      writeFileSync(sessionPath, `${JSON.stringify(summary, null, 2)}\n`, "utf8");
      writeFileSync(outboxPath, `${JSON.stringify(summaryToFeishuFields(summary, this.unitRecordId), null, 2)}\n`, "utf8");
    }
    return {
      accepted: true,
      duplicate: false,
      event_id: event.event_id,
      session_id: event.session_id,
      summary,
    };
  }

  getSummary(sessionId) {
    if (!SAFE_ID.test(sessionId) || !sessionId.startsWith("session_")) return undefined;
    const memory = this.sessions.get(sessionId);
    if (memory) return finalizeSessionSummary(memory, this.manifest.evidence?.session_metrics, this.manifest.transfer_variants);
    const sessionPath = join(this.sessionDir, `${sessionId}.json`);
    if (!existsSync(sessionPath)) return undefined;
    return JSON.parse(readFileSync(sessionPath, "utf8"));
  }
}
