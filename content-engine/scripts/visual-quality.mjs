import { createHash } from "node:crypto";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { extname } from "node:path";
import { callJsonModel } from "./generation-common.mjs";

const VISUAL_QUALITY_CONTRACT_VERSION = 2;
const ASSET_KEYS = new Set(["background_before", "background_after", "target_entity", "console", "npc"]);
const ISSUE_CODES = new Set([
  "THEME_MISMATCH",
  "BEFORE_AFTER_INCONSISTENT",
  "TARGET_COPY_MISMATCH",
  "SPRITE_BACKGROUND_DIRTY",
  "STYLE_INCONSISTENT",
  "TEXT_OR_WATERMARK",
  "CHILD_SAFETY",
  "OTHER",
]);

function invariant(condition, message) {
  if (!condition) throw new Error(message);
}

function exactKeys(value, required, optional, name) {
  invariant(value && typeof value === "object" && !Array.isArray(value), `${name} 必须是对象`);
  const allowed = new Set([...required, ...optional]);
  for (const key of Object.keys(value)) invariant(allowed.has(key), `${name} 含越权字段 ${key}`);
  for (const key of required) invariant(Object.hasOwn(value, key), `${name} 缺少字段 ${key}`);
}

function cleanText(value, maxLength, name) {
  const text = String(value ?? "").replace(/[\u0000-\u001f\u007f]/gu, " ").replace(/\s+/gu, " ").trim();
  invariant(text && text.length <= maxLength, `${name} 必须是 1—${maxLength} 个字符`);
  return text;
}

function truthyEnv(name, defaultValue = false) {
  const value = process.env[name];
  if (value == null || value === "") return defaultValue;
  return /^(1|true|yes|on)$/iu.test(value);
}

function mimeType(filePath) {
  const extension = extname(filePath).toLowerCase();
  if (extension === ".jpg" || extension === ".jpeg") return "image/jpeg";
  if (extension === ".webp") return "image/webp";
  return "image/png";
}

function previewFingerprint(previewPath, context) {
  return createHash("sha256")
    .update(String(VISUAL_QUALITY_CONTRACT_VERSION))
    .update("\0")
    .update(JSON.stringify(context))
    .update("\0")
    .update(readFileSync(previewPath))
    .digest("hex");
}

export function validateVisualQualityPayload(raw) {
  exactKeys(raw, ["theme_match", "before_after_consistent", "target_matches_copy", "sprites_clean", "style_consistent", "child_safe", "summary", "issues"], [], "视觉质检结果");
  const flags = {};
  for (const key of ["theme_match", "before_after_consistent", "target_matches_copy", "sprites_clean", "style_consistent", "child_safe"]) {
    invariant(typeof raw[key] === "boolean", `视觉质检结果.${key} 必须是布尔值`);
    flags[key] = raw[key];
  }
  invariant(Array.isArray(raw.issues) && raw.issues.length <= 12, "视觉质检 issues 必须是最多 12 项的数组");
  const issues = raw.issues.map((issue, index) => {
    exactKeys(issue, ["code", "severity", "asset_keys", "message"], [], `视觉质检 issues[${index}]`);
    const code = String(issue.code ?? "").trim().toUpperCase();
    invariant(ISSUE_CODES.has(code), `视觉质检 issues[${index}].code 不在白名单`);
    const severity = String(issue.severity ?? "").trim().toLowerCase();
    invariant(severity === "warning" || severity === "blocking", `视觉质检 issues[${index}].severity 无效`);
    invariant(Array.isArray(issue.asset_keys) && issue.asset_keys.length >= 1 && issue.asset_keys.length <= 5, `视觉质检 issues[${index}].asset_keys 无效`);
    const assetKeys = [...new Set(issue.asset_keys.map((value) => String(value).trim()))];
    invariant(assetKeys.every((value) => ASSET_KEYS.has(value)), `视觉质检 issues[${index}].asset_keys 含未知素材`);
    return { code, severity, asset_keys: assetKeys, message: cleanText(issue.message, 160, `视觉质检 issues[${index}].message`) };
  });
  const passed = Object.values(flags).every(Boolean) && !issues.some((issue) => issue.severity === "blocking");
  return { status: passed ? "passed" : "failed", passed, ...flags, summary: cleanText(raw.summary, 240, "视觉质检 summary"), issues };
}

function mockResult() {
  return {
    status: "passed",
    passed: true,
    theme_match: true,
    before_after_consistent: true,
    target_matches_copy: true,
    sprites_clean: true,
    style_consistent: true,
    child_safe: true,
    summary: "离线夹具视觉质检通过。",
    issues: [],
    provider_audit: { mode: "mock", provider: "fixture", model: "deterministic-fixture" },
  };
}

