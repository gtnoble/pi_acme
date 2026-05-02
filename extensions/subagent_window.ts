/**
 * subagent_window — spawn a pi_acme subagent in a dedicated acme window.
 *
 * Registers the `spawn_subagent` tool.  When the LLM calls it, a new
 * pi_acme process is spawned with --prompt, --one-shot, and --no-session.
 * The window shows the subagent working in real time and closes
 * automatically when the agent turn completes.  The final assistant text
 * (or an error description) is returned to the parent agent as the tool
 * result.
 *
 * Installation:
 *   ln -s /path/to/pi_acme/extensions/subagent_window.ts \
 *         ~/.pi/agent/extensions/subagent_window.ts
 *
 * The PI_ACME_BIN environment variable is injected by pi_acme when it
 * spawns the pi --mode rpc subprocess, so the extension can always find
 * the binary that launched it.
 */

import { spawn } from "node:child_process";
import * as fs from "node:fs";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";

/**
 * Resolve the pi_acme binary path.
 *
 * Priority:
 *  1. PI_ACME_BIN env var (set by pi_acme before spawning pi)
 *  2. "pi_acme" on PATH (fallback for manual invocations)
 */
function findPiAcme(): string {
  const fromEnv = process.env["PI_ACME_BIN"];
  if (fromEnv && fs.existsSync(fromEnv)) {
    return fromEnv;
  }
  return "pi_acme";
}

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "spawn_subagent",
    label: "Spawn Subagent",
    description: [
      "Spawn a subagent in a new pi_acme window.",
      "The window displays the subagent working in real time and closes",
      "automatically when the agent turn completes.",
      "Returns the subagent's final response text, or an error string.",
    ].join(" "),

    parameters: Type.Object({
      prompt: Type.String({
        description: "Task or question for the subagent.",
      }),
      model: Type.Optional(
        Type.String({
          description:
            'Model to use, in "provider/model-id" form.  Defaults to the current model.',
        }),
      ),
      agent: Type.Optional(
        Type.String({
          description:
            "System-prompt text or path to an .agent.md file for the subagent.",
        }),
      ),
      name: Type.Optional(
        Type.String({
          description:
            "Short label for the subagent window's tagline.  Displayed as" +
            ' "CWD/+pi:label | …" so concurrent subagent windows are easy' +
            " to tell apart.",
        }),
      ),
    }),

    async execute(_toolCallId, params, signal) {
      const piAcme = findPiAcme();

      const args: string[] = [
        "--prompt",
        params.prompt,
        "--one-shot",
        // --no-session is implied by --one-shot in pi_acme, but pass it
        // explicitly for clarity and forward-compatibility.
        "--no-session",
      ];

      if (params.model) {
        args.push("--model", params.model);
      }
      if (params.agent) {
        args.push("--agent", params.agent);
      }
      if (params.name) {
        args.push("--name", params.name);
      }

      return new Promise((resolve) => {
        const proc = spawn(piAcme, args, {
          cwd: process.cwd(),
          // stdin closed: subagent reads no user input.
          // stdout piped: we read the JSON result line.
          // stderr ignored: subagent writes diagnostics to its acme window.
          stdio: ["ignore", "pipe", "ignore"],
          shell: false,
        });

        let stdout = "";
        proc.stdout.on("data", (chunk: Buffer) => {
          stdout += chunk.toString("utf8");
        });

        proc.on("close", (code: number | null) => {
          // pi_acme prints exactly one JSON line to stdout before exiting
          // in --one-shot mode.  Parse the last non-empty line to be
          // robust against any stray output.
          let resultJson: { output?: string; error?: string } = {};
          const lines = stdout.trim().split("\n");
          for (let i = lines.length - 1; i >= 0; i--) {
            const line = lines[i].trim();
            if (!line) continue;
            try {
              resultJson = JSON.parse(line);
              break;
            } catch {
              // not JSON — keep scanning backwards
            }
          }

          if (resultJson.output !== undefined) {
            resolve({
              content: [{ type: "text", text: resultJson.output }],
              details: {},
            });
          } else {
            const errorText =
              resultJson.error ??
              (code !== 0
                ? `pi_acme exited with code ${code}`
                : "subagent produced no output");
            resolve({
              content: [{ type: "text", text: `[subagent error] ${errorText}` }],
              details: {},
              isError: true,
            });
          }
        });

        proc.on("error", (err: Error) => {
          resolve({
            content: [
              {
                type: "text",
                text: `[subagent error] failed to spawn pi_acme: ${err.message}`,
              },
            ],
            details: {},
            isError: true,
          });
        });

        // Honour the tool-call abort signal: terminate the subagent window.
        if (signal) {
          const kill = () => {
            try {
              proc.kill("SIGTERM");
            } catch {
              // already gone
            }
          };
          if (signal.aborted) {
            kill();
          } else {
            signal.addEventListener("abort", kill, { once: true });
          }
        }
      });
    },
  });
}
