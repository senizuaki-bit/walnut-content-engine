import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { runLark } from "./feishu-bridge.mjs";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const engineRoot = resolve(scriptDir, "..");
const config = JSON.parse(readFileSync(join(engineRoot, "feishu", "publish-config.json"), "utf8"));

const tableDefinitions = [
  {
    tableId: config.tables.content_units,
    fields: [
      {
        name: "主题",
        type: "select",
        multiple: false,
        description: "AI 世界工坊的表面情境；生成器不会改动诊断规则、程序语义或指标权重。",
        options: [
          { name: "海底", hue: "Blue", lightness: "Lighter" },
          { name: "太空", hue: "Purple", lightness: "Lighter" },
          { name: "沙漠绿洲", hue: "Orange", lightness: "Lighter" },
          { name: "森林", hue: "Green", lightness: "Lighter" },
          { name: "冰川", hue: "Wathet", lightness: "Lighter" },
        ],
      },
      { name: "生成请求", type: "checkbox", description: "勾选后由发布轮询器生成并机器试玩候选世界。" },
      { name: "恢复原版", type: "checkbox", description: "勾选后以新版本恢复官方数据花园；不调用生图模型，仍需审核后发布。" },
      { name: "候选预览", type: "attachment", description: "候选世界的拼图预览，供教研审核。" },
      { name: "候选审核通过", type: "checkbox", description: "教研确认候选后勾选；发布时仍会重新硬校验和 Godot 冒烟。" },
      { name: "候选路径", type: "text", description: "生成器写入的本地候选包路径。" },
      { name: "候选版本", type: "text" },
      { name: "候选哈希", type: "text", description: "候选 JSON 与全部素材共同计算的 SHA-256。" },
      { name: "候选结果", type: "text", description: "生成、校验、试玩或发布的状态摘要。" },
      { name: "图片生成状态", type: "text", description: "实时显示当前素材、等待时长、视觉质检、自动修复与 Godot 冒烟阶段。" },
      { name: "图片生成进度", type: "number", style: { type: "plain", precision: 0, percentage: false }, description: "世界工坊当前进度，范围 0–100。" },
      { name: "图片生成心跳", type: "text", description: "生成器最近一次正常回报时间（精确到秒）；请求中每 30 秒刷新。" },
    ],
  },
  {
    tableId: config.tables.classroom_evidence,
    fields: [
      { name: "变式ID", type: "text", description: "本次游戏事件使用的迁移变式。" },
      { name: "推荐变式ID", type: "text", description: "由会话主导误区自动映射的回访变式。" },
      { name: "回访发布", type: "checkbox", description: "教师勾选后，为该学生发布推荐变式。" },
      { name: "回访任务ID", type: "text" },
      { name: "回访发布结果", type: "text" },
    ],
  },
];

function listFields(tableId) {
  const data = runLark([
    "base", "+field-list",
    "--base-token", config.base_token,
    "--table-id", tableId,
    "--format", "json",
    "--as", "user",
  ], { cwd: engineRoot });
  return data.fields ?? [];
}

function createField(tableId, definition, index) {
  const stateDir = join(engineRoot, ".state", "field-definitions");
  mkdirSync(stateDir, { recursive: true });
  const payloadPath = join(stateDir, `${tableId}.${index}.json`);
  writeFileSync(payloadPath, `${JSON.stringify(definition, null, 2)}\n`, "utf8");
  const payloadArg = `@./${relative(engineRoot, payloadPath).replaceAll("\\", "/")}`;
  return runLark([
    "base", "+field-create",
    "--base-token", config.base_token,
    "--table-id", tableId,
    "--json", payloadArg,
    "--format", "json",
    "--as", "user",
  ], { cwd: engineRoot });
}

export function setupFeishuWorkshop() {
  const result = { created: [], existing: [] };
  for (const table of tableDefinitions) {
    const existing = new Set(listFields(table.tableId).map((field) => field.name));
    for (const [index, definition] of table.fields.entries()) {
      if (existing.has(definition.name)) {
        result.existing.push({ table_id: table.tableId, name: definition.name });
        continue;
      }
      const created = createField(table.tableId, definition, index);
      result.created.push({ table_id: table.tableId, name: definition.name, field: created.field ?? created });
      existing.add(definition.name);
    }
  }
  return result;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const result = setupFeishuWorkshop();
    console.log(`FEISHU_WORKSHOP_SCHEMA_OK created=${result.created.length} existing=${result.existing.length}`);
  } catch (error) {
    console.error(`FEISHU_WORKSHOP_SCHEMA_FAILED ${error instanceof Error ? error.message : String(error)}`);
    process.exitCode = 1;
  }
}
