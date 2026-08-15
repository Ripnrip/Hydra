import esbuild from "esbuild";

const prod = process.argv.includes("--prod");

await esbuild.build({
  entryPoints: ["src/main.ts"],
  bundle: true,
  external: [
    "obsidian",
    "electron",
    "@electron/remote",
    "child_process",
    "util",
    "fs",
    "path",
    "os",
  ],
  format: "cjs",
  target: "es2022",
  logLevel: "info",
  sourcemap: prod ? false : "inline",
  treeShaking: true,
  outfile: "main.js",
});

console.log("Build complete");
