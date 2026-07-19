import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const STAGE_IDS = ["observe", "predict", "single_action", "program", "trace", "counterfactual", "transfer", "concept_name", "debug_boss", "explain"];
const SENSITIVE_CONTENT = /色情|裸露|赌博|毒品|自杀|自残|血腥|仇恨|歧视|恐怖主义|武器制作|联系方式|手机号|微信|QQ|学校|住址/iu;

function invariant(condition, message) {
  if (!condition) throw new Error(message);
}

function loadDotEnv(filePath) {
  if (!existsSync(filePath)) return;
  for (const line of readFileSync(filePath, "utf8").replace(/^\uFEFF/, "").split(/\r?\n/u)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const separator = trimmed.indexOf("=");
    if (separator < 1) continue;
    const key = trimmed.slice(0, separator).trim();
    let value = trimmed.slice(separator + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) value = value.slice(1, -1);
    if (!(key in process.env)) process.env[key] = value;
  }
}

const moduleDir = dirname(fileURLToPath(import.meta.url));
loadDotEnv(resolve(moduleDir, "..", "..", "xiao-hetao-ai-server", ".env"));

function cleanText(value, maxLength, name) {
  const text = String(value ?? "").replace(/[\u0000-\u001f\u007f]/gu, " ").replace(/\s+/gu, " ").trim();
  invariant(text && text.length <= maxLength, `${name} 必须是 1—${maxLength} 个字符`);
  invariant(!SENSITIVE_CONTENT.test(text), `${name} 命中儿童内容敏感词`);
  return text;
}

function exactKeys(value, required, optional, name) {
  invariant(value && typeof value === "object" && !Array.isArray(value), `${name} 必须是对象`);
  const allowed = new Set([...required, ...optional]);
  for (const key of Object.keys(value)) invariant(allowed.has(key), `${name} 含越权字段 ${key}`);
  for (const key of required) invariant(Object.hasOwn(value, key), `${name} 缺少字段 ${key}`);
}

export function nextMinorVersion(version) {
  const match = /^(\d+)\.(\d+)\.(\d+)$/u.exec(String(version));
  invariant(match, "基准模板 version 不是 semver");
  return `${match[1]}.${Number(match[2]) + 1}.0`;
}

export function themeSlug(theme) {
  const aliases = { "海底": "undersea", "太空": "space", "沙漠绿洲": "desert_oasis", "森林": "forest", "冰川": "glacier" };
  if (aliases[theme]) return aliases[theme];
  const ascii = String(theme).toLowerCase().replace(/[^a-z0-9]+/gu, "_").replace(/^_+|_+$/gu, "");
  return ascii || `theme_${createHash("sha256").update(String(theme)).digest("hex").slice(0, 8)}`;
}

export function validateGeneratedSkinPayload(raw, { theme } = {}) {
  exactKeys(raw, ["skin_id", "theme", "entity_type", "display", "stage_purposes", "hint_policy", "causal_copy"], [], "皮肤候选");
  invariant(/^skin_[a-z0-9_]{3,48}$/u.test(raw.skin_id), "skin_id 必须是 skin_* snake_case ID");
  invariant(/^[a-z][a-z0-9_]{2,48}$/u.test(raw.entity_type), "entity_type 必须是 snake_case ID");
  const normalizedTheme = cleanText(raw.theme, 30, "theme");
  if (theme) invariant(normalizedTheme === String(theme).trim(), "模型不得改写请求主题");

  exactKeys(raw.display, ["world_name", "entity_name", "action_name", "console_name", "objective", "scenario_frame"], [], "display");
  const display = Object.fromEntries(Object.entries(raw.display).map(([key, value]) => [key, cleanText(value, key === "objective" || key === "scenario_frame" ? 80 : 24, `display.${key}`)]));

  exactKeys(raw.stage_purposes, STAGE_IDS, [], "stage_purposes");
  const stagePurposes = {};
  for (const id of STAGE_IDS) stagePurposes[id] = cleanText(raw.stage_purposes[id], 100, `stage_purposes.${id}`);

  invariant(Array.isArray(raw.hint_policy) && raw.hint_policy.length === 5, "hint_policy 必须恰好有 5 级");
  const hints = raw.hint_policy.map((hint, index) => {
    exactKeys(hint, ["level", "intent", "template", "reveal_answer", "next_action"], ["needs_review"], `hint_policy[${index}]`);
    invariant(Number(hint.level) === index + 1, "提示等级必须连续为 1—5");
    invariant(Boolean(hint.reveal_answer) === (index === 4), `第 ${index + 1} 级 reveal_answer 不符合边界`);
    const template = cleanText(hint.template, 100, `hint_policy[${index}].template`);
    for (const match of template.matchAll(/\{([^{}]+)\}/gu)) {
      invariant(["main_target", "main_entity", "main_action"].includes(match[1]), `第 ${index + 1} 级含未知占位符 ${match[0]}`);
    }
    return {
      level: index + 1,
      intent: cleanText(hint.intent, 80, `hint_policy[${index}].intent`),
      template,
      reveal_answer: index === 4,
      ...(index === 4 ? { needs_review: true } : {}),
      next_action: cleanText(hint.next_action, 40, `hint_policy[${index}].next_action`),
    };
  });
  invariant(hints[4].template.includes("{main_target}"), "第 5 级提示必须保留 {main_target} 占位符");
  invariant(hints.some((hint) => hint.template.includes("{main_entity}") || hint.template.includes("{main_action}")), "提示模板应使用皮肤显示占位符");

  return {
    skin_id: raw.skin_id,
    theme: normalizedTheme,
    entity_type: raw.entity_type,
    display,
    stage_purposes: stagePurposes,
    hint_policy: hints,
    causal_copy: cleanText(raw.causal_copy, 100, "causal_copy"),
  };
}

