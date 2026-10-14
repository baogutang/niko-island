import Foundation

/// Files we own outright inside agent config directories.
public enum PluginTemplates {
    /// Hook file for agents that load self-contained hook files. Same JSON
    /// shape as the shared-settings adapter, plus (unless the agent is strict
    /// about keys) a note for whoever opens it.
    public static func hookFile(agent: AgentDescriptor, events: [HookSpec], paths: NikoPaths, note: Bool = true) -> String {
        var hooks = JSONObject()
        for spec in events {
            hooks[spec.event] = .array([HookMerge.group(spec: spec, command: command(agent, paths))])
        }
        var root = JSONObject()
        if note { root["_comment"] = .string("Managed by Niko Island (niko-bridge). `niko-island uninstall` removes this file.") }
        root["hooks"] = .object(hooks)
        return JSONValue.object(root).serialized(.pretty)
    }

    /// Copilot CLI: `{ "version": 1, "hooks": { event: [{ "type", "bash", "timeoutSec" }] } }`.
    public static func copilotHookFile(agent: AgentDescriptor, events: [HookSpec], paths: NikoPaths) -> String {
        var hooks = JSONObject()
        for spec in events {
            hooks[spec.event] = .array([.object([
                "type": .string("command"),
                "bash": .string(command(agent, paths, event: spec.event)),
                "timeoutSec": .int(spec.timeout ?? HookSpec.quickTimeout),
            ])])
        }
        return JSONValue.object(["version": .int(1), "hooks": .object(hooks)]).serialized(.pretty)
    }

    /// Kiro: `{ "version": "v1", "hooks": [{ "name", "trigger", "action": { "type", "command" }, "timeout", "enabled" }] }`.
    public static func kiroHookFile(agent: AgentDescriptor, events: [HookSpec], paths: NikoPaths) -> String {
        let hooks: [JSONValue] = events.map { spec in
            var entry = JSONObject()
            entry["name"] = .string("niko-island-\(spec.event)")
            entry["trigger"] = .string(spec.event)
            if let matcher = spec.matcher { entry["matcher"] = .string(matcher) }
            entry["action"] = .object(["type": .string("command"), "command": .string(command(agent, paths, event: spec.event))])
            entry["timeout"] = .int(spec.timeout ?? HookSpec.quickTimeout)
            entry["enabled"] = .bool(true)
            return .object(entry)
        }
        return JSONValue.object(["version": .string("v1"), "hooks": .array(hooks)]).serialized(.pretty)
    }

    /// The manifest of a plugin pack, as Claude Code plugins have it (MiniMax Code reads the same layout).
    public static func pluginManifest(agent: AgentDescriptor) -> String {
        let root = JSONObject([
            "name": .string("niko"),
            "displayName": .string("Niko Island"),
            "version": .string(NikoVersion.current),
            "description": .string("Niko Island status bridge (niko-bridge). `niko-island uninstall` removes this plugin."),
            "hooks": .array([.string(AgentDescriptor.packHooks)]),
        ])
        return JSONValue.object(root).serialized(.pretty)
    }

    /// The hook command for one agent; `event` names the event for agents whose payload may not.
    static func command(_ agent: AgentDescriptor, _ paths: NikoPaths, event: String? = nil) -> String {
        Shims.hookCommand(paths: paths, source: agent.id,
                          extraArguments: agent.bridgeArguments + (event.map { ["--event", $0] } ?? []))
    }

