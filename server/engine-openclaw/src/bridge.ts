/**
 * OpenClaw Engine Runner - Bridge Layer
 * 
 * Converts standard AgentRequest into OpenAI-compatible API calls
 * and transforms streaming responses back into standard EngineEvents.
 * 
 * Phase 1: Direct OpenAI-compatible streaming (works with DeepSeek, GPT-4, etc.)
 * Phase 2: Deep OpenClaw agent/tool/session integration
 */

import OpenAI from "openai";
import { execFile } from "child_process";
import { promisify } from "util";
import { promises as fs } from "fs";
import path from "path";

const execFilePromise = promisify(execFile);

// Standard Engine SPI types (must match Go's engine/spi.go)
export interface AgentRequest {
  session_id: string;
  messages: Array<{ role: string; content: string; tool_call_id?: string; name?: string }>;
  config: {
    model_name: string;
    base_url: string;
    api_key: string;
    max_tokens?: number;
    temperature?: number;
  };
  skills?: string[];
  role_id?: string;
  task_id?: string;
  project_id?: string;
  project_sources?: Array<{
    source_id: string;
    source_type: string;
    name: string;
    content_text?: string;
    file_path?: string;
    link_url?: string;
  }>;
  allowed_tools?: string[];
  plan_level?: string;
  mode: string;
  trace_id: string;
  tenant_id: string;
  user_id: string;
  client_id?: string;
}

export interface EngineEvent {
  type: "content" | "tool_call" | "tool_result" | "ui_component" | "usage" | "error" | "done";
  delta?: string;
  tool?: string;
  args?: Record<string, unknown>;
  result?: string;
  component?: string;
  component_args?: Record<string, unknown>;
  tokens_in?: number;
  tokens_out?: number;
  code?: string;
  message?: string;
}