export function skinQualityWarnings(payload) {
  const warnings = [];
  const entityName = String(payload?.display?.entity_name ?? "").trim();
  const actionName = String(payload?.display?.action_name ?? "").trim();
  const worldName = String(payload?.display?.world_name ?? "").trim();
  const consoleName = String(payload?.display?.console_name ?? "").trim();
  const objective = String(payload?.display?.objective ?? "").trim();
  const scenario = String(payload?.display?.scenario_frame ?? "").trim();
  const theme = String(payload?.theme ?? "").trim();
  const combinedCopy = `${worldName} ${entityName} ${actionName} ${consoleName} ${objective} ${scenario}`;
  if (/^(小?动物|目标|物体|对象|东西|能量体|任务点)$/u.test(entityName)) {
    warnings.push({ code: "GENERIC_ENTITY", message: "实体名过于泛化，应使用可数的具体世界对象，如珊瑚、信标或泉眼。" });
  }
  if (/^(游动|移动|前进|等待|观察|看看|行动|操作|处理)$/u.test(actionName)) {
    warnings.push({ code: "INTRANSITIVE_ACTION", message: "动作名缺少单目标因果，应使用能施加到一个实体上的动宾短语。" });
  }
  if ([...actionName].length < 3) {
    warnings.push({ code: "ACTION_MISSING_OBJECT", message: "动作名过短，应写成明确的动宾短语，如“点亮海星”而不是“点亮”。" });
  }
  const normalizedEntity = entityName.replace(/^(小|微光|星光|沉睡的?|发光的?)/u, "");
  let actionTargetsEntity = false;
  for (let length = Math.min(4, [...normalizedEntity].length); length >= 2 && !actionTargetsEntity; length -= 1) {
    const characters = [...normalizedEntity];
    for (let start = 0; start + length <= characters.length; start += 1) {
      if (actionName.includes(characters.slice(start, start + length).join(""))) {
        actionTargetsEntity = true;
        break;
      }
    }
  }
  if (!actionTargetsEntity) {
    warnings.push({ code: "ACTION_ENTITY_MISMATCH", message: "动作名没有明确指向实体核心名；动作必须作用于同一个可数目标。" });
  }
  if (entityName && !objective.includes(entityName)) {
    warnings.push({ code: "OBJECTIVE_MISSING_ENTITY", message: "目标文案没有复用实体显示名。" });
  }
  if (actionName && !objective.includes(actionName) && !scenario.includes(actionName)) {
    warnings.push({ code: "COPY_MISSING_ACTION", message: "目标或情境文案没有明确同一动作。" });
  }
  const themeEvidence = {
    "太空": /(太空|宇宙|星|轨道|行星|月球|银河|空间站|飞船|卫星)/u,
    "海底": /(海底|深海|海洋|潮汐|珊瑚|礁石|潜水|水下)/u,
    "沙漠绿洲": /(沙漠|绿洲|风沙|沙丘|泉眼)/u,
  };
  const evidencePattern = themeEvidence[theme];
  if (theme && !(evidencePattern ? evidencePattern.test(combinedCopy) : combinedCopy.includes(theme))) {
    warnings.push({ code: "THEME_EVIDENCE_MISSING", message: `世界名、实体、动作和情境没有体现请求主题“${theme}”。` });
  }
  if (theme === "太空" && /(海底|珊瑚|海星|小丑鱼|花朵|森林|草原|蒲公英|绒花|沙漠|绿洲|泉眼)/u.test(combinedCopy)) {
    warnings.push({ code: "THEME_CONFLICT", message: "太空主题混入了陆地、海底或其他世界的核心实体。" });
  }
  if (theme === "海底" && /(小行星|星球|轨道站|太空船|月球|草原|蒲公英|沙漠)/u.test(combinedCopy)) {
    warnings.push({ code: "THEME_CONFLICT", message: "海底主题混入了太空或陆地世界的核心实体。" });
  }
  return warnings;
}

