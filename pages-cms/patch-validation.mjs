import fs from "node:fs";

let configSchema = fs.readFileSync("lib/config-schema.ts", "utf8");
configSchema = configSchema.replace(
  /required_error:\s*("(?:[^"\\]|\\.)*"),\s*(?:invalid_type_error|message):\s*("(?:[^"\\]|\\.)*"),/g,
  (_, required, invalid) => `error: (issue) => issue.input === undefined ? ${required} : ${invalid},`,
).replace(/invalid_type_error:/g, "error:");
if (/required_error|invalid_type_error/.test(configSchema)) throw new Error("Unconverted Zod error options");
fs.writeFileSync("lib/config-schema.ts", configSchema);

function replace(file, before, after) {
  const source = fs.readFileSync(file, "utf8");
  if (!source.includes(before)) throw new Error(`Unexpected source in ${file}`);
  fs.writeFileSync(file, source.replace(before, after));
}

replace("lib/config.ts", "zodError.errors.forEach", "zodError.issues.forEach");
replace("lib/config.ts", "error.unionErrors.forEach((unionError: any) => {\n        unionError.issues.forEach", "error.errors.forEach((issues: any[]) => {\n        issues.forEach");
replace("lib/config.ts", "error.unionErrors.length", "error.errors.length");
replace(
  "lib/schema.ts",
  "  ignoreHidden: boolean = false\n): z.ZodTypeAny => {",
  "  ignoreHidden: boolean = false\n) => {",
);
replace(
  "app/api/[owner]/[repo]/[branch]/files/[path]/route.ts",
  "zodValidation.error.errors.map",
  "zodValidation.error.issues.map",
);
for (const type of ["file", "image"]) {
  replace(
    `fields/core/${type}/index.tsx`,
    "let zodSchema: z.ZodTypeAny;",
    "let zodSchema: z.ZodType<string | string[] | null | undefined>;",
  );
}

fs.copyFileSync(new URL("./hardening.test.mjs", import.meta.url), "scripts/hardening.test.mjs");