    /// In-process plugin for OpenCode-family agents (INTEGRATIONS "OpenCode-family JS").
    /// It reads the live port and token from our runtime directory on every
    /// event, so it is inert whenever the app is not running.
    public static func openCodePlugin(agent: AgentDescriptor, paths: NikoPaths) -> String {
        let root = paths.isDefaultLocation
            ? "join(homedir(), \".niko-island\")"
            : JSONValue.string(paths.root.path).serialized()
        return """
        // Niko Island plugin (niko-bridge) for \(agent.displayName) — generated, version \(NikoVersion.current).
        // It forwards session activity to the Niko Island menu-bar app on this
        // machine over loopback HTTP. Delete this file, or run
        // `niko-island uninstall`, and it is gone. It never throws into the agent.
        import { readFileSync } from "node:fs";
        import { homedir } from "node:os";
        import { join } from "node:path";

        const ROOT = \(root);
        const SOURCE = \(JSONValue.string(agent.id).serialized());

        function endpoint() {
          try {
            const port = readFileSync(join(ROOT, "run", "ingress-port"), "utf8").trim();
            const token = readFileSync(join(ROOT, "run", "ingress-token"), "utf8").trim();
            if (!/^\\d+$/.test(port) || !token) return null;
            return { url: `http://127.0.0.1:${port}/event`, token };
          } catch {
            return null; // app not running or not installed
          }
        }

        function terminal() {
          const env = process.env;
          return {
            pid: process.pid,
            term_program: env.TERM_PROGRAM,
            iterm_session_id: env.ITERM_SESSION_ID,
            tmux: env.TMUX,
            tmux_pane: env.TMUX_PANE,
            bundle_id: env.__CFBundleIdentifier,
          };
        }

        async function post(directory, event, blocking = false) {
          const target = endpoint();
          if (!target) return null;
          const controller = new AbortController();
          const timer = blocking ? null : setTimeout(() => controller.abort(), 1500);
          try {
            const response = await fetch(target.url, {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                Authorization: `Bearer ${target.token}`,
                "X-Niko-Directory": encodeURIComponent(directory ?? ""),
                "X-Niko-Source": SOURCE,
              },
              // Status events only need names and short hints: cap long strings.
              body: JSON.stringify(
                { source: SOURCE, cwd: directory, ts: Date.now(), _niko: terminal(), ...event },
                blocking ? undefined : (key, value) => (typeof value === "string" && value.length > 4096 ? value.slice(0, 4096) + "…" : value),
              ),
              signal: controller.signal,
            });
            if (!response.ok) return null;
            return await response.json();
          } catch {
            return null;
          } finally {
            if (timer) clearTimeout(timer);
          }
        }

        function behaviorOf(reply) {
          const decision = reply?.reply?.hookSpecificOutput?.decision ?? reply?.reply?.decision;
          const behavior = typeof decision?.behavior === "string" ? decision.behavior.toLowerCase() : "";
          if (behavior === "approve" || behavior === "allow") return { allow: true, decision };
          if (behavior === "deny" || behavior === "block") return { allow: false, decision };
          return null; // no decision: the agent keeps its own prompt
        }

        export const NikoIsland = async ({ client, directory }) => {
          const sessionOf = (id) => id ?? `cwd:${directory}`;
          const seen = new Set();

          async function permission(request) {
            const id = request?.id;
            if (id && seen.has(id)) return null;
            if (id) seen.add(id);
            const reply = await post(directory, {
              hook_event_name: "PermissionRequest",
              session_id: sessionOf(request?.sessionID),
              tool_name: request?.type ?? request?.permission ?? request?.title ?? "permission",
              tool_input: { ...(request?.metadata ?? {}), title: request?.title, pattern: request?.pattern, _request_id: id },
            }, true);
            return behaviorOf(reply);
          }

          async function question(request) {
            const questions = (request?.questions ?? []).map((q) => ({
              text: q.question ?? q.text ?? "",
              header: q.header,
              options: (q.options ?? []).map((o) => (typeof o === "string" ? o : o.label)),
              multiSelect: Boolean(q.multiple ?? q.multiSelect),
            }));
            const reply = await post(directory, {
              hook_event_name: "PermissionRequest",
              session_id: sessionOf(request?.sessionID),
              tool_name: "AskUserQuestion",
              tool_input: { questions, _request_id: request?.id },
            }, true);
            const outcome = behaviorOf(reply);
            const answers = outcome?.decision?.updatedInput?.answers;
            if (!outcome?.allow || !Array.isArray(answers)) return;
            try {
              await client?.question?.reply?.({ requestID: request?.id, answers });
            } catch {
              // Unknown client surface: the question simply stays open in the agent.
            }
          }

          return {
            event: async ({ event }) => {
              try {
                const p = event?.properties ?? {};
                const session_id = sessionOf(p.sessionID ?? p.info?.id);
                switch (event?.type) {
                  case "session.created":
                    await post(directory, { hook_event_name: "SessionStart", session_id });
                    break;
                  case "session.deleted":
                    await post(directory, { hook_event_name: "SessionEnd", session_id });
                    break;
                  case "session.idle":
                    await post(directory, { hook_event_name: "Stop", session_id });
                    break;
                  case "permission.replied":
                  case "question.replied":
                    await post(directory, { hook_event_name: "PostToolUse", session_id, tool_name: event.type });
                    break;
                  case "question.asked":
                    await question(p);
                    break;
                  default:
                    break;
                }
              } catch {
                // never let our failure reach the agent
              }
            },
            "chat.message": async (input) => {
              await post(directory, { hook_event_name: "UserPromptSubmit", session_id: sessionOf(input?.sessionID) });
            },
            "tool.execute.before": async (input, output) => {
              await post(directory, {
                hook_event_name: "PreToolUse",
                session_id: sessionOf(input?.sessionID),
                tool_name: input?.tool,
                tool_input: output?.args ?? {},
              });
            },
            "tool.execute.after": async (input) => {
              await post(directory, { hook_event_name: "PostToolUse", session_id: sessionOf(input?.sessionID), tool_name: input?.tool });
            },
            "permission.ask": async (input, output) => {
              const outcome = await permission(input);
              if (outcome && output) output.status = outcome.allow ? "allow" : "deny";
            },
          };
        };

        """
    }

