import { expect, test } from "bun:test";
import { preservedRoutes, routePlan } from "../scripts/agentvoice-network.ts";

const dns = "desktop.example";
const settings = { version: 1 as const, endpoint: `wss://${dns}:48414/v2/client`, port: 44414 };
const existing = { TCP: { "443": { HTTPS: true } }, Web: { [`${dns}:443`]: { Handlers: { "/mcp": { Proxy: "http://127.0.0.1:4790/mcp" } } } }, AllowFunnel: { [`${dns}:443`]: true } };
test("dedicated voice route is idempotent and preserves public MCP routes", () => {
  const plan = routePlan(settings, dns, existing);
  expect(plan.install).toBe(true);
  const after = { ...existing, TCP: { ...existing.TCP, "48414": { HTTPS: true } }, Web: { ...existing.Web, [plan.host]: { Handlers: { "/": { Proxy: plan.proxy } } } } };
  expect(routePlan(settings, dns, after).install).toBe(false);
  expect(() => preservedRoutes(existing, after, plan.host, plan.port)).not.toThrow();
  expect(() => preservedRoutes(existing, { ...after, AllowFunnel: {} }, plan.host, plan.port)).toThrow();
});
test("foreign routes, Funnel and nonlocal Tailscale identities fail closed", () => {
  expect(() => routePlan(settings, dns, { AllowFunnel: { [`${dns}:48414`]: true } })).toThrow("Funnel");
  expect(() => routePlan(settings, dns, { TCP: { "48414": { HTTPS: true } } })).toThrow();
  expect(() => routePlan(settings, dns, { TCP: { "48414": { HTTPS: true } }, Web: { [`${dns}:48414`]: { Handlers: { "/": { Proxy: "http://127.0.0.1:9999" } } } } })).toThrow();
  expect(() => routePlan(settings, "different.example", existing)).toThrow();
  expect(() => routePlan({ ...settings, endpoint: `wss://${dns}/v2/client` }, dns, existing)).toThrow();
});