export function buildSkinGenerationMessages(theme, mainTarget) {
  const system = `
你是儿童编程内容的“世界皮肤文案生成器”，只改表面情境，不接触教学判定。
只输出一个 JSON 对象，不输出 Markdown。主题必须原样写为“${theme}”。
允许字段仅为：skin_id、theme、entity_type、display、stage_purposes、hint_policy、causal_copy。skin_id 与 theme 会由程序强制覆盖，模型不得据此扩展任何规则。
display 仅含 world_name、entity_name、action_name、console_name、objective、scenario_frame。
stage_purposes 必须恰好含：${STAGE_IDS.join("、")}。
hint_policy 必须恰好 5 级，每级仅含 level、intent、template、reveal_answer、next_action；第5级可额外含 needs_review。
前4级 reveal_answer=false，不得说出正确次数；第5级 reveal_answer=true、needs_review=true，且 template 必须保留字面占位符 {main_target}。
文案可使用 {main_entity} 与 {main_action}，运行时会替换。结构始终是“对 N 个目标依次执行同一动作”，不要生成规则、代码、诊断、指标、安全策略或权重。
面向 8—12 岁儿童，温暖、具体、无暴力、无恐吓、无隐私索取。`.trim();
  return [
    { role: "system", content: `${system}\n实体名必须具体且可数，禁止使用“小动物、目标、物体、对象”等泛称；动作名必须是可施加到单个实体的动宾短语（如实体“微光珊瑚”对应“唤醒珊瑚”、实体“星光信标”对应“校准信标”），而且动作名必须包含实体的核心名，禁止实体是“小丑鱼”却写“唤醒珊瑚”，也禁止只写“游动、移动、等待、处理”。objective 或 scenario_frame 必须同时出现该实体名与动作名。world_name、entity_name、action_name、console_name 与 scenario_frame 必须全部属于请求主题“${theme}”，scenario_frame 必须直接写出“${theme}”字样；禁止为太空主题生成草原、花朵、蒲公英、森林、海底或沙漠内容。` },
    { role: "user", content: JSON.stringify({ theme, main_target_for_copy_context_only: mainTarget, request: "生成一套完整世界皮肤文案" }) },
  ];
}

const unavailableProviders = new Set();

function parseProviderList(value) {
  return String(value ?? "")
    .split(",")
    .map((item) => item.trim().toLowerCase())
    .filter((item) => item && item !== "none" && item !== "off");
}

function providerConfig(provider, purpose, overrides) {
  if (provider === "ark" || provider === "doubao") {
    const apiUrl = overrides.apiUrl
      ?? (purpose === "vision" ? process.env.ARK_VISION_API_URL : process.env.ARK_TEXT_API_URL)
      ?? "https://ark.cn-beijing.volces.com/api/v3/chat/completions";
    return {
      provider: "ark",
      label: "豆包",
      apiKey: overrides.apiKey ?? process.env.ARK_API_KEY ?? "",
      apiUrl: String(apiUrl),
      model: overrides.model
        ?? (purpose === "vision" ? process.env.ARK_VISION_MODEL : process.env.ARK_TEXT_MODEL)
        ?? "doubao-seed-2-0-pro-260215",
    };
  }
  if (provider === "deepseek") {
    const baseUrl = String(overrides.baseUrl ?? process.env.DEEPSEEK_BASE_URL ?? "https://api.deepseek.com").replace(/\/$/u, "");
    return {
      provider: "deepseek",
      label: "DeepSeek",
      apiKey: overrides.apiKey ?? process.env.DEEPSEEK_API_KEY ?? "",
      apiUrl: overrides.apiUrl ?? `${baseUrl}/chat/completions`,
      model: overrides.model ?? process.env.DEEPSEEK_MODEL ?? "deepseek-v4-flash",
    };
  }
  throw new Error(`不支持的生成模型供应商：${provider}`);
}