    /// Amp's plugin (its plugin API is experimental; Bun runs the file). It
    /// only listens: it never answers a tool call, so Amp's own permission
    /// rules stay exactly as they are.
    public static func ampPlugin(agent: AgentDescriptor, paths: NikoPaths) -> String {
        let root = paths.isDefaultLocation
            ? "join(homedir(), \".niko-island\")"
            : JSONValue.string(paths.root.path).serialized()
        return """
        // Niko Island plugin (niko-bridge) for \(agent.displayName) — generated, version \(NikoVersion.current).
        // It tells the Niko Island menu-bar app on this machine what Amp is doing,
        // over loopback HTTP. It only listens and never answers a tool call.
        // Delete this file, or run `niko-island uninstall`, and it is gone.
        import { readFileSync } from "node:fs";
        import { homedir } from "node:os";
        import { join } from "node:path";

        const ROOT = \(root);
        const SOURCE = \(JSONValue.string(agent.id).serialized());

        function endpoint() {
          try {
            const port = readFileSync(join(ROOT, "run", "ingress-port"), "utf8").trim();
            const token = readFileSync(join(ROOT, "run", "ingress-token"), "utf8").trim();
            if (!/^\\d+$/.test(port) || !token) return null;
            return { url: `http://127.0.0.1:${port}/event`, token };
          } catch {
            return null; // app not running or not installed
          }
        }

        function textOf(value) {
          if (typeof value === "string") return value;
          if (Array.isArray(value)) return value.map(textOf).filter(Boolean).join("\\n");
          if (value && typeof value === "object") return textOf(value.text ?? value.content);
          return undefined;
        }

        async function post(directory, event) {
          const target = endpoint();
          if (!target) return;
          const controller = new AbortController();
          const timer = setTimeout(() => controller.abort(), 1500);
          try {
            await fetch(target.url, {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                Authorization: `Bearer ${target.token}`,
                "X-Niko-Directory": encodeURIComponent(directory ?? ""),
                "X-Niko-Source": SOURCE,
              },
              body: JSON.stringify(
                {
                  source: SOURCE,
                  cwd: directory,
                  ts: Date.now(),
                  _niko: { pid: process.pid, term_program: process.env.TERM_PROGRAM, iterm_session_id: process.env.ITERM_SESSION_ID,
                           tmux: process.env.TMUX, tmux_pane: process.env.TMUX_PANE, bundle_id: process.env.__CFBundleIdentifier },
                  ...event,
                },
                (key, value) => (typeof value === "string" && value.length > 4096 ? value.slice(0, 4096) + "…" : value),
              ),
              signal: controller.signal,
            });
          } catch {
            // the app is not there: nothing to do
          } finally {
            clearTimeout(timer);
          }
        }

        export default function (amp) {
          let directory = process.cwd();
          try {
            const root = amp?.system?.workspaceRoot;
            if (root) directory = amp.helpers?.filePathFromURI?.(root) ?? String(root);
          } catch {
            // keep the process directory
          }
          const sessionOf = (event) => event?.thread?.id ?? `cwd:${directory}`;
          const on = (name, handler) => {
            try {
              amp.on(name, async (event) => {
                try {
                  await handler(event ?? {});
                } catch {
                  // never let our failure reach Amp
                }
              });
            } catch {
              // an Amp without this event
            }
          };

          on("session.start", (event) => post(directory, { hook_event_name: "SessionStart", session_id: sessionOf(event) }));
          on("agent.start", (event) =>
            post(directory, { hook_event_name: "UserPromptSubmit", session_id: sessionOf(event), prompt: textOf(event.message) }));
          on("tool.result", (event) =>
            post(directory, {
              hook_event_name: "PreToolUse",
              session_id: sessionOf(event),
              tool_name: event.tool,
              tool_input: event.input && typeof event.input === "object" ? event.input : {},
            }));
          on("agent.end", (event) => {
            const replies = Array.isArray(event.messages) ? event.messages.filter((m) => m?.role === "assistant") : [];
            return post(directory, {
              hook_event_name: event.status === "error" ? "StopFailure" : "Stop",
              session_id: sessionOf(event),
              last_assistant_message: textOf(replies[replies.length - 1]?.content),
            });
          });
        }

        """
    }
}