const TOOLS = [
  {
    type: "function",
    function: {
      name: "artifact_render",
      description: "Render a structured artifact file (docx/xlsx/pdf/md/csv/json/pptx) into project output storage.",
      parameters: {
        type: "object",
        properties: {
          type: { type: "string", description: "Output type: docx/xlsx/pdf/md/csv/json/pptx/txt" },
          filename: { type: "string", description: "Target file name with extension" },
          payload: { type: "object", description: "Structured payload for rendering" },
          template_id: { type: "string", description: "Optional template id" },
          project_id: { type: "string", description: "Optional project identifier" }
        },
        required: ["type", "filename", "payload"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "artifact_bundle_zip",
      description: "Bundle previously rendered files into a zip package.",
      parameters: {
        type: "object",
        properties: {
          file_paths: {
            type: "array",
            items: { type: "string" },
            description: "Absolute file paths returned by artifact_render"
          },
          bundle_name: { type: "string", description: "Zip file name" },
          project_id: { type: "string", description: "Optional project identifier" }
        },
        required: ["file_paths"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "source_lookup",
      description: "Search project source snippets by keyword and return matching source summaries.",
      parameters: {
        type: "object",
        properties: {
          query: { type: "string", description: "Keyword query for source matching" },
          limit: { type: "number", description: "Maximum matched sources to return" }
        },
        required: ["query"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "ocr_extract",
      description: "Extract text from image files or URLs using OCR provider.",
      parameters: {
        type: "object",
        properties: {
          source_id: { type: "string", description: "Optional project source id" },
          image_path: { type: "string", description: "Local image path" },
          image_url: { type: "string", description: "Image URL" },
          language: { type: "string", description: "OCR language hint, e.g. zh/en" }
        },
        required: [],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "asr_transcribe",
      description: "Transcribe audio files or URLs to text using ASR provider.",
      parameters: {
        type: "object",
        properties: {
          source_id: { type: "string", description: "Optional project source id" },
          audio_path: { type: "string", description: "Local audio path" },
          audio_url: { type: "string", description: "Audio URL" },
          language: { type: "string", description: "Language hint, e.g. zh/en" }
        },
        required: [],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "tts_synthesize",
      description: "Synthesize text into audio output using TTS provider.",
      parameters: {
        type: "object",
        properties: {
          text: { type: "string", description: "Input text to synthesize" },
          voice: { type: "string", description: "Optional voice id" },
          format: { type: "string", description: "Output format, e.g. mp3/wav" },
          project_id: { type: "string", description: "Optional project identifier" }
        },
        required: ["text"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "execute_command",
      description: "Execute a shell command on the host terminal (Secure Terminal integration)",
      parameters: {
        type: "object",
        properties: {
          command: {
            type: "string",
            description: "The shell command to run (e.g., 'ls -la')",
          },
        },
        required: ["command"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "request_calendar",
      description: "Request a calendar UI component to be displayed to the user",
      parameters: {
        type: "object",
        properties: {},
        required: [],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "request_data_chart",
      description: "Request a visual data chart (Bar or Pie) to be displayed to the user",
      parameters: {
        type: "object",
        properties: {
          type: {
            type: "string",
            enum: ["bar", "pie"],
            description: "The type of chart to display"
          },
          title: {
            type: "string",
            description: "The title of the chart"
          },
          labels: {
            type: "array",
            items: { type: "string" },
            description: "Labels for each data point"
          },
          values: {
            type: "array",
            items: { type: "number" },
            description: "Numerical values for each data point"
          }
        },
        required: ["type", "title", "labels", "values"],
      },
    },
  },
];

const BLOCKED_COMMAND_FRAGMENTS = [
  "rm", "mv", "sudo", "chmod", "chown", "apt", "yum", "apk",
  "docker", "kubectl", "ssh", "scp", "nc", "nmap", "wget", "curl",
  "python -c", "bash -c", "sh -c"
];

const SHELL_META = /[|&;><`$]/;

const SAFE_COMMANDS_BY_PLAN: Record<string, Set<string>> = {
  free: new Set(["pwd", "ls", "cat", "echo", "whoami", "date", "uname", "head", "tail", "wc"]),
  pro: new Set(["pwd", "ls", "cat", "echo", "whoami", "date", "uname", "head", "tail", "wc", "grep", "find"]),
  team: new Set(["pwd", "ls", "cat", "echo", "whoami", "date", "uname", "head", "tail", "wc", "grep", "find", "ps"]),
  enterprise: new Set(["pwd", "ls", "cat", "echo", "whoami", "date", "uname", "head", "tail", "wc", "grep", "find", "ps"])
};

function isToolAllowed(req: AgentRequest, toolName: string): boolean {
  if (!req.allowed_tools || req.allowed_tools.length === 0) return false;
  return req.allowed_tools.includes(toolName);
}

function selectTools(req: AgentRequest) {
  if (!req.allowed_tools || req.allowed_tools.length === 0) {
    return [];
  }
  return TOOLS.filter((t: any) => req.allowed_tools!.includes(t.function.name));
}

function buildSkillSystemNote(skills?: string[]): string {
  if (!skills || skills.length === 0) return "";
  return `Active skills: ${skills.join(", ")}. Prioritize skill outcomes over model identity.`;
}

function buildRoleTaskNote(req: AgentRequest): string {
  const lines: string[] = [];
  if (req.role_id) lines.push(`Role: ${req.role_id}`);
  if (req.task_id) lines.push(`Task: ${req.task_id}`);
  if (req.project_id) lines.push(`Project: ${req.project_id}`);
  if (lines.length === 0) return "";
  return `Execution context:\n${lines.map((x) => `- ${x}`).join("\n")}`;
}

async function ensureDir(p: string): Promise<void> {
  await fs.mkdir(p, { recursive: true });
}

function sanitizeName(raw: string): string {
  const fallback = `artifact-${Date.now()}.json`;
  if (!raw || typeof raw !== "string") return fallback;
  return raw.replace(/[<>:"/\\|?*\x00-\x1F]/g, "_").trim() || fallback;
}

function detectProjectID(req: AgentRequest, toolArgs: any): string {
  if (typeof toolArgs?.project_id === "string" && toolArgs.project_id.trim() !== "") {
    return toolArgs.project_id.trim();
  }
  if (req.session_id && req.session_id.trim() !== "") {
    return req.session_id.trim();
  }
  return "default";
}

function artifactRoot(req: AgentRequest, projectID: string): string {
  const root = process.env.ARTIFACT_ROOT || path.resolve(process.cwd(), "artifacts");
  const tenantSafe = sanitizeName(req.tenant_id || "tenant");
  const projectSafe = sanitizeName(projectID);
  return path.join(root, tenantSafe, projectSafe);
}

async function toolArtifactRender(req: AgentRequest, toolArgs: any): Promise<string> {
  const projectID = detectProjectID(req, toolArgs);
  const dir = artifactRoot(req, projectID);
  await ensureDir(dir);

  const outputType = String(toolArgs?.type || "json").toLowerCase();
  const payload = toolArgs?.payload ?? {};
  const fileName = sanitizeName(String(toolArgs?.filename || `artifact-${Date.now()}.${outputType}`));
  const payloadB64 = Buffer.from(JSON.stringify(payload), "utf8").toString("base64");
  const scriptPath = path.resolve(process.cwd(), "scripts", "render_artifact.py");
  const { stdout } = await execFilePromise(
    "python",
    [
      scriptPath,
      "--type",
      outputType,
      "--filename",
      fileName,
      "--dir",
      dir,
      "--payload-b64",
      payloadB64,
    ],
    {
      timeout: 90000,
      maxBuffer: 1024 * 1024,
      shell: false,
    },
  );

  const parsed = JSON.parse(stdout.trim() || "{}");
  return JSON.stringify({
    file_path: parsed.output_path || "",
    filename: parsed.filename || fileName,
    requested_type: outputType,
    actual_type: parsed.actual_type || outputType,
    size_bytes: Number(parsed.size_bytes || 0),
    sha256: String(parsed.sha256 || ""),
    warning: String(parsed.warning || ""),
    project_id: projectID,
  });
}

async function toolArtifactBundleZip(req: AgentRequest, toolArgs: any): Promise<string> {
  const filePaths = Array.isArray(toolArgs?.file_paths) ? toolArgs.file_paths.map((x: any) => String(x)) : [];
  if (filePaths.length === 0) throw new Error("file_paths is required");

  const projectID = detectProjectID(req, toolArgs);
  const dir = artifactRoot(req, projectID);
  await ensureDir(dir);
  const bundleName = sanitizeName(String(toolArgs?.bundle_name || `bundle-${Date.now()}.zip`));
  const zipPath = path.join(dir, bundleName);

  try {
    await execFilePromise("python", ["-m", "zipfile", "-c", zipPath, ...filePaths], {
      timeout: 60000,
      maxBuffer: 512 * 1024,
      shell: false,
    });
    const stat = await fs.stat(zipPath);
    return JSON.stringify({
      bundle_path: zipPath,
      file_count: filePaths.length,
      size_bytes: stat.size,
      project_id: projectID,
    });
  } catch (err) {
    const fallbackPath = `${zipPath}.manifest.json`;
    const manifest = JSON.stringify(
      { bundle_path: zipPath, file_paths: filePaths, file_count: filePaths.length, project_id: projectID },
      null,
      2,
    );
    await fs.writeFile(fallbackPath, manifest, "utf8");
    return JSON.stringify({
      bundle_path: fallbackPath,
      file_count: filePaths.length,
      note: "zip tool unavailable, wrote manifest fallback",
      project_id: projectID,
    });
  }
}

async function toolSourceLookup(req: AgentRequest, toolArgs: any): Promise<string> {
  const query = String(toolArgs?.query || "").trim().toLowerCase();
  if (!query) throw new Error("query is required");
  const limit = Number.isFinite(toolArgs?.limit) ? Math.max(1, Math.min(20, Number(toolArgs.limit))) : 5;
  const projectID = detectProjectID(req, toolArgs);

  const requestSources = Array.isArray(req.project_sources) ? req.project_sources : [];
  if (requestSources.length > 0) {
    const filtered = requestSources.filter((r) => {
      const text = `${r.name || ""} ${r.content_text || ""} ${r.file_path || ""} ${r.link_url || ""}`.toLowerCase();
      return text.includes(query);
    }).slice(0, limit);
    return JSON.stringify({ query, project_id: projectID, count: filtered.length, items: filtered, source: "request.project_sources" });
  }

  const sourcePath = process.env.PROJECT_SOURCE_INDEX || path.resolve(process.cwd(), "artifacts", "project-sources.json");

  try {
    const raw = await fs.readFile(sourcePath, "utf8");
    const rows = JSON.parse(raw) as Array<Record<string, unknown>>;
    const filtered = rows.filter((r) => {
      const rowProject = String(r.project_id || "");
      if (rowProject && rowProject !== projectID) return false;
      const text = `${r.name || ""} ${r.content || ""} ${r.link_url || ""}`.toLowerCase();
      return text.includes(query);
    }).slice(0, limit);
    return JSON.stringify({ query, project_id: projectID, count: filtered.length, items: filtered });
  } catch {
    return JSON.stringify({
      query,
      project_id: projectID,
      count: 0,
      items: [],
      note: "project source index not found; create artifacts/project-sources.json to enable local lookup",
    });
  }
}

function readIntegrationEnv(prefix: "OCR" | "ASR" | "TTS"): { baseURL: string; token: string; model: string; voice: string } {
  return {
    baseURL: String(process.env[`${prefix}_API_BASE_URL`] || "").trim(),
    token: String(process.env[`${prefix}_API_TOKEN`] || "").trim(),
    model: String(process.env[`${prefix}_MODEL`] || "").trim(),
    voice: String(process.env[`${prefix}_VOICE`] || "").trim(),
  };
}

function findProjectSource(req: AgentRequest, sourceID: string): any | undefined {
  const rows = Array.isArray(req.project_sources) ? req.project_sources : [];
  return rows.find((x) => String(x.source_id || "") === sourceID);
}

async function httpJSON(url: string, token: string, payload: any): Promise<any> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 15000);
  try {
    const resp = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify(payload || {}),
      signal: controller.signal,
    });
    const text = await resp.text();
    let data: any = {};
    try {
      data = text ? JSON.parse(text) : {};
    } catch {
      data = { raw: text };
    }
    if (!resp.ok) {
      const msg = typeof data?.message === "string" ? data.message : `http ${resp.status}`;
      throw new Error(msg);
    }
    return data;
  } finally {
    clearTimeout(timer);
  }
}

async function toolOCRExtract(req: AgentRequest, toolArgs: any): Promise<string> {
  const env = readIntegrationEnv("OCR");
  if (!env.baseURL || !env.token) {
    throw new Error("OCR not configured. Set OCR_API_BASE_URL and OCR_API_TOKEN in engine environment.");
  }

  const sourceID = String(toolArgs?.source_id || "").trim();
  const src = sourceID ? findProjectSource(req, sourceID) : undefined;
  const imagePath = String(toolArgs?.image_path || src?.file_path || "").trim();
  const imageURL = String(toolArgs?.image_url || src?.link_url || "").trim();
  if (!imagePath && !imageURL) {
    throw new Error("ocr_extract needs image_path/image_url or a valid image source_id.");
  }

  const endpoint = `${env.baseURL.replace(/\/$/, "")}/ocr`;
  const payload = {
    image_path: imagePath || undefined,
    image_url: imageURL || undefined,
    language: String(toolArgs?.language || "").trim() || undefined,
    model: env.model || undefined,
  };
  const data = await httpJSON(endpoint, env.token, payload);
  const text = String(data?.text || data?.result?.text || "").trim();
  return JSON.stringify({
    text,
    confidence: data?.confidence ?? data?.result?.confidence ?? null,
    provider_response: data?.meta ?? {},
    source_id: sourceID || undefined,
  });
}

async function toolASRTranscribe(req: AgentRequest, toolArgs: any): Promise<string> {
  const env = readIntegrationEnv("ASR");
  if (!env.baseURL || !env.token) {
    throw new Error("ASR not configured. Set ASR_API_BASE_URL and ASR_API_TOKEN in engine environment.");
  }

  const sourceID = String(toolArgs?.source_id || "").trim();
  const src = sourceID ? findProjectSource(req, sourceID) : undefined;
  const audioPath = String(toolArgs?.audio_path || src?.file_path || "").trim();
  const audioURL = String(toolArgs?.audio_url || src?.link_url || "").trim();
  if (!audioPath && !audioURL) {
    throw new Error("asr_transcribe needs audio_path/audio_url or a valid audio source_id.");
  }

  const endpoint = `${env.baseURL.replace(/\/$/, "")}/asr/transcribe`;
  const payload = {
    audio_path: audioPath || undefined,
    audio_url: audioURL || undefined,
    language: String(toolArgs?.language || "").trim() || undefined,
    model: env.model || undefined,
  };
  const data = await httpJSON(endpoint, env.token, payload);
  const text = String(data?.text || data?.transcript || data?.result?.text || "").trim();
  return JSON.stringify({
    transcript: text,
    confidence: data?.confidence ?? data?.result?.confidence ?? null,
    provider_response: data?.meta ?? {},
    source_id: sourceID || undefined,
  });
}

async function toolTTSSynthesize(req: AgentRequest, toolArgs: any): Promise<string> {
  const env = readIntegrationEnv("TTS");
  if (!env.baseURL || !env.token) {
    throw new Error("TTS not configured. Set TTS_API_BASE_URL and TTS_API_TOKEN in engine environment.");
  }
  const text = String(toolArgs?.text || "").trim();
  if (!text) {
    throw new Error("tts_synthesize requires non-empty text.");
  }
  const format = String(toolArgs?.format || "mp3").trim() || "mp3";
  const voice = String(toolArgs?.voice || env.voice || "").trim();
  const projectID = detectProjectID(req, toolArgs);
  const dir = artifactRoot(req, projectID);
  await ensureDir(dir);

  const endpoint = `${env.baseURL.replace(/\/$/, "")}/tts/synthesize`;
  const payload = { text, format, voice: voice || undefined, model: env.model || undefined };
  const data = await httpJSON(endpoint, env.token, payload);

  let audioPath = String(data?.audio_path || "").trim();
  const audioURL = String(data?.audio_url || "").trim();
  const audioB64 = String(data?.audio_base64 || "").trim();

  if (!audioPath && audioB64) {
    const out = path.join(dir, sanitizeName(`tts-${Date.now()}.${format}`));
    await fs.writeFile(out, Buffer.from(audioB64, "base64"));
    audioPath = out;
  }

  if (!audioPath && !audioURL) {
    throw new Error("tts provider returned no audio payload.");
  }

  let sizeBytes = 0;
  if (audioPath) {
    try {
      sizeBytes = (await fs.stat(audioPath)).size;
    } catch {}
  }

  return JSON.stringify({
    output_type: "audio",
    format,
    audio_path: audioPath || "",
    audio_url: audioURL || "",
    size_bytes: sizeBytes,
    project_id: projectID,
  });
}

function buildToolBehaviorNote(allowedTools?: string[]): string {
  if (!allowedTools || allowedTools.length === 0) return "";
  const notes: string[] = [];

  if (allowedTools.includes("request_data_chart")) {
    notes.push(
      "When the user asks for a chart/plot/visualization, call request_data_chart with {type,title,labels,values}. Do not output matplotlib or other plotting code as a replacement."
    );
  }

  if (allowedTools.includes("execute_command")) {
    notes.push(
      "If terminal output is needed, call execute_command. Do not fabricate terminal commands or outputs."
    );
  }
  if (allowedTools.includes("artifact_render")) {
    notes.push(
      "When final deliverables are required, call artifact_render to produce downloadable artifacts instead of returning plain text only."
    );
  }
  if (allowedTools.includes("artifact_bundle_zip")) {
    notes.push(
      "When multiple files are produced, call artifact_bundle_zip with file_paths to return one bundled package."
    );
  }
  if (allowedTools.includes("source_lookup")) {
    notes.push(
      "Use source_lookup to retrieve project-scoped local sources before answering role task questions."
    );
  }
  if (allowedTools.includes("ocr_extract")) {
    notes.push(
      "When user asks to read text from images, call ocr_extract with source_id/image_path/image_url and quote extracted text."
    );
  }
  if (allowedTools.includes("asr_transcribe")) {
    notes.push(
      "When user asks to transcribe audio, call asr_transcribe with source_id/audio_path/audio_url before summarizing."
    );
  }
  if (allowedTools.includes("tts_synthesize")) {
    notes.push(
      "When user asks for audio output, call tts_synthesize and return the generated audio artifact details."
    );
  }

  return notes.join("\n");
}

function tokenizeCommand(input: string): string[] {
  const trimmed = input.trim();
  if (!trimmed) return [];
  return trimmed.split(/\s+/).filter(Boolean);
}

function validateAndParseCommand(raw: string, planLevel: string): { command: string; args: string[] } {
  const candidate = (raw || "").trim().toLowerCase();
  if (!candidate) {
    throw new Error("empty command is not allowed");
  }
  if (candidate.includes("\n") || candidate.includes("\r") || SHELL_META.test(candidate)) {
    throw new Error("shell metacharacters are not allowed");
  }
  if (BLOCKED_COMMAND_FRAGMENTS.some((frag) => candidate.includes(frag))) {
    throw new Error("command blocked by security policy");
  }

  const tokens = tokenizeCommand(raw);
  if (tokens.length === 0) {
    throw new Error("empty command is not allowed");
  }

  const executable = tokens[0];
  const allowed = SAFE_COMMANDS_BY_PLAN[planLevel] || SAFE_COMMANDS_BY_PLAN.free;
  if (!allowed.has(executable)) {
    throw new Error(`command '${executable}' is not allowed for plan ${planLevel}`);
  }

  return { command: executable, args: tokens.slice(1) };
}

/**
 * Execute an agent request and yield EngineEvents via a callback.
 * Implements a multi-turn tool execution loop.
 */
export async function executeAgentRequest(
  req: AgentRequest,
  onEvent: (event: EngineEvent) => void,
): Promise<void> {
  const { config, messages: initialMessages } = req;

  // Normalize base_url
  let baseURL = config.base_url;
  if (baseURL && !baseURL.endsWith("/v1")) {
    baseURL = baseURL.replace(/\/$/, "") + "/v1";
  }

  const client = new OpenAI({
    apiKey: config.api_key,
    baseURL,
  });

  // Maintain local history for tool turns
  const history: any[] = initialMessages.map(m => ({
    role: m.role,
    content: m.content,
    tool_call_id: m.tool_call_id,
    name: m.name,
  }));
  const skillNote = buildSkillSystemNote(req.skills);
  const roleTaskNote = buildRoleTaskNote(req);
  const toolBehaviorNote = buildToolBehaviorNote(req.allowed_tools);
  const mergedNote = [skillNote, roleTaskNote, toolBehaviorNote].filter(Boolean).join("\n");
  if (mergedNote) {
    if (history.length > 0 && history[0].role === "system") {
      history[0].content = `${history[0].content}\n\n${mergedNote}`;
    } else {
      history.unshift({ role: "system", content: mergedNote });
    }
  }

  let totalTokensIn = 0;
  let totalTokensOut = 0;
  let loopCount = 0;
  const MAX_LOOPS = 5;

  try {
    while (loopCount < MAX_LOOPS) {
      loopCount++;
      
      const availableTools = selectTools(req);
      const requestPayload: any = {
        model: config.model_name,
        messages: history,
        max_tokens: config.max_tokens || 4096,
        temperature: config.temperature ?? 0.7,
        stream: true,
        stream_options: { include_usage: true },
      };
      if (availableTools.length > 0) {
        requestPayload.tools = availableTools as any;
      }
      const stream: any = await client.chat.completions.create(requestPayload as any);

      let currentAssistantMessage: any = { role: "assistant", content: "", tool_calls: [] };

      for await (const chunk of stream) {
        const choice = chunk.choices?.[0];
        const delta = choice?.delta;

        if (delta?.content) {
          currentAssistantMessage.content += delta.content;
          onEvent({ type: "content", delta: delta.content });
        }

        if (delta?.tool_calls) {
          for (const tc of delta.tool_calls) {
            const index = tc.index;
            if (!currentAssistantMessage.tool_calls[index]) {
              currentAssistantMessage.tool_calls[index] = {
                id: tc.id,
                type: "function",
                function: { name: "", arguments: "" }
              };
            }
            if (tc.id) currentAssistantMessage.tool_calls[index].id = tc.id;
            if (tc.function?.name) currentAssistantMessage.tool_calls[index].function.name = tc.function.name;
            if (tc.function?.arguments) currentAssistantMessage.tool_calls[index].function.arguments += tc.function.arguments;
          }
        }

        if (chunk.usage) {
          totalTokensIn += chunk.usage.prompt_tokens || 0;
          totalTokensOut += chunk.usage.completion_tokens || 0;
        }
      }

      history.push(currentAssistantMessage);

      // Check if we have tool calls to execute
      const toolCalls = currentAssistantMessage.tool_calls.filter((tc: any) => tc.function.name);
      if (toolCalls.length === 0) {
        break; // No more tools, finish loop
      }

      const planLevel = (req.plan_level || "free").toLowerCase();

      // Execute tools
      for (const tc of toolCalls) {
        const toolName = tc.function.name;
        let toolArgs: any = {};
        try {
          toolArgs = JSON.parse(tc.function.arguments || "{}");
        } catch (e) {
          console.error(`[${req.trace_id}] Failed to parse tool args:`, tc.function.arguments);
        }
        
        if (!isToolAllowed(req, toolName)) {
          onEvent({
            type: "error",
            code: "SECURITY_RESTRICTION",
            message: `Tool '${toolName}' is not allowed for plan '${planLevel}'.`,
          });
          return;
        }

        onEvent({ type: "tool_call", tool: toolName, args: toolArgs });

        let result = "";
        try {
          if (toolName === "execute_command") {
            const rawCommand = String(toolArgs.command || "");
            const parsed = validateAndParseCommand(rawCommand, planLevel);
            onEvent({ type: "content", delta: `\n> [OpenClaw Terminal]: ${parsed.command} ${parsed.args.join(" ")}\n` });
            const { stdout, stderr } = await execFilePromise(parsed.command, parsed.args, {
              timeout: 30000,
              maxBuffer: 256 * 1024,
              shell: false,
            });
            result = (stdout + stderr).trim() || "[No output]";
          } else if (toolName === "artifact_render") {
            result = await toolArtifactRender(req, toolArgs);
            try {
              const parsed = JSON.parse(result);
              onEvent({
                type: "ui_component",
                component: "artifact_file",
                component_args: parsed,
              });
            } catch {}
          } else if (toolName === "artifact_bundle_zip") {
            result = await toolArtifactBundleZip(req, toolArgs);
            try {
              const parsed = JSON.parse(result);
              onEvent({
                type: "ui_component",
                component: "artifact_bundle",
                component_args: parsed,
              });
            } catch {}
          } else if (toolName === "source_lookup") {
            result = await toolSourceLookup(req, toolArgs);
          } else if (toolName === "ocr_extract") {
            result = await toolOCRExtract(req, toolArgs);
          } else if (toolName === "asr_transcribe") {
            result = await toolASRTranscribe(req, toolArgs);
          } else if (toolName === "tts_synthesize") {
            result = await toolTTSSynthesize(req, toolArgs);
            try {
              const parsed = JSON.parse(result);
              onEvent({
                type: "ui_component",
                component: "artifact_file",
                component_args: {
                  filename: parsed.audio_path ? path.basename(String(parsed.audio_path)) : "tts-output",
                  file_path: parsed.audio_path || parsed.audio_url || "",
                  requested_type: parsed.format || "audio",
                  actual_type: parsed.format || "audio",
                  size_bytes: Number(parsed.size_bytes || 0),
                  project_id: parsed.project_id || "",
                },
              });
            } catch {}
          } else if (toolName === "request_calendar") {
            // Demo UI Component trigger
            onEvent({ 
              type: "ui_component", 
              component: "calendar", 
              component_args: { initial_date: new Date().toISOString() } 
            });
            result = "UI Component 'calendar' requested.";
          } else if (toolName === "request_data_chart") {
            // Visual Data Chart trigger
            onEvent({ 
              type: "ui_component", 
              component: "data_chart", 
              component_args: { 
                type: toolArgs.type,
                title: toolArgs.title,
                labels: toolArgs.labels,
                values: toolArgs.values
              } 
            });
            result = `UI Component 'data_chart' (${toolArgs.type}) requested.`;
          } else {
            result = `Error: Unknown tool ${toolName}`;
          }
        } catch (err: any) {
          result = `Error executing command: ${err.message}`;
        }

        history.push({
          role: "tool",
          tool_call_id: tc.id,
          name: toolName,
          content: result,
        });

        onEvent({ type: "tool_result", tool: toolName, result });

        if (toolName === "execute_command") {
          onEvent({ type: "content", delta: `\n< [Terminal Output]:\n${result}\n` });
        }
      }
      
      // Continue to next turn with tool results
    }

    onEvent({
      type: "usage",
      tokens_in: totalTokensIn,
      tokens_out: totalTokensOut,
    });
    onEvent({ type: "done" });

  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(`[bridge] Execution FAILED: ${message}`);
    onEvent({
      type: "error",
      code: "ENGINE_ERROR",
      message: message,
    });
  }
}
