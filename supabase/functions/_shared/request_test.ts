import { readJsonLimited } from "./request.ts";

Deno.test("readJsonLimited accepts a valid body at the exact byte limit", async () => {
  const body = JSON.stringify({ ok: true });
  const request = new Request("https://example.test", { method: "POST", body });
  const result = await readJsonLimited(request, new TextEncoder().encode(body).byteLength);
  if (JSON.stringify(result) !== body) throw new Error("Parsed JSON did not match input.");
});

Deno.test("readJsonLimited rejects an oversized declared content length", async () => {
  const request = new Request("https://example.test", {
    method: "POST",
    headers: { "content-length": "100" },
    body: "{}",
  });
  let rejected = false;
  try { await readJsonLimited(request, 10); }
  catch (error) { rejected = error instanceof Error && error.message === "REQUEST_TOO_LARGE"; }
  if (!rejected) throw new Error("Expected declared oversized body to be rejected.");
});

Deno.test("readJsonLimited rejects a streamed body larger than the limit", async () => {
  const request = new Request("https://example.test", { method: "POST", body: "123456" });
  let rejected = false;
  try { await readJsonLimited(request, 5); }
  catch (error) { rejected = error instanceof Error && error.message === "REQUEST_TOO_LARGE"; }
  if (!rejected) throw new Error("Expected streamed oversized body to be rejected.");
});

Deno.test("readJsonLimited rejects malformed JSON and invalid UTF-8", async () => {
  for (const body of ["{", new Uint8Array([0xff, 0xfe])]) {
    const request = new Request("https://example.test", { method: "POST", body });
    let rejected = false;
    try { await readJsonLimited(request, 20); }
    catch (error) { rejected = error instanceof Error && error.message === "INVALID_JSON"; }
    if (!rejected) throw new Error("Expected malformed JSON to be rejected.");
  }
});

Deno.test("readJsonLimited rejects requests without a body", async () => {
  const request = new Request("https://example.test", { method: "POST" });
  let rejected = false;
  try { await readJsonLimited(request, 10); }
  catch (error) { rejected = error instanceof Error && error.message === "INVALID_JSON"; }
  if (!rejected) throw new Error("Expected a missing body to be rejected.");
});

Deno.test("readJsonLimited rejects zero, negative, fractional, and unsafe limits", async () => {
  const request = new Request("https://example.test", { method: "POST", body: "{}" });
  for (const limit of [0, -1, 1.5, Number.MAX_SAFE_INTEGER + 1, Number.NaN]) {
    let rejected = false;
    try { await readJsonLimited(request.clone(), limit); }
    catch (error) { rejected = error instanceof Error && error.message === "INVALID_LIMIT"; }
    if (!rejected) throw new Error(`Expected invalid limit ${String(limit)} to be rejected.`);
  }
});
