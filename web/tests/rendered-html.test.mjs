import assert from "node:assert/strict";
import test from "node:test";

async function render() {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request("http://localhost/", {
      headers: { accept: "text/html" },
    }),
    {
      ASSETS: {
        fetch: async () => new Response("Not found", { status: 404 }),
      },
    },
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );
}

test("renders the bread intake prototype", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<html lang="ru">/i);
  assert.match(html, /<title>Хлеб\.Приход<\/title>/i);
  assert.match(html, /Добавьте накладную/);
  assert.match(html, /Открыть тестовую накладную/);
  assert.match(html, /Рабочая база 1С не используется/);
  assert.doesNotMatch(html, /codex-preview|SkeletonPreview|Starter Project/);
});

test("includes product-specific social metadata", async () => {
  const response = await render();
  const html = await response.text();

  assert.match(html, /property="og:title" content="Хлеб\.Приход"/i);
  assert.match(html, /property="og:description" content="Накладная — от фото до 1С"/i);
  assert.match(html, /property="og:image" content="http:\/\/localhost(?::3000)?\/og\.png"/i);
  assert.match(html, /name="twitter:card" content="summary_large_image"/i);
});
