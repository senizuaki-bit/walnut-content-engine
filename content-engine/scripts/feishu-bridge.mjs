import { spawnSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, relative, resolve } from "node:path";

function quoteCmd(value) {
  const text = String(value);
  if (!/[\s"&|<>^()]/u.test(text)) return text;
  return `"${text.replaceAll('"', '\\"')}"`;
}

export function runLark(args, { cwd } = {}) {
  const workdir = resolve(cwd ?? process.cwd());
  const executable = process.platform === "win32" ? (process.env.ComSpec || "cmd.exe") : "lark-cli";
  const executableArgs = process.platform === "win32" ? ["/d", "/s", "/c", ["lark-cli", ...args].map(quoteCmd).join(" ")] : args;
  const result = spawnSync(executable, executableArgs, { cwd: workdir, encoding: "utf8", windowsHide: true });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(result.stderr?.trim() || result.stdout?.trim() || `lark-cli 退出码 ${result.status}`);
  const parsed = JSON.parse(result.stdout);
  if (!parsed.ok) throw new Error(parsed.error?.message || "飞书命令执行失败");
  return parsed.data;
}

export function tableRows(data) {
  const names = data.fields ?? [];
  return (data.data ?? []).map((values, index) => ({
    record_id: data.record_id_list[index],
    fields: Object.fromEntries(names.map((name, fieldIndex) => [name, values[fieldIndex]])),
  }));
}

export function listRecords(config, tableId, cwd) {
  return tableRows(runLark(["base", "+record-list", "--base-token", config.base_token, "--table-id", tableId, "--format", "json", "--as", "user"], { cwd }));
}

export function updateRecord(config, tableId, recordId, fields, { cwd, statePath } = {}) {
  const workdir = resolve(cwd ?? process.cwd());
  const payloadPath = resolve(statePath ?? `${workdir}/.state/record-update.json`);
  mkdirSync(dirname(payloadPath), { recursive: true });
  writeFileSync(payloadPath, `${JSON.stringify(fields, null, 2)}\n`, "utf8");
  const cliPath = `@./${relative(workdir, payloadPath).replaceAll("\\", "/")}`;
  return runLark(["base", "+record-upsert", "--base-token", config.base_token, "--table-id", tableId, "--record-id", recordId, "--json", cliPath, "--format", "json", "--as", "user"], { cwd: workdir });
}

export function uploadAttachment(config, tableId, recordId, fieldId, filePath, cwd) {
  const workdir = resolve(cwd ?? process.cwd());
  const relativePath = `./${relative(workdir, resolve(filePath)).replaceAll("\\", "/")}`;
  if (relativePath.includes("../")) throw new Error("飞书附件必须位于内容引擎目录内");
  return runLark(["base", "+record-upload-attachment", "--base-token", config.base_token, "--table-id", tableId, "--record-id", recordId, "--field-id", fieldId, "--file", relativePath, "--format", "json", "--as", "user"], { cwd: workdir });
}