function jsonFromModelText(content, label) {
  invariant(typeof content === "string" && content.trim(), `${label} 未返回 JSON 文本`);
  const trimmed = content.trim();
  const candidates = [trimmed];
  const fenced = /^```(?:json)?\s*([\s\S]*?)\s*```$/iu.exec(trimmed)?.[1];
  if (fenced) candidates.push(fenced.trim());
  const firstBrace = trimmed.indexOf("{");
  const lastBrace = trimmed.lastIndexOf("}");
  if (firstBrace >= 0 && lastBrace > firstBrace) candidates.push(trimmed.slice(firstBrace, lastBrace + 1));
  for (const candidate of [...new Set(candidates)]) {
    try {
      const value = JSON.parse(candidate);
      if (value && typeof value === "object" && !Array.isArray(value)) return value;
    } catch {
      // Continue to the next safe extraction strategy. The caller still applies a strict field whitelist.
    }
  }
  throw new Error(`${label} 返回的内容不是合法 JSON 对象`);
}

function providerError(config, response, body) {
  const detail = String(body?.error?.message ?? body?.message ?? "").replace(/\s+/gu, " ").trim().slice(0, 300);
  const error = new Error(`${config.label} HTTP ${response.status}${detail ? `：${detail}` : ""}`);
  error.provider = config.provider;
  error.status = response.status;
  error.code = body?.error?.code ?? body?.code;
  error.retryable = response.status >= 500 || [408, 409, 425, 429].includes(response.status);
  error.providerUnavailable = [401, 403, 404].includes(response.status);
  return error;
}