function visualMessages(context, previewPath, correction = "") {
  const image = readFileSync(previewPath).toString("base64");
  const instructions = `
你是儿童编程游戏世界皮肤的视觉质检器。只检查表面美术，不判断教学规则，只输出一个 JSON 对象，不输出 Markdown。
预览图布局固定为：上排左侧=修复前世界，上排右侧=修复后世界；下排从左到右=目标实体、控制台、可选 NPC。
必须逐项判断：
1. 是否明显符合主题；
2. 修复前/后是否保持相同镜头、主要地形轮廓、道路和关键物体布局，仅状态与氛围发生因果变化；
3. 目标实体是否与文案实体及动作相符；
4. 三张精灵是否轮廓清楚、没有大块不透明方形底；
5. 五张素材的像素画风、调色板和光照是否一致；
6. 是否无文字、水印、暴力、恐吓、裸露或其他儿童不宜内容。
仅允许字段：theme_match、before_after_consistent、target_matches_copy、sprites_clean、style_consistent、child_safe、summary、issues。
前六项必须是布尔值。issues 最多 12 项，每项仅含 code、severity、asset_keys、message；severity 仅允许 warning 或 blocking；code 仅允许 ${[...ISSUE_CODES].join("、")}；asset_keys 必须从 ${[...ASSET_KEYS].join("、")} 中选择受影响素材。
任何前六项为 false 时，issues 必须包含对应的 blocking 项并准确标出需要重生成的素材。不要因为画面漂亮而忽略镜头或布局被重画。
`.trim();
  return [
    { role: "system", content: instructions },
    {
      role: "user",
      content: [
        { type: "text", text: JSON.stringify({ ...context, correction: correction || undefined }) },
        { type: "image_url", image_url: { url: `data:${mimeType(previewPath)};base64,${image}`, detail: "high" } },
      ],
    },
  ];
}

export async function inspectCandidatePreview({ previewPath, context, checkpointPath, mock = false, resume = true, required = truthyEnv("GENERATION_VISION_REQUIRED", false) } = {}) {
  invariant(previewPath && existsSync(previewPath), "视觉质检缺少候选预览图");
  invariant(context && typeof context === "object", "视觉质检缺少候选上下文");
  const fingerprint = previewFingerprint(previewPath, context);
  if (mock) return { ...mockResult(), fingerprint };
  if (resume && checkpointPath && existsSync(checkpointPath)) {
    try {
      const checkpoint = JSON.parse(readFileSync(checkpointPath, "utf8"));
      if (checkpoint.contract_version === VISUAL_QUALITY_CONTRACT_VERSION && checkpoint.fingerprint === fingerprint) {
        const checked = validateVisualQualityPayload(checkpoint.result);
        return { ...checked, fingerprint, provider_audit: { ...checkpoint.provider_audit, mode: "resume-visual-checkpoint" } };
      }
    } catch {
      // A stale or malformed checkpoint must never bypass a fresh inspection.
    }
  }

  let lastError;
  for (let validationAttempt = 1; validationAttempt <= 2; validationAttempt += 1) {
    try {
      const response = await callJsonModel(visualMessages(context, previewPath, lastError?.message), {
        purpose: "vision",
        maxTokens: 1200,
        maxAttempts: 2,
      });
      const checked = validateVisualQualityPayload(response.value);
      const providerAudit = {
        mode: "api",
        provider: response.provider,
        model: response.model,
        usage: response.usage,
        request_id: response.request_id,
        provider_attempts: response.provider_attempts,
        validation_attempts: validationAttempt,
        fallback_used: response.fallback_used,
        failures: response.failures,
      };
      if (checkpointPath) {
        writeFileSync(checkpointPath, `${JSON.stringify({
          contract_version: VISUAL_QUALITY_CONTRACT_VERSION,
          fingerprint,
          checked_at: new Date().toISOString(),
          result: checked,
          provider_audit: providerAudit,
        }, null, 2)}\n`, "utf8");
      }
      return { ...checked, fingerprint, provider_audit: providerAudit };
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error));
      if (lastError.providerUnavailable) break;
    }
  }
  const unavailable = {
    status: "unavailable",
    passed: null,
    blocking: required,
    summary: `豆包视觉质检暂不可用：${String(lastError?.message ?? "未知错误").replace(/\s+/gu, " ").slice(0, 300)}`,
    issues: [{ code: "OTHER", severity: required ? "blocking" : "warning", asset_keys: ["background_after"], message: "请在火山方舟控制台开通并授权 ARK_VISION_MODEL 后重试。" }],
    fingerprint,
    provider_audit: { mode: "unavailable", failures: lastError?.providerFailures ?? [], required },
  };
  return unavailable;
}
