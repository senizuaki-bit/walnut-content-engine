import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { callJsonModel, nextMinorVersion, skinQualityWarnings, themeSlug } from "./generation-common.mjs";
import { smokeTestCandidate } from "./smoke-test-candidate.mjs";
import { validateContentUnit } from "./validate-content.mjs";
import { validateTransferVariant, validateTransferVariants } from "./variant-structure.mjs";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const engineRoot = resolve(scriptDir, "..");
const projectRoot = resolve(engineRoot, "..");
const defaultTemplatePath = join(engineRoot, "source", "data-garden-loop.json");
const SUPPORTED_TRANSFER_MISCONCEPTIONS = new Set(["MIS-LOOP-UNDER", "MIS-LOOP-OVER", "MIS-LOOP-ACTION"]);

function invariant(condition, message) {
  if (!condition) throw new Error(message);
}

function tableRows(data) {
  const names = data.fields ?? [];
  return (data.data ?? []).map((values) => Object.fromEntries(names.map((name, index) => [name, values[index]])));
}

function larkMisconceptions() {
  const config = JSON.parse(readFileSync(join(engineRoot, "feishu", "publish-config.json"), "utf8"));
  invariant(config.tables?.misconceptions, "publish-config.json 缺少 tables.misconceptions");
  const command = ["base", "+record-list", "--base-token", config.base_token, "--table-id", config.tables.misconceptions, "--format", "json", "--as", "user"];
  const executable = process.platform === "win32" ? (process.env.ComSpec || "cmd.exe") : "lark-cli";
  const args = process.platform === "win32" ? ["/d", "/s", "/c", ["lark-cli", ...command].join(" ")] : command;
  const result = spawnSync(executable, args, { cwd: engineRoot, encoding: "utf8", windowsHide: true });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(result.stderr?.trim() || result.stdout?.trim() || "误区库读取失败");
  const envelope = JSON.parse(result.stdout);
  invariant(envelope.ok, envelope.error?.message ?? "误区库读取失败");
  return tableRows(envelope.data).map((row) => ({
    id: String(row["误区ID"] ?? ""),
    meaning: String(row["误区描述"] ?? ""),
    signal: String(row["可观察信号"] ?? ""),
    intervention: String(row["最小干预"] ?? ""),
    forbidden: String(row["禁止动作"] ?? ""),
  })).filter((item) => item.id);
}

function localMisconceptions(unit) {
  return unit.misconceptions.map(({ id, meaning, signal, intervention }) => ({ id, meaning, signal, intervention }));
}

function mockVariant(theme, misconception, index) {
  const slug = themeSlug(theme);
  const targetCount = 3 + (index % 4);
  const entity = theme === "海底" ? "潮汐浮标" : theme === "太空" ? "轨道信标" : `${theme}目标`;
  const action = theme === "海底" ? "校准浮标" : theme === "太空" ? "校准信标" : "依次校准";
  return {
    variant_id: `VAR-${misconception.id.replace(/^MIS-/u, "")}-${slug.replaceAll("_", "-").toUpperCase()}-${targetCount}`,
    misconception_id: misconception.id,
    skin: {
      entity_type: `${slug}_probe_target`,
      entity_name: entity,
      action_name: action,
      objective: `让所有${entity}恢复稳定`,
      scenario_frame: `在${theme}的新情境中，依次处理每一个${entity}`,
    },
    params: { target_count: targetCount },
    expected: { probe_count: 3, expected_diagnosis: { exact: "SUCCESS", under: "COUNT_TOO_SMALL", over: "COUNT_TOO_LARGE" } },
  };
}

function lockVariantKernel(raw, theme, misconception) {
  const targetCount = Number(raw?.params?.target_count);
  const slug = themeSlug(theme).replaceAll("_", "-").toUpperCase();
  return {
    ...raw,
    variant_id: `VAR-${misconception.id.replace(/^MIS-/u, "")}-${slug}-${Number.isInteger(targetCount) ? targetCount : "INVALID"}`,
    misconception_id: misconception.id,
    skin: {
      ...raw?.skin,
      entity_type: `${themeSlug(theme)}_transfer_target`,
    },
    expected: {
      probe_count: 3,
      expected_diagnosis: { exact: "SUCCESS", under: "COUNT_TOO_SMALL", over: "COUNT_TOO_LARGE" },
    },
  };
}

function variantMessages(theme, misconception) {
  const examples = [
    { context: "光种花园", structure: "对 5 颗光种重复生长", surface: "光种/生长" },
    { context: "巡检器", structure: "对 6 个目标重复巡检", surface: "巡检目标/巡检" },
  ];
  return [
    {
      role: "system",
      content: `你是迁移练习表面情境生成器。只输出 JSON，不输出 Markdown。只允许字段 variant_id、misconception_id、skin、params、expected。skin 只含 entity_type、entity_name、action_name、objective、scenario_frame；params 只含 target_count；expected 固定为三次探针及 SUCCESS/COUNT_TOO_SMALL/COUNT_TOO_LARGE。只换表面，结构必须仍是“对 N 个目标重复同一动作”。objective 和 scenario_frame 不得说“重复N次”或“N次”。实体名必须具体、可数并符合主题，禁止“小动物、目标、物体”等泛称。action_name 必须是至少 3 个汉字的动宾短语，并包含 entity_name 的核心名，如“海星→点亮海星、星光信标→校准信标”，禁止实体是“小丑鱼”却写“唤醒珊瑚”，也禁止只写“点亮、移动、处理”。objective 或 scenario_frame 必须原样包含 entity_name 与 action_name。面向8—12岁儿童，无暴力、恐吓、敏感内容。`,
    },
    { role: "user", content: JSON.stringify({ theme, misconception, few_shot: examples, expected_shape: { probe_count: 3, expected_diagnosis: { exact: "SUCCESS", under: "COUNT_TOO_SMALL", over: "COUNT_TOO_LARGE" } } }) },
  ];
}

