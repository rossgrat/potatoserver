import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { test } from "node:test";
import { z } from "zod";
import { zodResolver } from "@hookform/resolvers/zod";
import nodemailer from "nodemailer";

createRequire(import.meta.url).extensions[".css"] = () => {};
const { parseAndValidateConfig } = await import("../lib/config.ts");
const { generateZodSchema } = await import("../lib/schema.ts");
const { schema: imageSchema } = await import("../fields/core/image/index.tsx");

const fields = [
  { name: "title", type: "string", required: true },
  { name: "draft", type: "boolean", default: true },
  { name: "date", type: "date", options: { time: true } },
  { name: "tags", type: "string", list: true },
  { name: "body", type: "rich-text" },
];
const content = {
  title: "Test post",
  draft: true,
  date: "2026-11-11T12:00",
  tags: ["test"],
  body: "A paragraph with **Markdown**.",
};

test("oversized collections stop before validating every element", () => {
  const result = z.array(z.string()).max(2).safeParse(Array(10000).fill(null));
  assert.equal(result.success, false);
  assert.equal(result.error.issues.length, 1);
  assert.equal(result.error.issues[0].code, "too_big");
});

test("raw email messages cannot read files when file access is disabled", async () => {
  const transport = nodemailer.createTransport({
    streamTransport: true,
    buffer: true,
    disableFileAccess: true,
    disableUrlAccess: true,
  });
  await assert.rejects(
    transport.sendMail({
      from: "sender@example.test",
      to: "recipient@example.test",
      raw: { path: new URL("../package.json", import.meta.url).pathname },
    }),
    /File access rejected/i,
  );
  transport.close();
});

test("post forms preserve valid drafts and published posts", async () => {
  const schema = generateZodSchema(fields);
  const resolver = zodResolver(schema);
  for (const draft of [true, false]) {
    const value = { ...content, draft };
    assert.deepEqual(schema.parse(value), value);
    const result = await resolver(value, {}, { fields: {}, shouldUseNativeValidation: false });
    assert.deepEqual(result.errors, {});
    assert.deepEqual(result.values, value);
  }
});

test("post forms show field errors instead of throwing", async () => {
  const resolver = zodResolver(generateZodSchema(fields));
  const result = await resolver(
    { ...content, title: "", tags: [false] },
    {},
    {
      fields: {},
      shouldUseNativeValidation: false,
    },
  );
  assert.equal(result.errors.title.message, "This field is required");
  assert.ok(result.errors.tags[0].message);
  assert.deepEqual(result.values, {});
});

test("configuration validation accepts the blog fields and reports invalid unions", () => {
  const config = {
    content: [{ name: "posts", type: "collection", path: "content/posts", fields }],
  };
  const valid = parseAndValidateConfig(JSON.stringify(config));
  assert.deepEqual(valid.parseErrors, []);
  assert.deepEqual(valid.validationErrors, []);
  for (const value of [false, { type: "invalid" }, { type: "collection", path: "content/posts" }]) {
    const invalid = parseAndValidateConfig(JSON.stringify({ content: [value] }));
    assert.ok(invalid.validationErrors.length > 0);
    assert.ok(invalid.validationErrors.every((error) => typeof error.message === "string"));
  }
});

test("required image lists still reject empty and duplicate values", () => {
  const schema = imageSchema({
    name: "images",
    type: "image",
    required: true,
    options: { multiple: true, unique: true },
  });
  assert.equal(schema.safeParse([]).success, false);
  assert.equal(schema.safeParse(["/images/post.png", "/images/post.png"]).success, false);
  assert.equal(schema.safeParse(["/images/post.png"]).success, true);
});
