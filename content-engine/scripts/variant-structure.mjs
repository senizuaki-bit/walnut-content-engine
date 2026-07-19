import { SENSITIVE_CONTENT } from "./generation-common.mjs";

const EXPECTED_DIAGNOSES = Object.freeze({ exact: "SUCCESS", under: "COUNT_TOO_SMALL", over: "COUNT_TOO_LARGE" });

function invariant(condition, message) {
  if (!condition) throw new Error(message);
}

function exactKeys(value, keys, name) {
  invariant(value && typeof value === "object" && !Array.isArray(value), `${name} 必须是对象`);
  invariant(Object.keys(value).length === keys.length && keys.every((key) => Object.hasOwn(value, key)), `${name} 字段白名单不匹配`);
}

function cleanText(value, maximum, name) {
  const text = String(value ?? "").replace(/[\u0000-\u001f\u007f]/gu, " ").replace(/\s+/gu, " ").trim();
  invariant(text && text.length <= maximum, `${name} 必须是 1—${maximum} 个字符`);
  invariant(!SENSITIVE_CONTENT.test(text), `${name} 命中儿童内容敏感词`);
  return text;
}

export function executeVariantProbe(variant, repeatCount, maxExecutionSteps = 100) {
  const targetCount = Number(variant.params.target_count);
  let executionSteps = 2; // Sequence + Repeat
  let completedTargets = 0;
  let noTargetActions = 0;
  for (let index = 0; index < repeatCount; index += 1) {
    executionSteps += 2; // iteration + Action
    if (executionSteps > maxExecutionSteps) return { diagnosis_id: "STEP_LIMIT_EXCEEDED", execution_steps: executionSteps, completed_targets: completedTargets, no_target_actions: noTargetActions };
    if (completedTargets < targetCount) completedTargets += 1;
    else noTargetActions += 1;
  }
  const diagnosisId = noTargetActions > 0 ? "COUNT_TOO_LARGE" : completedTargets < targetCount ? "COUNT_TOO_SMALL" : "SUCCESS";
  return { diagnosis_id: diagnosisId, execution_steps: executionSteps, completed_targets: completedTargets, no_target_actions: noTargetActions };
}

export function validateTransferVariant(raw, unit) {
  exactKeys(raw, ["variant_id", "misconception_id", "skin", "params", "expected"], "变式");
  invariant(/^VAR-[A-Z0-9-]{4,72}$/u.test(raw.variant_id), "variant_id 必须是 VAR-* 机器 ID");
  invariant((unit.misconceptions ?? []).some((item) => item.id === raw.misconception_id), `未知 misconception_id：${raw.misconception_id}`);
  exactKeys(raw.skin, ["entity_type", "entity_name", "action_name", "objective", "scenario_frame"], "variant.skin");
  invariant(/^[a-z][a-z0-9_]{2,48}$/u.test(raw.skin.entity_type), "variant.skin.entity_type 必须是 snake_case");
  const skin = {
    entity_type: raw.skin.entity_type,
    entity_name: cleanText(raw.skin.entity_name, 24, "variant.skin.entity_name"),
    action_name: cleanText(raw.skin.action_name, 24, "variant.skin.action_name"),
    objective: cleanText(raw.skin.objective, 80, "variant.skin.objective"),
    scenario_frame: cleanText(raw.skin.scenario_frame, 100, "variant.skin.scenario_frame"),
  };
  exactKeys(raw.params, ["target_count"], "variant.params");
  const targetCount = Number(raw.params.target_count);
  invariant(Number.isInteger(targetCount) && targetCount >= 2 && targetCount <= 8, "variant.params.target_count 必须是 2—8 的整数");
  const answerLeak = new RegExp(`重复\\s*${targetCount}|${targetCount}\\s*[次遍]`, "u");
  invariant(!answerLeak.test(Object.values(skin).join(" ")), "变式表面文案泄露了正确循环次数");
  exactKeys(raw.expected, ["probe_count", "expected_diagnosis"], "variant.expected");
  invariant(Number(raw.expected.probe_count) === 3, "variant.expected.probe_count 必须为 3");
  exactKeys(raw.expected.expected_diagnosis, ["exact", "under", "over"], "variant.expected.expected_diagnosis");
  for (const [key, value] of Object.entries(EXPECTED_DIAGNOSES)) invariant(raw.expected.expected_diagnosis[key] === value, `expected_diagnosis.${key} 必须为 ${value}`);
  const variant = {
    variant_id: raw.variant_id,
    misconception_id: raw.misconception_id,
    skin,
    params: { target_count: targetCount },
    expected: { probe_count: 3, expected_diagnosis: { ...EXPECTED_DIAGNOSES } },
  };
  const probes = {
    exact: executeVariantProbe(variant, targetCount, unit.program_semantics.max_execution_steps),
    under: executeVariantProbe(variant, targetCount - 1, unit.program_semantics.max_execution_steps),
    over: executeVariantProbe(variant, targetCount + 1, unit.program_semantics.max_execution_steps),
  };
  for (const key of ["exact", "under", "over"]) invariant(probes[key].diagnosis_id === EXPECTED_DIAGNOSES[key], `变式 ${variant.variant_id} 的 ${key} 探针不满足同构证明`);
  return { variant, probes };
}

export function validateTransferVariants(variants, unit) {
  invariant(Array.isArray(variants), "transfer_variants 必须是数组");
  const results = variants.map((variant) => validateTransferVariant(variant, unit));
  invariant(results.length === new Set(results.map((item) => item.variant.variant_id)).size, "variant_id 不能重复");
  return results;
}

export { EXPECTED_DIAGNOSES };