export async function generateVariants({ themes = ["海底", "太空", "沙漠绿洲"], templatePath = defaultTemplatePath, version, outputRoot = join(engineRoot, "candidates", "variants"), mock = false, fromFeishu = false, runSmoke = true } = {}) {
  const template = JSON.parse(readFileSync(resolve(templatePath), "utf8"));
  const misconceptions = fromFeishu ? larkMisconceptions() : localMisconceptions(template);
  const allowedIds = new Set(template.misconceptions.map((item) => item.id));
  const eligible = misconceptions.filter((item) => allowedIds.has(item.id) && SUPPORTED_TRANSFER_MISCONCEPTIONS.has(item.id));
  invariant(eligible.length > 0, "没有可用于当前模板的误区");
  const variants = [];
  const audits = [];
  let index = 0;
  for (const misconception of eligible) {
    for (const theme of themes) {
      let raw;
      let audit = { mode: "mock", model: "deterministic-fixture" };
      if (mock) raw = mockVariant(theme, misconception, index);
      else {
        let lastError;
        for (let attempt = 1; attempt <= 3; attempt += 1) {
          const messages = variantMessages(theme, misconception);
          if (lastError) messages.push({ role: "user", content: `上一份 JSON 未通过结构或文案校验：${lastError.message}。保持同一教学结构，仅修正表面字段后输出完整 JSON。` });
          const response = await callJsonModel(messages);
          raw = lockVariantKernel(response.value, theme, misconception);
          try {
            const preview = validateTransferVariant(raw, template);
            const qualityWarnings = skinQualityWarnings({ display: preview.variant.skin, theme });
            if (qualityWarnings.length > 0) {
              lastError = new Error(qualityWarnings.map((warning) => warning.message).join("；"));
              if (attempt < 3) continue;
              raw = undefined;
              break;
            }
            audit = {
              mode: "api",
              provider: response.provider,
              model: response.model,
              usage: response.usage,
              request_id: response.request_id,
              provider_attempts: response.provider_attempts,
              fallback_used: response.fallback_used,
              failures: response.failures,
              validation_attempts: attempt,
              quality_warnings: qualityWarnings,
            };
            break;
          } catch (error) {
            lastError = error instanceof Error ? error : new Error(String(error));
          }
        }
        if (!raw || audit.mode !== "api") {
          audits.push({ status: "rejected", theme, misconception_id: misconception.id, error: lastError?.message ?? "变式候选未通过结构校验" });
          index += 1;
          continue;
        }
      }
      const checked = validateTransferVariant(raw, template);
      variants.push(checked.variant);
      audits.push({ status: "accepted", variant_id: checked.variant.variant_id, theme, misconception_id: misconception.id, probes: checked.probes, generation: audit });
      index += 1;
    }
  }
  invariant(variants.length > 0, "全部变式组合均被结构或文案质量校验拒绝");
  validateTransferVariants(variants, template);
  const unit = structuredClone(template);
  unit.version = version ?? nextMinorVersion(template.version);
  unit.status = "candidate";
  unit.transfer_variants = variants;
  unit.release = { ...unit.release, automatic_tests: false, research_review: false, safety_review: false };
  validateContentUnit(unit);
  const candidateDir = join(resolve(outputRoot), unit.version);
  mkdirSync(candidateDir, { recursive: true });
  const candidatePath = join(candidateDir, `${unit.unit_id}.${unit.version}.variants.candidate.json`);
  writeFileSync(candidatePath, `${JSON.stringify(unit, null, 2)}\n`, "utf8");
  const smoke = runSmoke ? smokeTestCandidate(candidatePath, {
    projectDir: join(projectRoot, "my_topdown_game-main"),
    godotExe: join(projectRoot, "tools", "godot-4.5.2", "Godot_v4.5.2-stable_win64_console.exe"),
  }) : { skipped: true };
  const auditPath = join(candidateDir, "variant-structure-audit.json");
  writeFileSync(auditPath, `${JSON.stringify({ generated_at: new Date().toISOString(), candidate_path: candidatePath, variants: audits, smoke }, null, 2)}\n`, "utf8");
  return { unit, candidatePath, auditPath, smoke };
}

function argument(name) {
  const prefix = `--${name}=`;
  return process.argv.find((value) => value.startsWith(prefix))?.slice(prefix.length);
}

async function runCli() {
  const themes = (argument("themes") ?? "海底,太空,沙漠绿洲").split(",").map((value) => value.trim()).filter(Boolean);
  const result = await generateVariants({
    themes,
    templatePath: argument("template") ?? defaultTemplatePath,
    version: argument("version"),
    outputRoot: argument("output") ?? join(engineRoot, "candidates", "variants"),
    mock: process.argv.includes("--mock"),
    fromFeishu: process.argv.includes("--from-feishu"),
    runSmoke: !process.argv.includes("--no-smoke"),
  });
  console.log(`VARIANT_CANDIDATES_OK ${result.unit.transfer_variants.length} ${result.candidatePath}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try { await runCli(); } catch (error) { console.error(`VARIANT_CANDIDATES_FAILED ${error instanceof Error ? error.message : String(error)}`); process.exitCode = 1; }
}