async function callProviderJson(config, messages, options) {
  invariant(config.apiKey, `缺少 ${config.provider === "ark" ? "ARK_API_KEY" : "DEEPSEEK_API_KEY"}`);
  const timeoutMs = Number(options.timeoutMs ?? process.env.GENERATION_REQUEST_TIMEOUT_MS ?? 90_000);
  const maxAttempts = Number(options.maxAttempts ?? 3);
  let lastError;
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    try {
      const response = await fetch(config.apiUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${config.apiKey}` },
        body: JSON.stringify({
          model: config.model,
          messages,
          thinking: { type: "disabled" },
          response_format: { type: "json_object" },
          temperature: Number(options.temperature ?? process.env.GENERATION_TEMPERATURE ?? 0.2),
          max_tokens: Number(options.maxTokens ?? 2400),
          stream: false,
        }),
        signal: AbortSignal.timeout(timeoutMs),
      });
      const responseText = await response.text();
      let body;
      try { body = responseText ? JSON.parse(responseText) : {}; } catch { body = {}; }
      if (!response.ok) throw providerError(config, response, body);
      const content = body?.choices?.[0]?.message?.content;
      return {
        value: jsonFromModelText(content, config.label),
        provider: config.provider,
        model: body.model ?? config.model,
        usage: body.usage,
        request_id: response.headers.get("x-request-id") ?? body?.id,
        provider_attempts: attempt,
      };
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error));
      if (lastError.providerUnavailable || lastError.retryable === false) throw lastError;
    }
    if (attempt < maxAttempts) await new Promise((resolveDelay) => setTimeout(resolveDelay, 500 * attempt));
  }
  throw lastError ?? new Error(`${config.label} 请求失败`);
}

export async function callJsonModel(messages, overrides = {}) {
  const purpose = overrides.purpose === "vision" ? "vision" : "text";
  const primary = String(overrides.provider ?? (purpose === "vision" ? process.env.GENERATION_VISION_PROVIDER : process.env.GENERATION_TEXT_PROVIDER) ?? "ark").trim().toLowerCase();
  const configuredFallback = overrides.fallbackProvider
    ?? (purpose === "vision" ? process.env.GENERATION_VISION_FALLBACK_PROVIDER : process.env.GENERATION_TEXT_FALLBACK_PROVIDER)
    ?? (purpose === "vision" ? "" : "deepseek");
  const providers = [...new Set([primary, ...parseProviderList(configuredFallback)])];
  const failures = [];
  for (const provider of providers) {
    const config = providerConfig(provider, purpose, overrides);
    if (unavailableProviders.has(`${purpose}:${config.provider}:${config.model}`)) {
      failures.push({ provider: config.provider, model: config.model, error: "本进程内已确认模型不可用" });
      continue;
    }
    if (!config.apiKey) {
      failures.push({ provider: config.provider, model: config.model, error: "缺少 API Key" });
      continue;
    }
    try {
      const result = await callProviderJson(config, messages, overrides);
      return { ...result, fallback_used: config.provider !== providerConfig(primary, purpose, overrides).provider, failures };
    } catch (error) {
      const safeError = String(error instanceof Error ? error.message : error).replace(/\s+/gu, " ").trim().slice(0, 360);
      failures.push({ provider: config.provider, model: config.model, status: error?.status, code: error?.code, error: safeError });
      if (error?.providerUnavailable) unavailableProviders.add(`${purpose}:${config.provider}:${config.model}`);
    }
  }
  const error = new Error(`${purpose === "vision" ? "视觉质检" : "文案生成"}模型均不可用：${failures.map((item) => `${item.provider}/${item.model} ${item.error}`).join("；")}`);
  error.providerFailures = failures;
  error.providerUnavailable = failures.length > 0 && failures.every((item) => item.status === 401 || item.status === 403 || item.status === 404 || item.error === "缺少 API Key" || item.error === "本进程内已确认模型不可用");
  throw error;
}

export function mockSkinPayload(theme) {
  const slug = themeSlug(theme);
  const presets = {
    undersea: { world: "珊瑚回声湾", entity: "微光珊瑚", action: "唤醒珊瑚", console: "潮汐控制台", frame: "修复沉睡的珊瑚回声，让微光沿海湾依次亮起" },
    space: { world: "星环补给站", entity: "星光信标", action: "点亮信标", console: "轨道控制台", frame: "恢复星环上的补给信标，让航线重新连通" },
    desert_oasis: { world: "风沙绿洲", entity: "清泉芽点", action: "唤醒清泉", console: "绿洲控制台", frame: "沿古老水路依次唤醒清泉，让绿洲重新生长" },
  };
  const copy = presets[slug] ?? { world: `${theme}工坊`, entity: "能量目标", action: "唤醒目标", console: "法则控制台", frame: `修复${theme}里的能量法则` };
  return {
    skin_id: `skin_${slug}`,
    theme,
    entity_type: `${slug}_target`,
    display: {
      world_name: copy.world,
      entity_name: copy.entity,
      action_name: copy.action,
      console_name: copy.console,
      objective: `用“${copy.action}”让 {main_target} 个${copy.entity}依次醒来`,
      scenario_frame: copy.frame,
    },
    stage_purposes: {
      observe: `只展示等待中的${copy.entity}，不提前命名概念`,
      predict: `预测一次“${copy.action}”会改变几个目标`,
      single_action: `运行一次动作，让世界验证一次只影响一个目标`,
      program: `从自然语言目标进入积木结构，拖入“${copy.action}”并设置次数`,
      trace: `逐行高亮程序并与${copy.entity}的变化同步反馈`,
      counterfactual: `少执行一次，明确保留最后一个未完成目标`,
      transfer: `在陌生情境中无术语提示迁移同一结构`,
      concept_name: `最后命名循环，并显形 C 语言 for 代码`,
      debug_boss: `观察状态轨迹，修改条件后真实重跑`,
      explain: `用学习证据复盘预测、修改、迁移与 Debug`,
    },
    hint_policy: [
      { level: 1, intent: "确认当前世界目标", template: "先确认目标：你希望所有{main_entity}最后都完成变化，对吗？", reveal_answer: false, next_action: "确认当前目标" },
      { level: 2, intent: "观察结果与目标的偏差", template: "观察运行结果：哪一个{main_entity}没有按预期变化？", reveal_answer: false, next_action: "观察未变化目标" },
      { level: 3, intent: "缩小到可能出错的区域", template: "“{main_action}”已经有效，检查橙色重复结构里的执行次数。", reveal_answer: false, next_action: "检查执行次数" },
      { level: 4, intent: "提供轨迹但保留推断", template: "每执行一次只改变一个{main_entity}。沿轨迹补齐最后一步。", reveal_answer: false, next_action: "沿轨迹补齐一步" },
      { level: 5, intent: "给出兜底结构并标记复练", template: "完整结构是“重复{main_target}次：{main_action}”。仍由你亲手修改并运行。", reveal_answer: true, needs_review: true, next_action: "学生亲手修改并运行" },
    ],
    causal_copy: `{main_target} 个${copy.entity}按你的执行轨迹依次醒来。`,
  };
}

export { SENSITIVE_CONTENT, STAGE_IDS };
