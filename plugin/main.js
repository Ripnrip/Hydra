"use strict";
var __defProp = Object.defineProperty;
var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __hasOwnProp = Object.prototype.hasOwnProperty;
var __export = (target, all) => {
  for (var name in all)
    __defProp(target, name, { get: all[name], enumerable: true });
};
var __copyProps = (to, from, except, desc) => {
  if (from && typeof from === "object" || typeof from === "function") {
    for (let key of __getOwnPropNames(from))
      if (!__hasOwnProp.call(to, key) && key !== except)
        __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
  }
  return to;
};
var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

// src/main.ts
var main_exports = {};
__export(main_exports, {
  default: () => HydraPlugin
});
module.exports = __toCommonJS(main_exports);
var import_obsidian3 = require("obsidian");

// src/bridge.ts
var execFileAsync = null;
try {
  const { execFile } = require("child_process");
  const { promisify } = require("util");
  execFileAsync = promisify(execFile);
} catch {
}
var HydraBridge = class {
  binaryPath;
  constructor(binaryPath) {
    this.binaryPath = binaryPath;
  }
  updateBinary(path) {
    this.binaryPath = path;
  }
  // MARK: - Commands
  async scan(vaultPath) {
    const output = await this.run(["scan", "--vault", vaultPath]);
    return this.parseScanOutput(output);
  }
  async health(vaultPath) {
    const output = await this.run(["health", "--vault", vaultPath]);
    return this.parseHealthOutput(output);
  }
  async search(vaultPath, query, limit = 20) {
    const output = await this.run(["search", "--vault", vaultPath, "--query", query, "--limit", String(limit)]);
    return this.parseSearchOutput(output);
  }
  async classify(filePath, content) {
    const result = await this.run(["hydrate", "--source", filePath, "--dry-run"]);
    return this.parseClassifyOutput(result, content);
  }
  async findRelationships(noteName, content) {
    const wikilinks = this.extractWikilinks(content);
    const tags = this.extractTags(content);
    return {
      relationships: [
        ...wikilinks.map((w) => ({ type: "wikilink", target: w, confidence: 1 })),
        ...tags.map((t) => ({ type: "tag", target: `#${t}`, confidence: 0.7 }))
      ]
    };
  }
  // MARK: - Binary execution
  async run(args) {
    if (!execFileAsync) {
      throw new Error("Binary mode unavailable \u2014 using heuristic mode");
    }
    try {
      const { stdout } = await execFileAsync(this.binaryPath, args, {
        maxBuffer: 10 * 1024 * 1024,
        timeout: 3e4
      });
      return stdout;
    } catch (err) {
      const msg = err?.message ?? String(err);
      throw new Error(`Hydra binary error: ${msg}`);
    }
  }
  // MARK: - Output parsers
  parseScanOutput(output) {
    const result = {
      notes: 0,
      tags: 0,
      orphaned: 0,
      brokenLinks: 0,
      missingFrontmatter: 0,
      para: []
    };
    const notesMatch = output.match(/Notes:\s+(\d+)/);
    const tagsMatch = output.match(/Tags:\s+(\d+)/);
    const orphanedMatch = output.match(/Orphaned:\s+(\d+)/);
    const brokenMatch = output.match(/Broken wikilinks:\s+(\d+)/);
    const frontmatterMatch = output.match(/Missing frontmatter:\s+(\d+)/);
    if (notesMatch) result.notes = parseInt(notesMatch[1]);
    if (tagsMatch) result.tags = parseInt(tagsMatch[1]);
    if (orphanedMatch) result.orphaned = parseInt(orphanedMatch[1]);
    if (brokenMatch) result.brokenLinks = parseInt(brokenMatch[1]);
    if (frontmatterMatch) result.missingFrontmatter = parseInt(frontmatterMatch[1]);
    const paraSection = output.match(/PARA Breakdown:([\s\S]*?)(?=\n\n|\nOrphaned|$)/);
    if (paraSection) {
      const lines = paraSection[1].trim().split("\n");
      for (const line of lines) {
        const match = line.match(/^\s+(\S+)\s+(\d+)/);
        if (match) {
          result.para.push({ category: match[1], count: parseInt(match[2]) });
        }
      }
    }
    return result;
  }
  parseHealthOutput(output) {
    const checks = [];
    const lines = output.split("\n");
    for (const line of lines) {
      const match = line.match(/[✅⚠️🔴]\s+(.+?)\s{2,}(.+)/);
      if (match) {
        const name = match[1].trim();
        const message = match[2].trim();
        let status = "healthy";
        if (line.includes("\u26A0\uFE0F")) status = "warning";
        else if (line.includes("\u{1F534}")) status = "critical";
        checks.push({ name, status, message, count: 0 });
      }
    }
    const overallMatch = output.match(/Overall:\s+(\w+)/);
    const summaryMatch = output.match(/Summary:\s+(.+)/);
    return {
      status: overallMatch ? overallMatch[1].toLowerCase() : "unknown",
      summary: summaryMatch ? summaryMatch[1] : "",
      checks
    };
  }
  parseSearchOutput(output) {
    const results = [];
    const lines = output.split("\n");
    for (const line of lines) {
      if (line.trim().startsWith("Found")) continue;
      if (line.trim().startsWith("\u2014")) continue;
      if (line.trim().length < 3) continue;
      const match = line.match(/^\s+(.+?)(?:\s+\[(.+)\])?\s*$/);
      if (match) {
        results.push({
          title: match[1].trim(),
          tags: match[2] ? match[2].split(", ").map((t) => t.trim()) : []
        });
      }
    }
    return results;
  }
  parseClassifyOutput(output, content) {
    const tags = this.extractTags(content);
    const wikilinks = this.extractWikilinks(content);
    return {
      tags,
      wikilinks,
      kind: "note",
      lifecycle: "draft",
      confidence: 0.5,
      relationships: wikilinks.map((w) => ({ type: "references", target: w }))
    };
  }
  // MARK: - Content helpers
  extractWikilinks(content) {
    const matches = content.matchAll(/\[\[([^\]|]+)(?:\|[^\]]+)?\]\]/g);
    return Array.from(matches).map((m) => m[1].trim());
  }
  extractTags(content) {
    const tags = /* @__PURE__ */ new Set();
    const matches = content.matchAll(/(?:^|\s)#([a-zA-Z][a-zA-Z0-9/_-]*)/g);
    for (const match of matches) {
      tags.add(match[1].toLowerCase());
    }
    return Array.from(tags);
  }
};

// src/sidebar.ts
var import_obsidian = require("obsidian");
var SIDEBAR_VIEW_TYPE = "hydra-sidebar";
var HydraSidebarView = class extends import_obsidian.ItemView {
  plugin;
  scanResult = null;
  currentSuggestions = null;
  currentRelationships = null;
  constructor(leaf, plugin) {
    super(leaf);
    this.plugin = plugin;
  }
  getViewType() {
    return SIDEBAR_VIEW_TYPE;
  }
  getDisplayText() {
    return "Hydra";
  }
  getIcon() {
    return "droplet";
  }
  async onOpen() {
    this.render();
  }
  async onClose() {
  }
  // MARK: - Updates
  updateScanResult(result) {
    this.scanResult = result;
    this.render();
  }
  updateSuggestions(file, result) {
    this.currentSuggestions = { file, result };
    this.render();
  }
  showTagSuggestions(tags) {
    this.renderTagSuggestions(tags);
  }
  showRelationships(rels) {
    this.currentRelationships = rels;
    this.render();
  }
  // MARK: - Rendering
  render() {
    const container = this.contentEl;
    container.empty();
    container.addClass("hydra-sidebar");
    const header = container.createDiv({ cls: "hydra-header" });
    header.createEl("span", { text: "Hydra", cls: "hydra-logo" });
    header.createEl("span", { text: "Context Hydration", cls: "hydra-tagline" });
    if (this.scanResult) {
      this.renderStats(container);
    }
    if (this.currentSuggestions) {
      this.renderSuggestions(container);
    }
    if (this.currentRelationships) {
      this.renderRelationships(container);
    }
    this.renderActions(container);
  }
  renderStats(container) {
    const r = this.scanResult;
    const stats = container.createDiv({ cls: "hydra-stats" });
    const cards = [
      { label: "Notes", value: r.notes, icon: "\u{1F4C4}" },
      { label: "Tags", value: r.tags, icon: "\u{1F3F7}\uFE0F" },
      { label: "Orphaned", value: r.orphaned, icon: "\u{1F47B}" },
      { label: "Broken", value: r.brokenLinks, icon: "\u{1F517}" }
    ];
    for (const card of cards) {
      const el = stats.createDiv({ cls: "hydra-stat-card" });
      el.createEl("span", { text: card.icon, cls: "hydra-stat-icon" });
      el.createEl("span", { text: String(card.value), cls: "hydra-stat-value" });
      el.createEl("span", { text: card.label, cls: "hydra-stat-label" });
    }
    if (r.para.length > 0) {
      const para = container.createDiv({ cls: "hydra-para" });
      para.createEl("div", { text: "PARA BREAKDOWN", cls: "hydra-section-title" });
      for (const p of r.para.slice(0, 6)) {
        const row = para.createDiv({ cls: "hydra-para-row" });
        row.createEl("span", { text: p.category, cls: "hydra-para-cat" });
        row.createEl("span", { text: String(p.count), cls: "hydra-para-count" });
      }
    }
  }
  renderSuggestions(container) {
    const s = this.currentSuggestions;
    const section = container.createDiv({ cls: "hydra-suggestions" });
    section.createEl("div", { text: "SUGGESTED TAGS", cls: "hydra-section-title" });
    for (const tag of s.result.tags) {
      const chip = section.createDiv({ cls: "hydra-tag-chip" });
      chip.createEl("span", { text: "#", cls: "hydra-tag-hash" });
      chip.createEl("span", { text: tag });
      chip.onClickEvent(() => {
        this.applyTag(s.file, tag);
        chip.addClass("hydra-tag-applied");
      });
    }
    if (s.result.wikilinks.length > 0) {
      section.createEl("div", { text: "WIKILINKS", cls: "hydra-section-title" });
      for (const link of s.result.wikilinks) {
        const el = section.createDiv({ cls: "hydra-wikilink" });
        el.createEl("span", { text: "[[", cls: "hydra-link-bracket" });
        el.createEl("span", { text: link });
        el.createEl("span", { text: "]]", cls: "hydra-link-bracket" });
      }
    }
  }
  renderRelationships(container) {
    const rels = this.currentRelationships;
    const section = container.createDiv({ cls: "hydra-relationships" });
    section.createEl("div", { text: "RELATIONSHIPS", cls: "hydra-section-title" });
    for (const rel of rels.relationships) {
      const el = section.createDiv({ cls: "hydra-rel-row" });
      el.createEl("span", { text: rel.type, cls: "hydra-rel-type" });
      el.createEl("span", { text: "\u2192", cls: "hydra-rel-arrow" });
      el.createEl("span", { text: rel.target, cls: "hydra-rel-target" });
    }
  }
  renderTagSuggestions(tags) {
    const container = this.contentEl;
    container.empty();
    container.addClass("hydra-sidebar");
    container.createEl("div", { text: "SUGGESTED TAGS", cls: "hydra-section-title" });
    for (const tag of tags) {
      const chip = container.createDiv({ cls: "hydra-tag-chip" });
      chip.createEl("span", { text: "#", cls: "hydra-tag-hash" });
      chip.createEl("span", { text: tag });
    }
  }
  renderActions(container) {
    const actions = container.createDiv({ cls: "hydra-actions" });
    const scanBtn = actions.createEl("button", { text: "Scan Vault", cls: "hydra-btn" });
    scanBtn.onClickEvent(() => this.plugin.scanVault());
    const healthBtn = actions.createEl("button", { text: "Health", cls: "hydra-btn" });
    healthBtn.onClickEvent(() => this.plugin.showHealth());
  }
  async applyTag(file, tag) {
    const content = await this.app.vault.read(file);
    if (content.toLowerCase().includes(`#${tag.toLowerCase()}`)) return;
    if (content.startsWith("---")) {
      const end = content.indexOf("\n---", 3);
      if (end > 0) {
        const updated = content.substring(0, end) + `tags:
  - ${tag}
` + content.substring(end);
        await this.app.vault.modify(file, updated);
        return;
      }
    }
    await this.app.vault.modify(file, content + `

#${tag}`);
  }
};

// src/health-widget.ts
var import_obsidian2 = require("obsidian");
var HEALTH_VIEW_TYPE = "hydra-health";
var HydraHealthView = class extends import_obsidian2.ItemView {
  plugin;
  constructor(leaf, plugin) {
    super(leaf);
    this.plugin = plugin;
  }
  getViewType() {
    return HEALTH_VIEW_TYPE;
  }
  getDisplayText() {
    return "Hydra Health";
  }
  getIcon() {
    return "heart-pulse";
  }
  async onOpen() {
    this.render();
  }
  async onClose() {
  }
  setHealthResult(result) {
    this.render(result);
  }
  render(result) {
    const container = this.contentEl;
    container.empty();
    container.addClass("hydra-health");
    if (!result) {
      container.createEl("p", { text: "Run a health check to see results." });
      const btn = container.createEl("button", { text: "Run Health Check", cls: "hydra-btn" });
      btn.onClickEvent(() => this.plugin.showHealth());
      return;
    }
    const banner = container.createDiv({ cls: `hydra-health-banner hydra-health-${result.status}` });
    banner.createEl("span", { text: result.status.toUpperCase(), cls: "hydra-health-status" });
    banner.createEl("span", { text: result.summary, cls: "hydra-health-summary" });
    for (const check of result.checks) {
      const row = container.createDiv({ cls: `hydra-check-row hydra-check-${check.status}` });
      const icon = check.status === "healthy" ? "\u2705" : check.status === "warning" ? "\u26A0\uFE0F" : "\u{1F534}";
      row.createEl("span", { text: icon, cls: "hydra-check-icon" });
      const info = row.createDiv({ cls: "hydra-check-info" });
      info.createEl("div", { text: check.name, cls: "hydra-check-name" });
      info.createEl("div", { text: check.message, cls: "hydra-check-message" });
      const badge = row.createEl("span", { text: check.status.toUpperCase(), cls: `hydra-check-badge hydra-badge-${check.status}` });
    }
  }
};

// src/main.ts
var DEFAULT_SETTINGS = {
  binaryPath: "",
  // auto-detect if empty
  autoTag: true,
  autoLink: true,
  confidenceThreshold: 0.6,
  refreshInterval: 300,
  // seconds
  enableGraphOverlay: true
};
var HydraPlugin = class extends import_obsidian3.Plugin {
  settings = DEFAULT_SETTINGS;
  bridge;
  refreshTimer = null;
  async onload() {
    try {
      await this.initializePlugin();
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      new import_obsidian3.Notice(`Hydra partially failed: ${msg}`, 8e3);
      console.error("Hydra onload error:", err);
    }
  }
  async initializePlugin() {
    await this.loadSettings();
    this.bridge = new HydraBridge(this.settings.binaryPath || await this.detectBinary());
    this.registerView(SIDEBAR_VIEW_TYPE, (leaf) => new HydraSidebarView(leaf, this));
    this.registerView(HEALTH_VIEW_TYPE, (leaf) => new HydraHealthView(leaf, this));
    this.addRibbonIcon("droplet", "Hydra", () => {
      this.activateSidebar();
    });
    this.addCommand({
      id: "hydra-scan",
      name: "Scan vault",
      callback: () => this.scanVault()
    });
    this.addCommand({
      id: "hydra-hydrate-current",
      name: "Hydrate current note",
      callback: () => this.hydrateCurrentNote()
    });
    this.addCommand({
      id: "hydra-health",
      name: "Show vault health",
      callback: () => this.showHealth()
    });
    this.addCommand({
      id: "hydra-suggest-tags",
      name: "Suggest tags for current note",
      callback: () => this.suggestTags()
    });
    this.addCommand({
      id: "hydra-find-relations",
      name: "Find relationships for current note",
      callback: () => this.findRelationships()
    });
    this.addSettingTab(new HydraSettingTab(this.app, this));
    this.registerEvent(
      this.app.vault.on("modify", (file) => {
        if (file instanceof import_obsidian3.TFile && file.extension === "md" && this.settings.autoTag) {
          this.hydrateNote(file);
        }
      })
    );
    this.startRefreshTimer();
    console.log("Hydra plugin loaded");
  }
  onunload() {
    if (this.refreshTimer) {
      window.clearInterval(this.refreshTimer);
    }
  }
  // MARK: - Binary detection
  async detectBinary() {
    const candidates = [
      "/usr/local/bin/hydra",
      "/opt/homebrew/bin/hydra",
      `${process.env.HOME}/.local/bin/hydra`
    ];
    let execFileSync = null;
    try {
      execFileSync = require("child_process").execFileSync;
    } catch {
    }
    for (const path of candidates) {
      try {
        execFileSync(path, ["--version"], { stdio: "ignore" });
        return path;
      } catch {
        continue;
      }
    }
    new import_obsidian3.Notice("Hydra binary not found. Set path in settings.", 5e3);
    return "hydra";
  }
  // MARK: - Actions
  async scanVault() {
    new import_obsidian3.Notice("Hydra: Scanning vault...");
    try {
      const result = await this.bridge.scan(this.app.vault.adapter.getBasePath());
      new import_obsidian3.Notice(`Hydra: ${result.notes} notes, ${result.tags} tags, ${result.orphaned} orphaned`);
      const sidebar = this.getSidebar();
      if (sidebar) sidebar.updateScanResult(result);
    } catch (err) {
      new import_obsidian3.Notice(`Hydra: Scan failed \u2014 ${err.message}`);
    }
  }
  async hydrateCurrentNote() {
    const file = this.app.workspace.getActiveFile();
    if (!file || file.extension !== "md") {
      new import_obsidian3.Notice("Hydra: Open a markdown file first");
      return;
    }
    await this.hydrateNote(file);
  }
  async hydrateNote(file) {
    try {
      const content = await this.app.vault.read(file);
      const suggestions = await this.bridge.classify(file.path, content);
      if (suggestions.tags.length > 0 && this.settings.autoTag) {
        const updated = this.applyTags(content, suggestions.tags);
        if (updated !== content) {
          await this.app.vault.modify(file, updated);
        }
      }
      const sidebar = this.getSidebar();
      if (sidebar) sidebar.updateSuggestions(file, suggestions);
    } catch (err) {
      console.warn("Hydra hydration error:", err);
    }
  }
  async suggestTags() {
    const file = this.app.workspace.getActiveFile();
    if (!file) return;
    const content = await this.app.vault.read(file);
    const suggestions = await this.bridge.classify(file.path, content);
    const sidebar = await this.activateSidebar();
    sidebar.showTagSuggestions(suggestions.tags);
  }
  async findRelationships() {
    const file = this.app.workspace.getActiveFile();
    if (!file) return;
    const content = await this.app.vault.read(file);
    const rels = await this.bridge.findRelationships(file.basename, content);
    const sidebar = await this.activateSidebar();
    sidebar.showRelationships(rels);
  }
  async showHealth() {
    const result = await this.bridge.health(this.app.vault.adapter.getBasePath());
    const leaf = this.app.workspace.getRightLeaf(false);
    if (leaf) {
      await leaf.setViewState({ type: HEALTH_VIEW_TYPE, ejson: result });
      this.app.workspace.revealLeaf(leaf);
    }
  }
  // MARK: - Helpers
  applyTags(content, tags) {
    if (content.startsWith("---")) {
      const end = content.indexOf("\n---", 3);
      if (end > 0) {
        const frontmatter = content.substring(0, end);
        const hasTags = frontmatter.includes("tags:");
        if (hasTags) {
          const tagEnd = frontmatter.indexOf("\n", frontmatter.indexOf("tags:"));
          const newTags = tags.map((t) => `  - ${t}`).join("\n");
          return content.substring(0, tagEnd + 1) + newTags + content.substring(tagEnd);
        } else {
          const tagsField = `tags:
${tags.map((t) => `  - ${t}`).join("\n")}
`;
          return content.substring(0, end) + tagsField + content.substring(end);
        }
      }
    }
    const tagString = tags.map((t) => `#${t}`).join(" ");
    return content + "\n\n" + tagString;
  }
  startRefreshTimer() {
    if (this.refreshTimer) window.clearInterval(this.refreshTimer);
    this.refreshTimer = window.setInterval(() => {
      this.scanVault();
    }, this.settings.refreshInterval * 1e3);
  }
  // MARK: - Sidebar
  getSidebar() {
    const leaves = this.app.workspace.getLeavesOfType(SIDEBAR_VIEW_TYPE);
    return leaves.length > 0 ? leaves[0].view : null;
  }
  async activateSidebar() {
    const existing = this.getSidebar();
    if (existing) return existing;
    const leaf = this.app.workspace.getRightLeaf(false);
    if (!leaf) throw new Error("No sidebar leaf available");
    await leaf.setViewState({ type: SIDEBAR_VIEW_TYPE });
    this.app.workspace.revealLeaf(leaf);
    return leaf.view;
  }
  async loadSettings() {
    this.settings = Object.assign({}, DEFAULT_SETTINGS, await this.loadData());
  }
  async saveSettings() {
    await this.saveData(this.settings);
    this.bridge.updateBinary(this.settings.binaryPath);
    this.startRefreshTimer();
  }
};
var HydraSettingTab = class extends import_obsidian3.PluginSettingTab {
  plugin;
  constructor(app, plugin) {
    super(app, plugin);
    this.plugin = plugin;
  }
  display() {
    const { containerEl } = this;
    containerEl.empty();
    containerEl.createEl("h3", { text: "Hydra Settings" });
    new import_obsidian3.Setting(containerEl).setName("Binary path").setDesc("Path to the hydra CLI binary").addText((text) => text.setPlaceholder("Auto-detect").setValue(this.plugin.settings.binaryPath).onChange(async (value) => {
      this.plugin.settings.binaryPath = value;
      await this.plugin.saveSettings();
    }));
    new import_obsidian3.Setting(containerEl).setName("Auto-tag").setDesc("Automatically add suggested tags when notes are modified").addToggle((toggle) => toggle.setValue(this.plugin.settings.autoTag).onChange(async (value) => {
      this.plugin.settings.autoTag = value;
      await this.plugin.saveSettings();
    }));
    new import_obsidian3.Setting(containerEl).setName("Auto-link").setDesc("Automatically suggest wikilinks between related notes").addToggle((toggle) => toggle.setValue(this.plugin.settings.autoLink).onChange(async (value) => {
      this.plugin.settings.autoLink = value;
      await this.plugin.saveSettings();
    }));
    new import_obsidian3.Setting(containerEl).setName("Confidence threshold").setDesc("Minimum confidence for auto-classification (0.0\u20131.0)").addSlider((slider) => slider.setLimits(0, 1, 0.05).setValue(this.plugin.settings.confidenceThreshold).setDynamicTooltip().onChange(async (value) => {
      this.plugin.settings.confidenceThreshold = value;
      await this.plugin.saveSettings();
    }));
    new import_obsidian3.Setting(containerEl).setName("Refresh interval").setDesc("Seconds between automatic vault scans").addText((text) => text.setValue(String(this.plugin.settings.refreshInterval)).onChange(async (value) => {
      const num = parseInt(value);
      if (!isNaN(num) && num > 0) {
        this.plugin.settings.refreshInterval = num;
        await this.plugin.saveSettings();
      }
    }));
  }
};
//# sourceMappingURL=data:application/json;base64,ewogICJ2ZXJzaW9uIjogMywKICAic291cmNlcyI6IFsic3JjL21haW4udHMiLCAic3JjL2JyaWRnZS50cyIsICJzcmMvc2lkZWJhci50cyIsICJzcmMvaGVhbHRoLXdpZGdldC50cyJdLAogICJzb3VyY2VzQ29udGVudCI6IFsiaW1wb3J0IHsgUGx1Z2luLCBXb3Jrc3BhY2VMZWFmLCBURmlsZSwgTm90aWNlLCBTZXR0aW5nLCBQbHVnaW5TZXR0aW5nVGFiLCBBcHAgfSBmcm9tICdvYnNpZGlhbic7XG5pbXBvcnQgeyBIeWRyYUJyaWRnZSB9IGZyb20gJy4vYnJpZGdlJztcbmltcG9ydCB7IEh5ZHJhU2lkZWJhclZpZXcsIFNJREVCQVJfVklFV19UWVBFIH0gZnJvbSAnLi9zaWRlYmFyJztcbmltcG9ydCB7IEh5ZHJhSGVhbHRoVmlldywgSEVBTFRIX1ZJRVdfVFlQRSB9IGZyb20gJy4vaGVhbHRoLXdpZGdldCc7XG5cbi8vIE1BUks6IC0gU2V0dGluZ3NcblxuaW50ZXJmYWNlIEh5ZHJhU2V0dGluZ3Mge1xuICBiaW5hcnlQYXRoOiBzdHJpbmc7XG4gIGF1dG9UYWc6IGJvb2xlYW47XG4gIGF1dG9MaW5rOiBib29sZWFuO1xuICBjb25maWRlbmNlVGhyZXNob2xkOiBudW1iZXI7XG4gIHJlZnJlc2hJbnRlcnZhbDogbnVtYmVyO1xuICBlbmFibGVHcmFwaE92ZXJsYXk6IGJvb2xlYW47XG59XG5cbmNvbnN0IERFRkFVTFRfU0VUVElOR1M6IEh5ZHJhU2V0dGluZ3MgPSB7XG4gIGJpbmFyeVBhdGg6ICcnLCAgLy8gYXV0by1kZXRlY3QgaWYgZW1wdHlcbiAgYXV0b1RhZzogdHJ1ZSxcbiAgYXV0b0xpbms6IHRydWUsXG4gIGNvbmZpZGVuY2VUaHJlc2hvbGQ6IDAuNixcbiAgcmVmcmVzaEludGVydmFsOiAzMDAsICAvLyBzZWNvbmRzXG4gIGVuYWJsZUdyYXBoT3ZlcmxheTogdHJ1ZSxcbn07XG5cbi8vIE1BUks6IC0gUGx1Z2luXG5cbmV4cG9ydCBkZWZhdWx0IGNsYXNzIEh5ZHJhUGx1Z2luIGV4dGVuZHMgUGx1Z2luIHtcbiAgc2V0dGluZ3M6IEh5ZHJhU2V0dGluZ3MgPSBERUZBVUxUX1NFVFRJTkdTO1xuICBicmlkZ2U6IEh5ZHJhQnJpZGdlO1xuICBwcml2YXRlIHJlZnJlc2hUaW1lcjogbnVtYmVyIHwgbnVsbCA9IG51bGw7XG5cbiAgYXN5bmMgb25sb2FkKCkge1xuICAgIHRyeSB7XG4gICAgICBhd2FpdCB0aGlzLmluaXRpYWxpemVQbHVnaW4oKTtcbiAgICB9IGNhdGNoIChlcnIpIHtcbiAgICAgIGNvbnN0IG1zZyA9IGVyciBpbnN0YW5jZW9mIEVycm9yID8gZXJyLm1lc3NhZ2UgOiBTdHJpbmcoZXJyKTtcbiAgICAgIG5ldyBOb3RpY2UoYEh5ZHJhIHBhcnRpYWxseSBmYWlsZWQ6ICR7bXNnfWAsIDgwMDApO1xuICAgICAgY29uc29sZS5lcnJvcignSHlkcmEgb25sb2FkIGVycm9yOicsIGVycik7XG4gICAgfVxuICB9XG5cbiAgcHJpdmF0ZSBhc3luYyBpbml0aWFsaXplUGx1Z2luKCkge1xuICAgIGF3YWl0IHRoaXMubG9hZFNldHRpbmdzKCk7XG5cbiAgICAvLyBJbml0aWFsaXplIHRoZSBicmlkZ2UgdG8gdGhlIEh5ZHJhIGJpbmFyeVxuICAgIHRoaXMuYnJpZGdlID0gbmV3IEh5ZHJhQnJpZGdlKHRoaXMuc2V0dGluZ3MuYmluYXJ5UGF0aCB8fCBhd2FpdCB0aGlzLmRldGVjdEJpbmFyeSgpKTtcblxuICAgIC8vIFJlZ2lzdGVyIHZpZXdzXG4gICAgdGhpcy5yZWdpc3RlclZpZXcoU0lERUJBUl9WSUVXX1RZUEUsIChsZWFmKSA9PiBuZXcgSHlkcmFTaWRlYmFyVmlldyhsZWFmLCB0aGlzKSk7XG4gICAgdGhpcy5yZWdpc3RlclZpZXcoSEVBTFRIX1ZJRVdfVFlQRSwgKGxlYWYpID0+IG5ldyBIeWRyYUhlYWx0aFZpZXcobGVhZiwgdGhpcykpO1xuXG4gICAgLy8gUmliYm9uIGljb25cbiAgICB0aGlzLmFkZFJpYmJvbkljb24oJ2Ryb3BsZXQnLCAnSHlkcmEnLCAoKSA9PiB7XG4gICAgICB0aGlzLmFjdGl2YXRlU2lkZWJhcigpO1xuICAgIH0pO1xuXG4gICAgLy8gQ29tbWFuZHNcbiAgICB0aGlzLmFkZENvbW1hbmQoe1xuICAgICAgaWQ6ICdoeWRyYS1zY2FuJyxcbiAgICAgIG5hbWU6ICdTY2FuIHZhdWx0JyxcbiAgICAgIGNhbGxiYWNrOiAoKSA9PiB0aGlzLnNjYW5WYXVsdCgpLFxuICAgIH0pO1xuXG4gICAgdGhpcy5hZGRDb21tYW5kKHtcbiAgICAgIGlkOiAnaHlkcmEtaHlkcmF0ZS1jdXJyZW50JyxcbiAgICAgIG5hbWU6ICdIeWRyYXRlIGN1cnJlbnQgbm90ZScsXG4gICAgICBjYWxsYmFjazogKCkgPT4gdGhpcy5oeWRyYXRlQ3VycmVudE5vdGUoKSxcbiAgICB9KTtcblxuICAgIHRoaXMuYWRkQ29tbWFuZCh7XG4gICAgICBpZDogJ2h5ZHJhLWhlYWx0aCcsXG4gICAgICBuYW1lOiAnU2hvdyB2YXVsdCBoZWFsdGgnLFxuICAgICAgY2FsbGJhY2s6ICgpID0+IHRoaXMuc2hvd0hlYWx0aCgpLFxuICAgIH0pO1xuXG4gICAgdGhpcy5hZGRDb21tYW5kKHtcbiAgICAgIGlkOiAnaHlkcmEtc3VnZ2VzdC10YWdzJyxcbiAgICAgIG5hbWU6ICdTdWdnZXN0IHRhZ3MgZm9yIGN1cnJlbnQgbm90ZScsXG4gICAgICBjYWxsYmFjazogKCkgPT4gdGhpcy5zdWdnZXN0VGFncygpLFxuICAgIH0pO1xuXG4gICAgdGhpcy5hZGRDb21tYW5kKHtcbiAgICAgIGlkOiAnaHlkcmEtZmluZC1yZWxhdGlvbnMnLFxuICAgICAgbmFtZTogJ0ZpbmQgcmVsYXRpb25zaGlwcyBmb3IgY3VycmVudCBub3RlJyxcbiAgICAgIGNhbGxiYWNrOiAoKSA9PiB0aGlzLmZpbmRSZWxhdGlvbnNoaXBzKCksXG4gICAgfSk7XG5cbiAgICAvLyBTZXR0aW5ncyB0YWJcbiAgICB0aGlzLmFkZFNldHRpbmdUYWIobmV3IEh5ZHJhU2V0dGluZ1RhYih0aGlzLmFwcCwgdGhpcykpO1xuXG4gICAgLy8gQXV0by1yZWZyZXNoIG9uIG5vdGUgc2F2ZVxuICAgIHRoaXMucmVnaXN0ZXJFdmVudChcbiAgICAgIHRoaXMuYXBwLnZhdWx0Lm9uKCdtb2RpZnknLCAoZmlsZSkgPT4ge1xuICAgICAgICBpZiAoZmlsZSBpbnN0YW5jZW9mIFRGaWxlICYmIGZpbGUuZXh0ZW5zaW9uID09PSAnbWQnICYmIHRoaXMuc2V0dGluZ3MuYXV0b1RhZykge1xuICAgICAgICAgIHRoaXMuaHlkcmF0ZU5vdGUoZmlsZSk7XG4gICAgICAgIH1cbiAgICAgIH0pXG4gICAgKTtcblxuICAgIC8vIFN0YXJ0IHJlZnJlc2ggdGltZXJcbiAgICB0aGlzLnN0YXJ0UmVmcmVzaFRpbWVyKCk7XG5cbiAgICBjb25zb2xlLmxvZygnSHlkcmEgcGx1Z2luIGxvYWRlZCcpO1xuICB9XG5cbiAgb251bmxvYWQoKSB7XG4gICAgaWYgKHRoaXMucmVmcmVzaFRpbWVyKSB7XG4gICAgICB3aW5kb3cuY2xlYXJJbnRlcnZhbCh0aGlzLnJlZnJlc2hUaW1lcik7XG4gICAgfVxuICB9XG5cbiAgLy8gTUFSSzogLSBCaW5hcnkgZGV0ZWN0aW9uXG5cbiAgcHJpdmF0ZSBhc3luYyBkZXRlY3RCaW5hcnkoKTogUHJvbWlzZTxzdHJpbmc+IHtcbiAgICAvLyBUcnkgY29tbW9uIGxvY2F0aW9uc1xuICAgIGNvbnN0IGNhbmRpZGF0ZXMgPSBbXG4gICAgICAnL3Vzci9sb2NhbC9iaW4vaHlkcmEnLFxuICAgICAgJy9vcHQvaG9tZWJyZXcvYmluL2h5ZHJhJyxcbiAgICAgIGAke3Byb2Nlc3MuZW52LkhPTUV9Ly5sb2NhbC9iaW4vaHlkcmFgLFxuICAgIF07XG5cbiAgICBsZXQgZXhlY0ZpbGVTeW5jOiBhbnkgPSBudWxsO1xuICAgIHRyeSB7IGV4ZWNGaWxlU3luYyA9IHJlcXVpcmUoJ2NoaWxkX3Byb2Nlc3MnKS5leGVjRmlsZVN5bmM7IH0gY2F0Y2gge31cbiAgICBmb3IgKGNvbnN0IHBhdGggb2YgY2FuZGlkYXRlcykge1xuICAgICAgdHJ5IHtcbiAgICAgICAgZXhlY0ZpbGVTeW5jKHBhdGgsIFsnLS12ZXJzaW9uJ10sIHsgc3RkaW86ICdpZ25vcmUnIH0pO1xuICAgICAgICByZXR1cm4gcGF0aDtcbiAgICAgIH0gY2F0Y2gge1xuICAgICAgICBjb250aW51ZTtcbiAgICAgIH1cbiAgICB9XG5cbiAgICBuZXcgTm90aWNlKCdIeWRyYSBiaW5hcnkgbm90IGZvdW5kLiBTZXQgcGF0aCBpbiBzZXR0aW5ncy4nLCA1MDAwKTtcbiAgICByZXR1cm4gJ2h5ZHJhJztcbiAgfVxuXG4gIC8vIE1BUks6IC0gQWN0aW9uc1xuXG4gIGFzeW5jIHNjYW5WYXVsdCgpIHtcbiAgICBuZXcgTm90aWNlKCdIeWRyYTogU2Nhbm5pbmcgdmF1bHQuLi4nKTtcbiAgICB0cnkge1xuICAgICAgY29uc3QgcmVzdWx0ID0gYXdhaXQgdGhpcy5icmlkZ2Uuc2Nhbih0aGlzLmFwcC52YXVsdC5hZGFwdGVyLmdldEJhc2VQYXRoKCkpO1xuICAgICAgbmV3IE5vdGljZShgSHlkcmE6ICR7cmVzdWx0Lm5vdGVzfSBub3RlcywgJHtyZXN1bHQudGFnc30gdGFncywgJHtyZXN1bHQub3JwaGFuZWR9IG9ycGhhbmVkYCk7XG5cbiAgICAgIC8vIFVwZGF0ZSBzaWRlYmFyXG4gICAgICBjb25zdCBzaWRlYmFyID0gdGhpcy5nZXRTaWRlYmFyKCk7XG4gICAgICBpZiAoc2lkZWJhcikgc2lkZWJhci51cGRhdGVTY2FuUmVzdWx0KHJlc3VsdCk7XG4gICAgfSBjYXRjaCAoZXJyKSB7XG4gICAgICBuZXcgTm90aWNlKGBIeWRyYTogU2NhbiBmYWlsZWQgXHUyMDE0ICR7ZXJyLm1lc3NhZ2V9YCk7XG4gICAgfVxuICB9XG5cbiAgYXN5bmMgaHlkcmF0ZUN1cnJlbnROb3RlKCkge1xuICAgIGNvbnN0IGZpbGUgPSB0aGlzLmFwcC53b3Jrc3BhY2UuZ2V0QWN0aXZlRmlsZSgpO1xuICAgIGlmICghZmlsZSB8fCBmaWxlLmV4dGVuc2lvbiAhPT0gJ21kJykge1xuICAgICAgbmV3IE5vdGljZSgnSHlkcmE6IE9wZW4gYSBtYXJrZG93biBmaWxlIGZpcnN0Jyk7XG4gICAgICByZXR1cm47XG4gICAgfVxuICAgIGF3YWl0IHRoaXMuaHlkcmF0ZU5vdGUoZmlsZSk7XG4gIH1cblxuICBwcml2YXRlIGFzeW5jIGh5ZHJhdGVOb3RlKGZpbGU6IFRGaWxlKSB7XG4gICAgdHJ5IHtcbiAgICAgIGNvbnN0IGNvbnRlbnQgPSBhd2FpdCB0aGlzLmFwcC52YXVsdC5yZWFkKGZpbGUpO1xuICAgICAgY29uc3Qgc3VnZ2VzdGlvbnMgPSBhd2FpdCB0aGlzLmJyaWRnZS5jbGFzc2lmeShmaWxlLnBhdGgsIGNvbnRlbnQpO1xuXG4gICAgICBpZiAoc3VnZ2VzdGlvbnMudGFncy5sZW5ndGggPiAwICYmIHRoaXMuc2V0dGluZ3MuYXV0b1RhZykge1xuICAgICAgICBjb25zdCB1cGRhdGVkID0gdGhpcy5hcHBseVRhZ3MoY29udGVudCwgc3VnZ2VzdGlvbnMudGFncyk7XG4gICAgICAgIGlmICh1cGRhdGVkICE9PSBjb250ZW50KSB7XG4gICAgICAgICAgYXdhaXQgdGhpcy5hcHAudmF1bHQubW9kaWZ5KGZpbGUsIHVwZGF0ZWQpO1xuICAgICAgICB9XG4gICAgICB9XG5cbiAgICAgIC8vIFVwZGF0ZSBzaWRlYmFyIHdpdGggc3VnZ2VzdGlvbnNcbiAgICAgIGNvbnN0IHNpZGViYXIgPSB0aGlzLmdldFNpZGViYXIoKTtcbiAgICAgIGlmIChzaWRlYmFyKSBzaWRlYmFyLnVwZGF0ZVN1Z2dlc3Rpb25zKGZpbGUsIHN1Z2dlc3Rpb25zKTtcbiAgICB9IGNhdGNoIChlcnIpIHtcbiAgICAgIC8vIFNpbGVudCBmYWlsIGZvciBhdXRvLWh5ZHJhdGlvbiBcdTIwMTQgZG9uJ3QgZGlzcnVwdCB3cml0aW5nXG4gICAgICBjb25zb2xlLndhcm4oJ0h5ZHJhIGh5ZHJhdGlvbiBlcnJvcjonLCBlcnIpO1xuICAgIH1cbiAgfVxuXG4gIGFzeW5jIHN1Z2dlc3RUYWdzKCkge1xuICAgIGNvbnN0IGZpbGUgPSB0aGlzLmFwcC53b3Jrc3BhY2UuZ2V0QWN0aXZlRmlsZSgpO1xuICAgIGlmICghZmlsZSkgcmV0dXJuO1xuXG4gICAgY29uc3QgY29udGVudCA9IGF3YWl0IHRoaXMuYXBwLnZhdWx0LnJlYWQoZmlsZSk7XG4gICAgY29uc3Qgc3VnZ2VzdGlvbnMgPSBhd2FpdCB0aGlzLmJyaWRnZS5jbGFzc2lmeShmaWxlLnBhdGgsIGNvbnRlbnQpO1xuXG4gICAgY29uc3Qgc2lkZWJhciA9IGF3YWl0IHRoaXMuYWN0aXZhdGVTaWRlYmFyKCk7XG4gICAgc2lkZWJhci5zaG93VGFnU3VnZ2VzdGlvbnMoc3VnZ2VzdGlvbnMudGFncyk7XG4gIH1cblxuICBhc3luYyBmaW5kUmVsYXRpb25zaGlwcygpIHtcbiAgICBjb25zdCBmaWxlID0gdGhpcy5hcHAud29ya3NwYWNlLmdldEFjdGl2ZUZpbGUoKTtcbiAgICBpZiAoIWZpbGUpIHJldHVybjtcblxuICAgIGNvbnN0IGNvbnRlbnQgPSBhd2FpdCB0aGlzLmFwcC52YXVsdC5yZWFkKGZpbGUpO1xuICAgIGNvbnN0IHJlbHMgPSBhd2FpdCB0aGlzLmJyaWRnZS5maW5kUmVsYXRpb25zaGlwcyhmaWxlLmJhc2VuYW1lLCBjb250ZW50KTtcblxuICAgIGNvbnN0IHNpZGViYXIgPSBhd2FpdCB0aGlzLmFjdGl2YXRlU2lkZWJhcigpO1xuICAgIHNpZGViYXIuc2hvd1JlbGF0aW9uc2hpcHMocmVscyk7XG4gIH1cblxuICBhc3luYyBzaG93SGVhbHRoKCkge1xuICAgIGNvbnN0IHJlc3VsdCA9IGF3YWl0IHRoaXMuYnJpZGdlLmhlYWx0aCh0aGlzLmFwcC52YXVsdC5hZGFwdGVyLmdldEJhc2VQYXRoKCkpO1xuICAgIGNvbnN0IGxlYWYgPSB0aGlzLmFwcC53b3Jrc3BhY2UuZ2V0UmlnaHRMZWFmKGZhbHNlKTtcbiAgICBpZiAobGVhZikge1xuICAgICAgYXdhaXQgbGVhZi5zZXRWaWV3U3RhdGUoeyB0eXBlOiBIRUFMVEhfVklFV19UWVBFLCBlanNvbjogcmVzdWx0IH0pO1xuICAgICAgdGhpcy5hcHAud29ya3NwYWNlLnJldmVhbExlYWYobGVhZik7XG4gICAgfVxuICB9XG5cbiAgLy8gTUFSSzogLSBIZWxwZXJzXG5cbiAgcHJpdmF0ZSBhcHBseVRhZ3MoY29udGVudDogc3RyaW5nLCB0YWdzOiBzdHJpbmdbXSk6IHN0cmluZyB7XG4gICAgLy8gQWRkIHRhZ3MgdG8gZnJvbnRtYXR0ZXIgb3IgYXBwZW5kIGF0IGVuZFxuICAgIGlmIChjb250ZW50LnN0YXJ0c1dpdGgoJy0tLScpKSB7XG4gICAgICBjb25zdCBlbmQgPSBjb250ZW50LmluZGV4T2YoJ1xcbi0tLScsIDMpO1xuICAgICAgaWYgKGVuZCA+IDApIHtcbiAgICAgICAgY29uc3QgZnJvbnRtYXR0ZXIgPSBjb250ZW50LnN1YnN0cmluZygwLCBlbmQpO1xuICAgICAgICBjb25zdCBoYXNUYWdzID0gZnJvbnRtYXR0ZXIuaW5jbHVkZXMoJ3RhZ3M6Jyk7XG4gICAgICAgIGlmIChoYXNUYWdzKSB7XG4gICAgICAgICAgLy8gQXBwZW5kIHRvIGV4aXN0aW5nIHRhZ3NcbiAgICAgICAgICBjb25zdCB0YWdFbmQgPSBmcm9udG1hdHRlci5pbmRleE9mKCdcXG4nLCBmcm9udG1hdHRlci5pbmRleE9mKCd0YWdzOicpKTtcbiAgICAgICAgICBjb25zdCBuZXdUYWdzID0gdGFncy5tYXAodCA9PiBgICAtICR7dH1gKS5qb2luKCdcXG4nKTtcbiAgICAgICAgICByZXR1cm4gY29udGVudC5zdWJzdHJpbmcoMCwgdGFnRW5kICsgMSkgKyBuZXdUYWdzICsgY29udGVudC5zdWJzdHJpbmcodGFnRW5kKTtcbiAgICAgICAgfSBlbHNlIHtcbiAgICAgICAgICAvLyBBZGQgdGFncyBmaWVsZFxuICAgICAgICAgIGNvbnN0IHRhZ3NGaWVsZCA9IGB0YWdzOlxcbiR7dGFncy5tYXAodCA9PiBgICAtICR7dH1gKS5qb2luKCdcXG4nKX1cXG5gO1xuICAgICAgICAgIHJldHVybiBjb250ZW50LnN1YnN0cmluZygwLCBlbmQpICsgdGFnc0ZpZWxkICsgY29udGVudC5zdWJzdHJpbmcoZW5kKTtcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH1cbiAgICAvLyBObyBmcm9udG1hdHRlciBcdTIwMTQgYXBwZW5kIHRhZ3MgYXQgZW5kXG4gICAgY29uc3QgdGFnU3RyaW5nID0gdGFncy5tYXAodCA9PiBgIyR7dH1gKS5qb2luKCcgJyk7XG4gICAgcmV0dXJuIGNvbnRlbnQgKyAnXFxuXFxuJyArIHRhZ1N0cmluZztcbiAgfVxuXG4gIHByaXZhdGUgc3RhcnRSZWZyZXNoVGltZXIoKSB7XG4gICAgaWYgKHRoaXMucmVmcmVzaFRpbWVyKSB3aW5kb3cuY2xlYXJJbnRlcnZhbCh0aGlzLnJlZnJlc2hUaW1lcik7XG4gICAgdGhpcy5yZWZyZXNoVGltZXIgPSB3aW5kb3cuc2V0SW50ZXJ2YWwoKCkgPT4ge1xuICAgICAgdGhpcy5zY2FuVmF1bHQoKTtcbiAgICB9LCB0aGlzLnNldHRpbmdzLnJlZnJlc2hJbnRlcnZhbCAqIDEwMDApO1xuICB9XG5cbiAgLy8gTUFSSzogLSBTaWRlYmFyXG5cbiAgcHJpdmF0ZSBnZXRTaWRlYmFyKCk6IEh5ZHJhU2lkZWJhclZpZXcgfCBudWxsIHtcbiAgICBjb25zdCBsZWF2ZXMgPSB0aGlzLmFwcC53b3Jrc3BhY2UuZ2V0TGVhdmVzT2ZUeXBlKFNJREVCQVJfVklFV19UWVBFKTtcbiAgICByZXR1cm4gbGVhdmVzLmxlbmd0aCA+IDAgPyBsZWF2ZXNbMF0udmlldyBhcyBIeWRyYVNpZGViYXJWaWV3IDogbnVsbDtcbiAgfVxuXG4gIHByaXZhdGUgYXN5bmMgYWN0aXZhdGVTaWRlYmFyKCk6IFByb21pc2U8SHlkcmFTaWRlYmFyVmlldz4ge1xuICAgIGNvbnN0IGV4aXN0aW5nID0gdGhpcy5nZXRTaWRlYmFyKCk7XG4gICAgaWYgKGV4aXN0aW5nKSByZXR1cm4gZXhpc3Rpbmc7XG5cbiAgICBjb25zdCBsZWFmID0gdGhpcy5hcHAud29ya3NwYWNlLmdldFJpZ2h0TGVhZihmYWxzZSk7XG4gICAgaWYgKCFsZWFmKSB0aHJvdyBuZXcgRXJyb3IoJ05vIHNpZGViYXIgbGVhZiBhdmFpbGFibGUnKTtcbiAgICBhd2FpdCBsZWFmLnNldFZpZXdTdGF0ZSh7IHR5cGU6IFNJREVCQVJfVklFV19UWVBFIH0pO1xuICAgIHRoaXMuYXBwLndvcmtzcGFjZS5yZXZlYWxMZWFmKGxlYWYpO1xuICAgIHJldHVybiBsZWFmLnZpZXcgYXMgSHlkcmFTaWRlYmFyVmlldztcbiAgfVxuXG4gIGFzeW5jIGxvYWRTZXR0aW5ncygpIHtcbiAgICB0aGlzLnNldHRpbmdzID0gT2JqZWN0LmFzc2lnbih7fSwgREVGQVVMVF9TRVRUSU5HUywgYXdhaXQgdGhpcy5sb2FkRGF0YSgpKTtcbiAgfVxuXG4gIGFzeW5jIHNhdmVTZXR0aW5ncygpIHtcbiAgICBhd2FpdCB0aGlzLnNhdmVEYXRhKHRoaXMuc2V0dGluZ3MpO1xuICAgIHRoaXMuYnJpZGdlLnVwZGF0ZUJpbmFyeSh0aGlzLnNldHRpbmdzLmJpbmFyeVBhdGgpO1xuICAgIHRoaXMuc3RhcnRSZWZyZXNoVGltZXIoKTtcbiAgfVxufVxuXG4vLyBNQVJLOiAtIFNldHRpbmdzIFRhYlxuXG5jbGFzcyBIeWRyYVNldHRpbmdUYWIgZXh0ZW5kcyBQbHVnaW5TZXR0aW5nVGFiIHtcbiAgcGx1Z2luOiBIeWRyYVBsdWdpbjtcblxuICBjb25zdHJ1Y3RvcihhcHA6IEFwcCwgcGx1Z2luOiBIeWRyYVBsdWdpbikge1xuICAgIHN1cGVyKGFwcCwgcGx1Z2luKTtcbiAgICB0aGlzLnBsdWdpbiA9IHBsdWdpbjtcbiAgfVxuXG4gIGRpc3BsYXkoKTogdm9pZCB7XG4gICAgY29uc3QgeyBjb250YWluZXJFbCB9ID0gdGhpcztcbiAgICBjb250YWluZXJFbC5lbXB0eSgpO1xuXG4gICAgY29udGFpbmVyRWwuY3JlYXRlRWwoJ2gzJywgeyB0ZXh0OiAnSHlkcmEgU2V0dGluZ3MnIH0pO1xuXG4gICAgbmV3IFNldHRpbmcoY29udGFpbmVyRWwpXG4gICAgICAuc2V0TmFtZSgnQmluYXJ5IHBhdGgnKVxuICAgICAgLnNldERlc2MoJ1BhdGggdG8gdGhlIGh5ZHJhIENMSSBiaW5hcnknKVxuICAgICAgLmFkZFRleHQodGV4dCA9PiB0ZXh0XG4gICAgICAgIC5zZXRQbGFjZWhvbGRlcignQXV0by1kZXRlY3QnKVxuICAgICAgICAuc2V0VmFsdWUodGhpcy5wbHVnaW4uc2V0dGluZ3MuYmluYXJ5UGF0aClcbiAgICAgICAgLm9uQ2hhbmdlKGFzeW5jICh2YWx1ZSkgPT4ge1xuICAgICAgICAgIHRoaXMucGx1Z2luLnNldHRpbmdzLmJpbmFyeVBhdGggPSB2YWx1ZTtcbiAgICAgICAgICBhd2FpdCB0aGlzLnBsdWdpbi5zYXZlU2V0dGluZ3MoKTtcbiAgICAgICAgfSkpO1xuXG4gICAgbmV3IFNldHRpbmcoY29udGFpbmVyRWwpXG4gICAgICAuc2V0TmFtZSgnQXV0by10YWcnKVxuICAgICAgLnNldERlc2MoJ0F1dG9tYXRpY2FsbHkgYWRkIHN1Z2dlc3RlZCB0YWdzIHdoZW4gbm90ZXMgYXJlIG1vZGlmaWVkJylcbiAgICAgIC5hZGRUb2dnbGUodG9nZ2xlID0+IHRvZ2dsZVxuICAgICAgICAuc2V0VmFsdWUodGhpcy5wbHVnaW4uc2V0dGluZ3MuYXV0b1RhZylcbiAgICAgICAgLm9uQ2hhbmdlKGFzeW5jICh2YWx1ZSkgPT4ge1xuICAgICAgICAgIHRoaXMucGx1Z2luLnNldHRpbmdzLmF1dG9UYWcgPSB2YWx1ZTtcbiAgICAgICAgICBhd2FpdCB0aGlzLnBsdWdpbi5zYXZlU2V0dGluZ3MoKTtcbiAgICAgICAgfSkpO1xuXG4gICAgbmV3IFNldHRpbmcoY29udGFpbmVyRWwpXG4gICAgICAuc2V0TmFtZSgnQXV0by1saW5rJylcbiAgICAgIC5zZXREZXNjKCdBdXRvbWF0aWNhbGx5IHN1Z2dlc3Qgd2lraWxpbmtzIGJldHdlZW4gcmVsYXRlZCBub3RlcycpXG4gICAgICAuYWRkVG9nZ2xlKHRvZ2dsZSA9PiB0b2dnbGVcbiAgICAgICAgLnNldFZhbHVlKHRoaXMucGx1Z2luLnNldHRpbmdzLmF1dG9MaW5rKVxuICAgICAgICAub25DaGFuZ2UoYXN5bmMgKHZhbHVlKSA9PiB7XG4gICAgICAgICAgdGhpcy5wbHVnaW4uc2V0dGluZ3MuYXV0b0xpbmsgPSB2YWx1ZTtcbiAgICAgICAgICBhd2FpdCB0aGlzLnBsdWdpbi5zYXZlU2V0dGluZ3MoKTtcbiAgICAgICAgfSkpO1xuXG4gICAgbmV3IFNldHRpbmcoY29udGFpbmVyRWwpXG4gICAgICAuc2V0TmFtZSgnQ29uZmlkZW5jZSB0aHJlc2hvbGQnKVxuICAgICAgLnNldERlc2MoJ01pbmltdW0gY29uZmlkZW5jZSBmb3IgYXV0by1jbGFzc2lmaWNhdGlvbiAoMC4wXHUyMDEzMS4wKScpXG4gICAgICAuYWRkU2xpZGVyKHNsaWRlciA9PiBzbGlkZXJcbiAgICAgICAgLnNldExpbWl0cygwLCAxLCAwLjA1KVxuICAgICAgICAuc2V0VmFsdWUodGhpcy5wbHVnaW4uc2V0dGluZ3MuY29uZmlkZW5jZVRocmVzaG9sZClcbiAgICAgICAgLnNldER5bmFtaWNUb29sdGlwKClcbiAgICAgICAgLm9uQ2hhbmdlKGFzeW5jICh2YWx1ZSkgPT4ge1xuICAgICAgICAgIHRoaXMucGx1Z2luLnNldHRpbmdzLmNvbmZpZGVuY2VUaHJlc2hvbGQgPSB2YWx1ZTtcbiAgICAgICAgICBhd2FpdCB0aGlzLnBsdWdpbi5zYXZlU2V0dGluZ3MoKTtcbiAgICAgICAgfSkpO1xuXG4gICAgbmV3IFNldHRpbmcoY29udGFpbmVyRWwpXG4gICAgICAuc2V0TmFtZSgnUmVmcmVzaCBpbnRlcnZhbCcpXG4gICAgICAuc2V0RGVzYygnU2Vjb25kcyBiZXR3ZWVuIGF1dG9tYXRpYyB2YXVsdCBzY2FucycpXG4gICAgICAuYWRkVGV4dCh0ZXh0ID0+IHRleHRcbiAgICAgICAgLnNldFZhbHVlKFN0cmluZyh0aGlzLnBsdWdpbi5zZXR0aW5ncy5yZWZyZXNoSW50ZXJ2YWwpKVxuICAgICAgICAub25DaGFuZ2UoYXN5bmMgKHZhbHVlKSA9PiB7XG4gICAgICAgICAgY29uc3QgbnVtID0gcGFyc2VJbnQodmFsdWUpO1xuICAgICAgICAgIGlmICghaXNOYU4obnVtKSAmJiBudW0gPiAwKSB7XG4gICAgICAgICAgICB0aGlzLnBsdWdpbi5zZXR0aW5ncy5yZWZyZXNoSW50ZXJ2YWwgPSBudW07XG4gICAgICAgICAgICBhd2FpdCB0aGlzLnBsdWdpbi5zYXZlU2V0dGluZ3MoKTtcbiAgICAgICAgICB9XG4gICAgICAgIH0pKTtcbiAgfVxufVxuIiwgIi8vIExhenktbG9hZCBjaGlsZF9wcm9jZXNzIChub3QgYXZhaWxhYmxlIGluIGFsbCBidW5kbGVyIGNvbnRleHRzKVxubGV0IGV4ZWNGaWxlQXN5bmM6ICgoY21kOiBzdHJpbmcsIGFyZ3M6IHN0cmluZ1tdLCBvcHRzPzogYW55KSA9PiBQcm9taXNlPHtzdGRvdXQ6IHN0cmluZ30+KSB8IG51bGwgPSBudWxsO1xudHJ5IHtcbiAgY29uc3QgeyBleGVjRmlsZSB9ID0gcmVxdWlyZSgnY2hpbGRfcHJvY2VzcycpO1xuICBjb25zdCB7IHByb21pc2lmeSB9ID0gcmVxdWlyZSgndXRpbCcpO1xuICBleGVjRmlsZUFzeW5jID0gcHJvbWlzaWZ5KGV4ZWNGaWxlKTtcbn0gY2F0Y2gge1xuICAvLyBjaGlsZF9wcm9jZXNzIHVuYXZhaWxhYmxlIFx1MjAxNCBoZXVyaXN0aWMtb25seSBtb2RlXG59XG5cbmV4cG9ydCBpbnRlcmZhY2UgU2NhblJlc3VsdCB7XG4gIG5vdGVzOiBudW1iZXI7XG4gIHRhZ3M6IG51bWJlcjtcbiAgb3JwaGFuZWQ6IG51bWJlcjtcbiAgYnJva2VuTGlua3M6IG51bWJlcjtcbiAgbWlzc2luZ0Zyb250bWF0dGVyOiBudW1iZXI7XG4gIHBhcmE6IHsgY2F0ZWdvcnk6IHN0cmluZzsgY291bnQ6IG51bWJlciB9W107XG59XG5cbmV4cG9ydCBpbnRlcmZhY2UgQ2xhc3NpZnlSZXN1bHQge1xuICB0YWdzOiBzdHJpbmdbXTtcbiAgd2lraWxpbmtzOiBzdHJpbmdbXTtcbiAga2luZDogc3RyaW5nO1xuICBsaWZlY3ljbGU6IHN0cmluZztcbiAgY29uZmlkZW5jZTogbnVtYmVyO1xuICByZWxhdGlvbnNoaXBzOiB7IHR5cGU6IHN0cmluZzsgdGFyZ2V0OiBzdHJpbmcgfVtdO1xufVxuXG5leHBvcnQgaW50ZXJmYWNlIEhlYWx0aFJlc3VsdCB7XG4gIHN0YXR1czogc3RyaW5nO1xuICBzdW1tYXJ5OiBzdHJpbmc7XG4gIGNoZWNrczogeyBuYW1lOiBzdHJpbmc7IHN0YXR1czogc3RyaW5nOyBtZXNzYWdlOiBzdHJpbmc7IGNvdW50OiBudW1iZXIgfVtdO1xufVxuXG5leHBvcnQgaW50ZXJmYWNlIFJlbGF0aW9uc2hpcFJlc3VsdCB7XG4gIHJlbGF0aW9uc2hpcHM6IHsgdHlwZTogc3RyaW5nOyB0YXJnZXQ6IHN0cmluZzsgY29uZmlkZW5jZTogbnVtYmVyIH1bXTtcbn1cblxuLy8gTUFSSzogLSBIeWRyYSBCaW5hcnkgQnJpZGdlXG5cbi8vLyBDYWxscyB0aGUgaHlkcmEgQ0xJIGJpbmFyeSBmb3IgYWxsIGhlYXZ5IGxpZnRpbmcuXG4vLy8gVGhlIHBsdWdpbiBpcyBhIHRoaW4gVHlwZVNjcmlwdCBzaGVsbCBcdTIwMTQgU3dpZnQgZG9lcyB0aGUgd29yay5cbmV4cG9ydCBjbGFzcyBIeWRyYUJyaWRnZSB7XG4gIHByaXZhdGUgYmluYXJ5UGF0aDogc3RyaW5nO1xuXG4gIGNvbnN0cnVjdG9yKGJpbmFyeVBhdGg6IHN0cmluZykge1xuICAgIHRoaXMuYmluYXJ5UGF0aCA9IGJpbmFyeVBhdGg7XG4gIH1cblxuICB1cGRhdGVCaW5hcnkocGF0aDogc3RyaW5nKSB7XG4gICAgdGhpcy5iaW5hcnlQYXRoID0gcGF0aDtcbiAgfVxuXG4gIC8vIE1BUks6IC0gQ29tbWFuZHNcblxuICBhc3luYyBzY2FuKHZhdWx0UGF0aDogc3RyaW5nKTogUHJvbWlzZTxTY2FuUmVzdWx0PiB7XG4gICAgY29uc3Qgb3V0cHV0ID0gYXdhaXQgdGhpcy5ydW4oWydzY2FuJywgJy0tdmF1bHQnLCB2YXVsdFBhdGhdKTtcbiAgICByZXR1cm4gdGhpcy5wYXJzZVNjYW5PdXRwdXQob3V0cHV0KTtcbiAgfVxuXG4gIGFzeW5jIGhlYWx0aCh2YXVsdFBhdGg6IHN0cmluZyk6IFByb21pc2U8SGVhbHRoUmVzdWx0PiB7XG4gICAgY29uc3Qgb3V0cHV0ID0gYXdhaXQgdGhpcy5ydW4oWydoZWFsdGgnLCAnLS12YXVsdCcsIHZhdWx0UGF0aF0pO1xuICAgIHJldHVybiB0aGlzLnBhcnNlSGVhbHRoT3V0cHV0KG91dHB1dCk7XG4gIH1cblxuICBhc3luYyBzZWFyY2godmF1bHRQYXRoOiBzdHJpbmcsIHF1ZXJ5OiBzdHJpbmcsIGxpbWl0OiBudW1iZXIgPSAyMCk6IFByb21pc2U8YW55W10+IHtcbiAgICBjb25zdCBvdXRwdXQgPSBhd2FpdCB0aGlzLnJ1bihbJ3NlYXJjaCcsICctLXZhdWx0JywgdmF1bHRQYXRoLCAnLS1xdWVyeScsIHF1ZXJ5LCAnLS1saW1pdCcsIFN0cmluZyhsaW1pdCldKTtcbiAgICByZXR1cm4gdGhpcy5wYXJzZVNlYXJjaE91dHB1dChvdXRwdXQpO1xuICB9XG5cbiAgYXN5bmMgY2xhc3NpZnkoZmlsZVBhdGg6IHN0cmluZywgY29udGVudDogc3RyaW5nKTogUHJvbWlzZTxDbGFzc2lmeVJlc3VsdD4ge1xuICAgIC8vIFdyaXRlIGNvbnRlbnQgdG8gYSB0ZW1wIGZpbGUsIHJ1biBjbGFzc2lmaWVyLCByZXR1cm4gcmVzdWx0c1xuICAgIC8vIEZvciBub3csIHVzZXMgaGV1cmlzdGljIGNsYXNzaWZpY2F0aW9uIGZyb20gdGhlIGFkYXB0ZXJcbiAgICBjb25zdCByZXN1bHQgPSBhd2FpdCB0aGlzLnJ1bihbJ2h5ZHJhdGUnLCAnLS1zb3VyY2UnLCBmaWxlUGF0aCwgJy0tZHJ5LXJ1biddKTtcbiAgICByZXR1cm4gdGhpcy5wYXJzZUNsYXNzaWZ5T3V0cHV0KHJlc3VsdCwgY29udGVudCk7XG4gIH1cblxuICBhc3luYyBmaW5kUmVsYXRpb25zaGlwcyhub3RlTmFtZTogc3RyaW5nLCBjb250ZW50OiBzdHJpbmcpOiBQcm9taXNlPFJlbGF0aW9uc2hpcFJlc3VsdD4ge1xuICAgIC8vIEV4dHJhY3Qgd2lraWxpbmtzIGFuZCBmaW5kIHJlbGF0ZWQgbm90ZXNcbiAgICBjb25zdCB3aWtpbGlua3MgPSB0aGlzLmV4dHJhY3RXaWtpbGlua3MoY29udGVudCk7XG4gICAgY29uc3QgdGFncyA9IHRoaXMuZXh0cmFjdFRhZ3MoY29udGVudCk7XG5cbiAgICByZXR1cm4ge1xuICAgICAgcmVsYXRpb25zaGlwczogW1xuICAgICAgICAuLi53aWtpbGlua3MubWFwKHcgPT4gKHsgdHlwZTogJ3dpa2lsaW5rJywgdGFyZ2V0OiB3LCBjb25maWRlbmNlOiAxLjAgfSkpLFxuICAgICAgICAuLi50YWdzLm1hcCh0ID0+ICh7IHR5cGU6ICd0YWcnLCB0YXJnZXQ6IGAjJHt0fWAsIGNvbmZpZGVuY2U6IDAuNyB9KSksXG4gICAgICBdLFxuICAgIH07XG4gIH1cblxuICAvLyBNQVJLOiAtIEJpbmFyeSBleGVjdXRpb25cblxuICBwcml2YXRlIGFzeW5jIHJ1bihhcmdzOiBzdHJpbmdbXSk6IFByb21pc2U8c3RyaW5nPiB7XG4gICAgaWYgKCFleGVjRmlsZUFzeW5jKSB7XG4gICAgICB0aHJvdyBuZXcgRXJyb3IoXCJCaW5hcnkgbW9kZSB1bmF2YWlsYWJsZSBcdTIwMTQgdXNpbmcgaGV1cmlzdGljIG1vZGVcIik7XG4gICAgfVxuICAgIHRyeSB7XG4gICAgICBjb25zdCB7IHN0ZG91dCB9ID0gYXdhaXQgZXhlY0ZpbGVBc3luYyh0aGlzLmJpbmFyeVBhdGgsIGFyZ3MsIHtcbiAgICAgICAgbWF4QnVmZmVyOiAxMCAqIDEwMjQgKiAxMDI0LFxuICAgICAgICB0aW1lb3V0OiAzMDAwMCxcbiAgICAgIH0pO1xuICAgICAgcmV0dXJuIHN0ZG91dDtcbiAgICB9IGNhdGNoIChlcnI6IGFueSkge1xuICAgICAgY29uc3QgbXNnID0gZXJyPy5tZXNzYWdlID8/IFN0cmluZyhlcnIpO1xuICAgICAgdGhyb3cgbmV3IEVycm9yKGBIeWRyYSBiaW5hcnkgZXJyb3I6ICR7bXNnfWApO1xuICAgIH1cbiAgfVxuXG4gIC8vIE1BUks6IC0gT3V0cHV0IHBhcnNlcnNcblxuICBwcml2YXRlIHBhcnNlU2Nhbk91dHB1dChvdXRwdXQ6IHN0cmluZyk6IFNjYW5SZXN1bHQge1xuICAgIGNvbnN0IHJlc3VsdDogU2NhblJlc3VsdCA9IHtcbiAgICAgIG5vdGVzOiAwLCB0YWdzOiAwLCBvcnBoYW5lZDogMCwgYnJva2VuTGlua3M6IDAsIG1pc3NpbmdGcm9udG1hdHRlcjogMCwgcGFyYTogW10sXG4gICAgfTtcblxuICAgIGNvbnN0IG5vdGVzTWF0Y2ggPSBvdXRwdXQubWF0Y2goL05vdGVzOlxccysoXFxkKykvKTtcbiAgICBjb25zdCB0YWdzTWF0Y2ggPSBvdXRwdXQubWF0Y2goL1RhZ3M6XFxzKyhcXGQrKS8pO1xuICAgIGNvbnN0IG9ycGhhbmVkTWF0Y2ggPSBvdXRwdXQubWF0Y2goL09ycGhhbmVkOlxccysoXFxkKykvKTtcbiAgICBjb25zdCBicm9rZW5NYXRjaCA9IG91dHB1dC5tYXRjaCgvQnJva2VuIHdpa2lsaW5rczpcXHMrKFxcZCspLyk7XG4gICAgY29uc3QgZnJvbnRtYXR0ZXJNYXRjaCA9IG91dHB1dC5tYXRjaCgvTWlzc2luZyBmcm9udG1hdHRlcjpcXHMrKFxcZCspLyk7XG5cbiAgICBpZiAobm90ZXNNYXRjaCkgcmVzdWx0Lm5vdGVzID0gcGFyc2VJbnQobm90ZXNNYXRjaFsxXSk7XG4gICAgaWYgKHRhZ3NNYXRjaCkgcmVzdWx0LnRhZ3MgPSBwYXJzZUludCh0YWdzTWF0Y2hbMV0pO1xuICAgIGlmIChvcnBoYW5lZE1hdGNoKSByZXN1bHQub3JwaGFuZWQgPSBwYXJzZUludChvcnBoYW5lZE1hdGNoWzFdKTtcbiAgICBpZiAoYnJva2VuTWF0Y2gpIHJlc3VsdC5icm9rZW5MaW5rcyA9IHBhcnNlSW50KGJyb2tlbk1hdGNoWzFdKTtcbiAgICBpZiAoZnJvbnRtYXR0ZXJNYXRjaCkgcmVzdWx0Lm1pc3NpbmdGcm9udG1hdHRlciA9IHBhcnNlSW50KGZyb250bWF0dGVyTWF0Y2hbMV0pO1xuXG4gICAgLy8gUGFyc2UgUEFSQSBicmVha2Rvd25cbiAgICBjb25zdCBwYXJhU2VjdGlvbiA9IG91dHB1dC5tYXRjaCgvUEFSQSBCcmVha2Rvd246KFtcXHNcXFNdKj8pKD89XFxuXFxufFxcbk9ycGhhbmVkfCQpLyk7XG4gICAgaWYgKHBhcmFTZWN0aW9uKSB7XG4gICAgICBjb25zdCBsaW5lcyA9IHBhcmFTZWN0aW9uWzFdLnRyaW0oKS5zcGxpdCgnXFxuJyk7XG4gICAgICBmb3IgKGNvbnN0IGxpbmUgb2YgbGluZXMpIHtcbiAgICAgICAgY29uc3QgbWF0Y2ggPSBsaW5lLm1hdGNoKC9eXFxzKyhcXFMrKVxccysoXFxkKykvKTtcbiAgICAgICAgaWYgKG1hdGNoKSB7XG4gICAgICAgICAgcmVzdWx0LnBhcmEucHVzaCh7IGNhdGVnb3J5OiBtYXRjaFsxXSwgY291bnQ6IHBhcnNlSW50KG1hdGNoWzJdKSB9KTtcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH1cblxuICAgIHJldHVybiByZXN1bHQ7XG4gIH1cblxuICBwcml2YXRlIHBhcnNlSGVhbHRoT3V0cHV0KG91dHB1dDogc3RyaW5nKTogSGVhbHRoUmVzdWx0IHtcbiAgICBjb25zdCBjaGVja3M6IHsgbmFtZTogc3RyaW5nOyBzdGF0dXM6IHN0cmluZzsgbWVzc2FnZTogc3RyaW5nOyBjb3VudDogbnVtYmVyIH1bXSA9IFtdO1xuXG4gICAgY29uc3QgbGluZXMgPSBvdXRwdXQuc3BsaXQoJ1xcbicpO1xuICAgIGZvciAoY29uc3QgbGluZSBvZiBsaW5lcykge1xuICAgICAgY29uc3QgbWF0Y2ggPSBsaW5lLm1hdGNoKC9bXHUyNzA1XHUyNkEwXHVGRTBGXHVEODNEXHVERDM0XVxccysoLis/KVxcc3syLH0oLispLyk7XG4gICAgICBpZiAobWF0Y2gpIHtcbiAgICAgICAgY29uc3QgbmFtZSA9IG1hdGNoWzFdLnRyaW0oKTtcbiAgICAgICAgY29uc3QgbWVzc2FnZSA9IG1hdGNoWzJdLnRyaW0oKTtcbiAgICAgICAgbGV0IHN0YXR1cyA9ICdoZWFsdGh5JztcbiAgICAgICAgaWYgKGxpbmUuaW5jbHVkZXMoJ1x1MjZBMFx1RkUwRicpKSBzdGF0dXMgPSAnd2FybmluZyc7XG4gICAgICAgIGVsc2UgaWYgKGxpbmUuaW5jbHVkZXMoJ1x1RDgzRFx1REQzNCcpKSBzdGF0dXMgPSAnY3JpdGljYWwnO1xuICAgICAgICBjaGVja3MucHVzaCh7IG5hbWUsIHN0YXR1cywgbWVzc2FnZSwgY291bnQ6IDAgfSk7XG4gICAgICB9XG4gICAgfVxuXG4gICAgY29uc3Qgb3ZlcmFsbE1hdGNoID0gb3V0cHV0Lm1hdGNoKC9PdmVyYWxsOlxccysoXFx3KykvKTtcbiAgICBjb25zdCBzdW1tYXJ5TWF0Y2ggPSBvdXRwdXQubWF0Y2goL1N1bW1hcnk6XFxzKyguKykvKTtcblxuICAgIHJldHVybiB7XG4gICAgICBzdGF0dXM6IG92ZXJhbGxNYXRjaCA/IG92ZXJhbGxNYXRjaFsxXS50b0xvd2VyQ2FzZSgpIDogJ3Vua25vd24nLFxuICAgICAgc3VtbWFyeTogc3VtbWFyeU1hdGNoID8gc3VtbWFyeU1hdGNoWzFdIDogJycsXG4gICAgICBjaGVja3MsXG4gICAgfTtcbiAgfVxuXG4gIHByaXZhdGUgcGFyc2VTZWFyY2hPdXRwdXQob3V0cHV0OiBzdHJpbmcpOiBhbnlbXSB7XG4gICAgY29uc3QgcmVzdWx0czogYW55W10gPSBbXTtcbiAgICBjb25zdCBsaW5lcyA9IG91dHB1dC5zcGxpdCgnXFxuJyk7XG4gICAgZm9yIChjb25zdCBsaW5lIG9mIGxpbmVzKSB7XG4gICAgICBpZiAobGluZS50cmltKCkuc3RhcnRzV2l0aCgnRm91bmQnKSkgY29udGludWU7XG4gICAgICBpZiAobGluZS50cmltKCkuc3RhcnRzV2l0aCgnXHUyMDE0JykpIGNvbnRpbnVlO1xuICAgICAgaWYgKGxpbmUudHJpbSgpLmxlbmd0aCA8IDMpIGNvbnRpbnVlO1xuICAgICAgLy8gUGFyc2UgXCJUaXRsZSBbdGFnc10gLyBwYXRoXCJcbiAgICAgIGNvbnN0IG1hdGNoID0gbGluZS5tYXRjaCgvXlxccysoLis/KSg/OlxccytcXFsoLispXFxdKT9cXHMqJC8pO1xuICAgICAgaWYgKG1hdGNoKSB7XG4gICAgICAgIHJlc3VsdHMucHVzaCh7XG4gICAgICAgICAgdGl0bGU6IG1hdGNoWzFdLnRyaW0oKSxcbiAgICAgICAgICB0YWdzOiBtYXRjaFsyXSA/IG1hdGNoWzJdLnNwbGl0KCcsICcpLm1hcCgodDogc3RyaW5nKSA9PiB0LnRyaW0oKSkgOiBbXSxcbiAgICAgICAgfSk7XG4gICAgICB9XG4gICAgfVxuICAgIHJldHVybiByZXN1bHRzO1xuICB9XG5cbiAgcHJpdmF0ZSBwYXJzZUNsYXNzaWZ5T3V0cHV0KG91dHB1dDogc3RyaW5nLCBjb250ZW50OiBzdHJpbmcpOiBDbGFzc2lmeVJlc3VsdCB7XG4gICAgLy8gRmFsbGJhY2s6IHVzZSBjb250ZW50LWJhc2VkIGhldXJpc3RpY3MgaWYgYmluYXJ5IGRvZXNuJ3QgcHJvdmlkZSBjbGFzc2lmaWNhdGlvblxuICAgIGNvbnN0IHRhZ3MgPSB0aGlzLmV4dHJhY3RUYWdzKGNvbnRlbnQpO1xuICAgIGNvbnN0IHdpa2lsaW5rcyA9IHRoaXMuZXh0cmFjdFdpa2lsaW5rcyhjb250ZW50KTtcblxuICAgIHJldHVybiB7XG4gICAgICB0YWdzLFxuICAgICAgd2lraWxpbmtzLFxuICAgICAga2luZDogJ25vdGUnLFxuICAgICAgbGlmZWN5Y2xlOiAnZHJhZnQnLFxuICAgICAgY29uZmlkZW5jZTogMC41LFxuICAgICAgcmVsYXRpb25zaGlwczogd2lraWxpbmtzLm1hcCh3ID0+ICh7IHR5cGU6ICdyZWZlcmVuY2VzJywgdGFyZ2V0OiB3IH0pKSxcbiAgICB9O1xuICB9XG5cbiAgLy8gTUFSSzogLSBDb250ZW50IGhlbHBlcnNcblxuICBwcml2YXRlIGV4dHJhY3RXaWtpbGlua3MoY29udGVudDogc3RyaW5nKTogc3RyaW5nW10ge1xuICAgIGNvbnN0IG1hdGNoZXMgPSBjb250ZW50Lm1hdGNoQWxsKC9cXFtcXFsoW15cXF18XSspKD86XFx8W15cXF1dKyk/XFxdXFxdL2cpO1xuICAgIHJldHVybiBBcnJheS5mcm9tKG1hdGNoZXMpLm1hcChtID0+IG1bMV0udHJpbSgpKTtcbiAgfVxuXG4gIHByaXZhdGUgZXh0cmFjdFRhZ3MoY29udGVudDogc3RyaW5nKTogc3RyaW5nW10ge1xuICAgIGNvbnN0IHRhZ3MgPSBuZXcgU2V0PHN0cmluZz4oKTtcbiAgICAvLyBJbmxpbmUgI3RhZ3NcbiAgICBjb25zdCBtYXRjaGVzID0gY29udGVudC5tYXRjaEFsbCgvKD86XnxcXHMpIyhbYS16QS1aXVthLXpBLVowLTkvXy1dKikvZyk7XG4gICAgZm9yIChjb25zdCBtYXRjaCBvZiBtYXRjaGVzKSB7XG4gICAgICB0YWdzLmFkZChtYXRjaFsxXS50b0xvd2VyQ2FzZSgpKTtcbiAgICB9XG4gICAgcmV0dXJuIEFycmF5LmZyb20odGFncyk7XG4gIH1cbn1cbiIsICJpbXBvcnQgeyBJdGVtVmlldywgV29ya3NwYWNlTGVhZiwgVEZpbGUgfSBmcm9tICdvYnNpZGlhbic7XG5pbXBvcnQgdHlwZSBIeWRyYVBsdWdpbiBmcm9tICcuL21haW4nO1xuaW1wb3J0IHR5cGUgeyBTY2FuUmVzdWx0LCBDbGFzc2lmeVJlc3VsdCwgUmVsYXRpb25zaGlwUmVzdWx0IH0gZnJvbSAnLi9icmlkZ2UnO1xuXG5leHBvcnQgY29uc3QgU0lERUJBUl9WSUVXX1RZUEUgPSAnaHlkcmEtc2lkZWJhcic7XG5cbmV4cG9ydCBjbGFzcyBIeWRyYVNpZGViYXJWaWV3IGV4dGVuZHMgSXRlbVZpZXcge1xuICBwbHVnaW46IEh5ZHJhUGx1Z2luO1xuICBwcml2YXRlIHNjYW5SZXN1bHQ6IFNjYW5SZXN1bHQgfCBudWxsID0gbnVsbDtcbiAgcHJpdmF0ZSBjdXJyZW50U3VnZ2VzdGlvbnM6IHsgZmlsZTogVEZpbGU7IHJlc3VsdDogQ2xhc3NpZnlSZXN1bHQgfSB8IG51bGwgPSBudWxsO1xuICBwcml2YXRlIGN1cnJlbnRSZWxhdGlvbnNoaXBzOiBSZWxhdGlvbnNoaXBSZXN1bHQgfCBudWxsID0gbnVsbDtcblxuICBjb25zdHJ1Y3RvcihsZWFmOiBXb3Jrc3BhY2VMZWFmLCBwbHVnaW46IEh5ZHJhUGx1Z2luKSB7XG4gICAgc3VwZXIobGVhZik7XG4gICAgdGhpcy5wbHVnaW4gPSBwbHVnaW47XG4gIH1cblxuICBnZXRWaWV3VHlwZSgpOiBzdHJpbmcgeyByZXR1cm4gU0lERUJBUl9WSUVXX1RZUEU7IH1cbiAgZ2V0RGlzcGxheVRleHQoKTogc3RyaW5nIHsgcmV0dXJuICdIeWRyYSc7IH1cbiAgZ2V0SWNvbigpOiBzdHJpbmcgeyByZXR1cm4gJ2Ryb3BsZXQnOyB9XG5cbiAgYXN5bmMgb25PcGVuKCkge1xuICAgIHRoaXMucmVuZGVyKCk7XG4gIH1cblxuICBhc3luYyBvbkNsb3NlKCkge31cblxuICAvLyBNQVJLOiAtIFVwZGF0ZXNcblxuICB1cGRhdGVTY2FuUmVzdWx0KHJlc3VsdDogU2NhblJlc3VsdCkge1xuICAgIHRoaXMuc2NhblJlc3VsdCA9IHJlc3VsdDtcbiAgICB0aGlzLnJlbmRlcigpO1xuICB9XG5cbiAgdXBkYXRlU3VnZ2VzdGlvbnMoZmlsZTogVEZpbGUsIHJlc3VsdDogQ2xhc3NpZnlSZXN1bHQpIHtcbiAgICB0aGlzLmN1cnJlbnRTdWdnZXN0aW9ucyA9IHsgZmlsZSwgcmVzdWx0IH07XG4gICAgdGhpcy5yZW5kZXIoKTtcbiAgfVxuXG4gIHNob3dUYWdTdWdnZXN0aW9ucyh0YWdzOiBzdHJpbmdbXSkge1xuICAgIHRoaXMucmVuZGVyVGFnU3VnZ2VzdGlvbnModGFncyk7XG4gIH1cblxuICBzaG93UmVsYXRpb25zaGlwcyhyZWxzOiBSZWxhdGlvbnNoaXBSZXN1bHQpIHtcbiAgICB0aGlzLmN1cnJlbnRSZWxhdGlvbnNoaXBzID0gcmVscztcbiAgICB0aGlzLnJlbmRlcigpO1xuICB9XG5cbiAgLy8gTUFSSzogLSBSZW5kZXJpbmdcblxuICBwcml2YXRlIHJlbmRlcigpIHtcbiAgICBjb25zdCBjb250YWluZXIgPSB0aGlzLmNvbnRlbnRFbDtcbiAgICBjb250YWluZXIuZW1wdHkoKTtcbiAgICBjb250YWluZXIuYWRkQ2xhc3MoJ2h5ZHJhLXNpZGViYXInKTtcblxuICAgIC8vIEhlYWRlclxuICAgIGNvbnN0IGhlYWRlciA9IGNvbnRhaW5lci5jcmVhdGVEaXYoeyBjbHM6ICdoeWRyYS1oZWFkZXInIH0pO1xuICAgIGhlYWRlci5jcmVhdGVFbCgnc3BhbicsIHsgdGV4dDogJ0h5ZHJhJywgY2xzOiAnaHlkcmEtbG9nbycgfSk7XG4gICAgaGVhZGVyLmNyZWF0ZUVsKCdzcGFuJywgeyB0ZXh0OiAnQ29udGV4dCBIeWRyYXRpb24nLCBjbHM6ICdoeWRyYS10YWdsaW5lJyB9KTtcblxuICAgIC8vIFN0YXRzXG4gICAgaWYgKHRoaXMuc2NhblJlc3VsdCkge1xuICAgICAgdGhpcy5yZW5kZXJTdGF0cyhjb250YWluZXIpO1xuICAgIH1cblxuICAgIC8vIFN1Z2dlc3Rpb25zXG4gICAgaWYgKHRoaXMuY3VycmVudFN1Z2dlc3Rpb25zKSB7XG4gICAgICB0aGlzLnJlbmRlclN1Z2dlc3Rpb25zKGNvbnRhaW5lcik7XG4gICAgfVxuXG4gICAgLy8gUmVsYXRpb25zaGlwc1xuICAgIGlmICh0aGlzLmN1cnJlbnRSZWxhdGlvbnNoaXBzKSB7XG4gICAgICB0aGlzLnJlbmRlclJlbGF0aW9uc2hpcHMoY29udGFpbmVyKTtcbiAgICB9XG5cbiAgICAvLyBBY3Rpb25zXG4gICAgdGhpcy5yZW5kZXJBY3Rpb25zKGNvbnRhaW5lcik7XG4gIH1cblxuICBwcml2YXRlIHJlbmRlclN0YXRzKGNvbnRhaW5lcjogSFRNTEVsZW1lbnQpIHtcbiAgICBjb25zdCByID0gdGhpcy5zY2FuUmVzdWx0ITtcbiAgICBjb25zdCBzdGF0cyA9IGNvbnRhaW5lci5jcmVhdGVEaXYoeyBjbHM6ICdoeWRyYS1zdGF0cycgfSk7XG5cbiAgICBjb25zdCBjYXJkcyA9IFtcbiAgICAgIHsgbGFiZWw6ICdOb3RlcycsIHZhbHVlOiByLm5vdGVzLCBpY29uOiAnXHVEODNEXHVEQ0M0JyB9LFxuICAgICAgeyBsYWJlbDogJ1RhZ3MnLCB2YWx1ZTogci50YWdzLCBpY29uOiAnXHVEODNDXHVERkY3XHVGRTBGJyB9LFxuICAgICAgeyBsYWJlbDogJ09ycGhhbmVkJywgdmFsdWU6IHIub3JwaGFuZWQsIGljb246ICdcdUQ4M0RcdURDN0InIH0sXG4gICAgICB7IGxhYmVsOiAnQnJva2VuJywgdmFsdWU6IHIuYnJva2VuTGlua3MsIGljb246ICdcdUQ4M0RcdUREMTcnIH0sXG4gICAgXTtcblxuICAgIGZvciAoY29uc3QgY2FyZCBvZiBjYXJkcykge1xuICAgICAgY29uc3QgZWwgPSBzdGF0cy5jcmVhdGVEaXYoeyBjbHM6ICdoeWRyYS1zdGF0LWNhcmQnIH0pO1xuICAgICAgZWwuY3JlYXRlRWwoJ3NwYW4nLCB7IHRleHQ6IGNhcmQuaWNvbiwgY2xzOiAnaHlkcmEtc3RhdC1pY29uJyB9KTtcbiAgICAgIGVsLmNyZWF0ZUVsKCdzcGFuJywgeyB0ZXh0OiBTdHJpbmcoY2FyZC52YWx1ZSksIGNsczogJ2h5ZHJhLXN0YXQtdmFsdWUnIH0pO1xuICAgICAgZWwuY3JlYXRlRWwoJ3NwYW4nLCB7IHRleHQ6IGNhcmQubGFiZWwsIGNsczogJ2h5ZHJhLXN0YXQtbGFiZWwnIH0pO1xuICAgIH1cblxuICAgIC8vIFBBUkEgYnJlYWtkb3duXG4gICAgaWYgKHIucGFyYS5sZW5ndGggPiAwKSB7XG4gICAgICBjb25zdCBwYXJhID0gY29udGFpbmVyLmNyZWF0ZURpdih7IGNsczogJ2h5ZHJhLXBhcmEnIH0pO1xuICAgICAgcGFyYS5jcmVhdGVFbCgnZGl2JywgeyB0ZXh0OiAnUEFSQSBCUkVBS0RPV04nLCBjbHM6ICdoeWRyYS1zZWN0aW9uLXRpdGxlJyB9KTtcbiAgICAgIGZvciAoY29uc3QgcCBvZiByLnBhcmEuc2xpY2UoMCwgNikpIHtcbiAgICAgICAgY29uc3Qgcm93ID0gcGFyYS5jcmVhdGVEaXYoeyBjbHM6ICdoeWRyYS1wYXJhLXJvdycgfSk7XG4gICAgICAgIHJvdy5jcmVhdGVFbCgnc3BhbicsIHsgdGV4dDogcC5jYXRlZ29yeSwgY2xzOiAnaHlkcmEtcGFyYS1jYXQnIH0pO1xuICAgICAgICByb3cuY3JlYXRlRWwoJ3NwYW4nLCB7IHRleHQ6IFN0cmluZyhwLmNvdW50KSwgY2xzOiAnaHlkcmEtcGFyYS1jb3VudCcgfSk7XG4gICAgICB9XG4gICAgfVxuICB9XG5cbiAgcHJpdmF0ZSByZW5kZXJTdWdnZXN0aW9ucyhjb250YWluZXI6IEhUTUxFbGVtZW50KSB7XG4gICAgY29uc3QgcyA9IHRoaXMuY3VycmVudFN1Z2dlc3Rpb25zITtcbiAgICBjb25zdCBzZWN0aW9uID0gY29udGFpbmVyLmNyZWF0ZURpdih7IGNsczogJ2h5ZHJhLXN1Z2dlc3Rpb25zJyB9KTtcbiAgICBzZWN0aW9uLmNyZWF0ZUVsKCdkaXYnLCB7IHRleHQ6ICdTVUdHRVNURUQgVEFHUycsIGNsczogJ2h5ZHJhLXNlY3Rpb24tdGl0bGUnIH0pO1xuXG4gICAgZm9yIChjb25zdCB0YWcgb2Ygcy5yZXN1bHQudGFncykge1xuICAgICAgY29uc3QgY2hpcCA9IHNlY3Rpb24uY3JlYXRlRGl2KHsgY2xzOiAnaHlkcmEtdGFnLWNoaXAnIH0pO1xuICAgICAgY2hpcC5jcmVhdGVFbCgnc3BhbicsIHsgdGV4dDogJyMnLCBjbHM6ICdoeWRyYS10YWctaGFzaCcgfSk7XG4gICAgICBjaGlwLmNyZWF0ZUVsKCdzcGFuJywgeyB0ZXh0OiB0YWcgfSk7XG4gICAgICBjaGlwLm9uQ2xpY2tFdmVudCgoKSA9PiB7XG4gICAgICAgIHRoaXMuYXBwbHlUYWcocy5maWxlLCB0YWcpO1xuICAgICAgICBjaGlwLmFkZENsYXNzKCdoeWRyYS10YWctYXBwbGllZCcpO1xuICAgICAgfSk7XG4gICAgfVxuXG4gICAgaWYgKHMucmVzdWx0Lndpa2lsaW5rcy5sZW5ndGggPiAwKSB7XG4gICAgICBzZWN0aW9uLmNyZWF0ZUVsKCdkaXYnLCB7IHRleHQ6ICdXSUtJTElOS1MnLCBjbHM6ICdoeWRyYS1zZWN0aW9uLXRpdGxlJyB9KTtcbiAgICAgIGZvciAoY29uc3QgbGluayBvZiBzLnJlc3VsdC53aWtpbGlua3MpIHtcbiAgICAgICAgY29uc3QgZWwgPSBzZWN0aW9uLmNyZWF0ZURpdih7IGNsczogJ2h5ZHJhLXdpa2lsaW5rJyB9KTtcbiAgICAgICAgZWwuY3JlYXRlRWwoJ3NwYW4nLCB7IHRleHQ6ICdbWycsIGNsczogJ2h5ZHJhLWxpbmstYnJhY2tldCcgfSk7XG4gICAgICAgIGVsLmNyZWF0ZUVsKCdzcGFuJywgeyB0ZXh0OiBsaW5rIH0pO1xuICAgICAgICBlbC5jcmVhdGVFbCgnc3BhbicsIHsgdGV4dDogJ11dJywgY2xzOiAnaHlkcmEtbGluay1icmFja2V0JyB9KTtcbiAgICAgIH1cbiAgICB9XG4gIH1cblxuICBwcml2YXRlIHJlbmRlclJlbGF0aW9uc2hpcHMoY29udGFpbmVyOiBIVE1MRWxlbWVudCkge1xuICAgIGNvbnN0IHJlbHMgPSB0aGlzLmN1cnJlbnRSZWxhdGlvbnNoaXBzITtcbiAgICBjb25zdCBzZWN0aW9uID0gY29udGFpbmVyLmNyZWF0ZURpdih7IGNsczogJ2h5ZHJhLXJlbGF0aW9uc2hpcHMnIH0pO1xuICAgIHNlY3Rpb24uY3JlYXRlRWwoJ2RpdicsIHsgdGV4dDogJ1JFTEFUSU9OU0hJUFMnLCBjbHM6ICdoeWRyYS1zZWN0aW9uLXRpdGxlJyB9KTtcblxuICAgIGZvciAoY29uc3QgcmVsIG9mIHJlbHMucmVsYXRpb25zaGlwcykge1xuICAgICAgY29uc3QgZWwgPSBzZWN0aW9uLmNyZWF0ZURpdih7IGNsczogJ2h5ZHJhLXJlbC1yb3cnIH0pO1xuICAgICAgZWwuY3JlYXRlRWwoJ3NwYW4nLCB7IHRleHQ6IHJlbC50eXBlLCBjbHM6ICdoeWRyYS1yZWwtdHlwZScgfSk7XG4gICAgICBlbC5jcmVhdGVFbCgnc3BhbicsIHsgdGV4dDogJ1x1MjE5MicsIGNsczogJ2h5ZHJhLXJlbC1hcnJvdycgfSk7XG4gICAgICBlbC5jcmVhdGVFbCgnc3BhbicsIHsgdGV4dDogcmVsLnRhcmdldCwgY2xzOiAnaHlkcmEtcmVsLXRhcmdldCcgfSk7XG4gICAgfVxuICB9XG5cbiAgcHJpdmF0ZSByZW5kZXJUYWdTdWdnZXN0aW9ucyh0YWdzOiBzdHJpbmdbXSkge1xuICAgIGNvbnN0IGNvbnRhaW5lciA9IHRoaXMuY29udGVudEVsO1xuICAgIGNvbnRhaW5lci5lbXB0eSgpO1xuICAgIGNvbnRhaW5lci5hZGRDbGFzcygnaHlkcmEtc2lkZWJhcicpO1xuXG4gICAgY29udGFpbmVyLmNyZWF0ZUVsKCdkaXYnLCB7IHRleHQ6ICdTVUdHRVNURUQgVEFHUycsIGNsczogJ2h5ZHJhLXNlY3Rpb24tdGl0bGUnIH0pO1xuICAgIGZvciAoY29uc3QgdGFnIG9mIHRhZ3MpIHtcbiAgICAgIGNvbnN0IGNoaXAgPSBjb250YWluZXIuY3JlYXRlRGl2KHsgY2xzOiAnaHlkcmEtdGFnLWNoaXAnIH0pO1xuICAgICAgY2hpcC5jcmVhdGVFbCgnc3BhbicsIHsgdGV4dDogJyMnLCBjbHM6ICdoeWRyYS10YWctaGFzaCcgfSk7XG4gICAgICBjaGlwLmNyZWF0ZUVsKCdzcGFuJywgeyB0ZXh0OiB0YWcgfSk7XG4gICAgfVxuICB9XG5cbiAgcHJpdmF0ZSByZW5kZXJBY3Rpb25zKGNvbnRhaW5lcjogSFRNTEVsZW1lbnQpIHtcbiAgICBjb25zdCBhY3Rpb25zID0gY29udGFpbmVyLmNyZWF0ZURpdih7IGNsczogJ2h5ZHJhLWFjdGlvbnMnIH0pO1xuXG4gICAgY29uc3Qgc2NhbkJ0biA9IGFjdGlvbnMuY3JlYXRlRWwoJ2J1dHRvbicsIHsgdGV4dDogJ1NjYW4gVmF1bHQnLCBjbHM6ICdoeWRyYS1idG4nIH0pO1xuICAgIHNjYW5CdG4ub25DbGlja0V2ZW50KCgpID0+IHRoaXMucGx1Z2luLnNjYW5WYXVsdCgpKTtcblxuICAgIGNvbnN0IGhlYWx0aEJ0biA9IGFjdGlvbnMuY3JlYXRlRWwoJ2J1dHRvbicsIHsgdGV4dDogJ0hlYWx0aCcsIGNsczogJ2h5ZHJhLWJ0bicgfSk7XG4gICAgaGVhbHRoQnRuLm9uQ2xpY2tFdmVudCgoKSA9PiB0aGlzLnBsdWdpbi5zaG93SGVhbHRoKCkpO1xuICB9XG5cbiAgcHJpdmF0ZSBhc3luYyBhcHBseVRhZyhmaWxlOiBURmlsZSwgdGFnOiBzdHJpbmcpIHtcbiAgICBjb25zdCBjb250ZW50ID0gYXdhaXQgdGhpcy5hcHAudmF1bHQucmVhZChmaWxlKTtcbiAgICAvLyBDaGVjayBpZiB0YWcgYWxyZWFkeSBleGlzdHNcbiAgICBpZiAoY29udGVudC50b0xvd2VyQ2FzZSgpLmluY2x1ZGVzKGAjJHt0YWcudG9Mb3dlckNhc2UoKX1gKSkgcmV0dXJuO1xuXG4gICAgLy8gQWRkIHRvIGZyb250bWF0dGVyIG9yIGFwcGVuZFxuICAgIGlmIChjb250ZW50LnN0YXJ0c1dpdGgoJy0tLScpKSB7XG4gICAgICBjb25zdCBlbmQgPSBjb250ZW50LmluZGV4T2YoJ1xcbi0tLScsIDMpO1xuICAgICAgaWYgKGVuZCA+IDApIHtcbiAgICAgICAgY29uc3QgdXBkYXRlZCA9IGNvbnRlbnQuc3Vic3RyaW5nKDAsIGVuZCkgKyBgdGFnczpcXG4gIC0gJHt0YWd9XFxuYCArIGNvbnRlbnQuc3Vic3RyaW5nKGVuZCk7XG4gICAgICAgIGF3YWl0IHRoaXMuYXBwLnZhdWx0Lm1vZGlmeShmaWxlLCB1cGRhdGVkKTtcbiAgICAgICAgcmV0dXJuO1xuICAgICAgfVxuICAgIH1cbiAgICBhd2FpdCB0aGlzLmFwcC52YXVsdC5tb2RpZnkoZmlsZSwgY29udGVudCArIGBcXG5cXG4jJHt0YWd9YCk7XG4gIH1cbn1cbiIsICJpbXBvcnQgeyBJdGVtVmlldywgV29ya3NwYWNlTGVhZiB9IGZyb20gJ29ic2lkaWFuJztcbmltcG9ydCB0eXBlIEh5ZHJhUGx1Z2luIGZyb20gJy4vbWFpbic7XG5pbXBvcnQgdHlwZSB7IEhlYWx0aFJlc3VsdCB9IGZyb20gJy4vYnJpZGdlJztcblxuZXhwb3J0IGNvbnN0IEhFQUxUSF9WSUVXX1RZUEUgPSAnaHlkcmEtaGVhbHRoJztcblxuZXhwb3J0IGNsYXNzIEh5ZHJhSGVhbHRoVmlldyBleHRlbmRzIEl0ZW1WaWV3IHtcbiAgcGx1Z2luOiBIeWRyYVBsdWdpbjtcblxuICBjb25zdHJ1Y3RvcihsZWFmOiBXb3Jrc3BhY2VMZWFmLCBwbHVnaW46IEh5ZHJhUGx1Z2luKSB7XG4gICAgc3VwZXIobGVhZik7XG4gICAgdGhpcy5wbHVnaW4gPSBwbHVnaW47XG4gIH1cblxuICBnZXRWaWV3VHlwZSgpOiBzdHJpbmcgeyByZXR1cm4gSEVBTFRIX1ZJRVdfVFlQRTsgfVxuICBnZXREaXNwbGF5VGV4dCgpOiBzdHJpbmcgeyByZXR1cm4gJ0h5ZHJhIEhlYWx0aCc7IH1cbiAgZ2V0SWNvbigpOiBzdHJpbmcgeyByZXR1cm4gJ2hlYXJ0LXB1bHNlJzsgfVxuXG4gIGFzeW5jIG9uT3BlbigpIHtcbiAgICB0aGlzLnJlbmRlcigpO1xuICB9XG5cbiAgYXN5bmMgb25DbG9zZSgpIHt9XG5cbiAgc2V0SGVhbHRoUmVzdWx0KHJlc3VsdDogSGVhbHRoUmVzdWx0KSB7XG4gICAgdGhpcy5yZW5kZXIocmVzdWx0KTtcbiAgfVxuXG4gIHByaXZhdGUgcmVuZGVyKHJlc3VsdD86IEhlYWx0aFJlc3VsdCkge1xuICAgIGNvbnN0IGNvbnRhaW5lciA9IHRoaXMuY29udGVudEVsO1xuICAgIGNvbnRhaW5lci5lbXB0eSgpO1xuICAgIGNvbnRhaW5lci5hZGRDbGFzcygnaHlkcmEtaGVhbHRoJyk7XG5cbiAgICBpZiAoIXJlc3VsdCkge1xuICAgICAgY29udGFpbmVyLmNyZWF0ZUVsKCdwJywgeyB0ZXh0OiAnUnVuIGEgaGVhbHRoIGNoZWNrIHRvIHNlZSByZXN1bHRzLicgfSk7XG4gICAgICBjb25zdCBidG4gPSBjb250YWluZXIuY3JlYXRlRWwoJ2J1dHRvbicsIHsgdGV4dDogJ1J1biBIZWFsdGggQ2hlY2snLCBjbHM6ICdoeWRyYS1idG4nIH0pO1xuICAgICAgYnRuLm9uQ2xpY2tFdmVudCgoKSA9PiB0aGlzLnBsdWdpbi5zaG93SGVhbHRoKCkpO1xuICAgICAgcmV0dXJuO1xuICAgIH1cblxuICAgIC8vIE92ZXJhbGwgc3RhdHVzXG4gICAgY29uc3QgYmFubmVyID0gY29udGFpbmVyLmNyZWF0ZURpdih7IGNsczogYGh5ZHJhLWhlYWx0aC1iYW5uZXIgaHlkcmEtaGVhbHRoLSR7cmVzdWx0LnN0YXR1c31gIH0pO1xuICAgIGJhbm5lci5jcmVhdGVFbCgnc3BhbicsIHsgdGV4dDogcmVzdWx0LnN0YXR1cy50b1VwcGVyQ2FzZSgpLCBjbHM6ICdoeWRyYS1oZWFsdGgtc3RhdHVzJyB9KTtcbiAgICBiYW5uZXIuY3JlYXRlRWwoJ3NwYW4nLCB7IHRleHQ6IHJlc3VsdC5zdW1tYXJ5LCBjbHM6ICdoeWRyYS1oZWFsdGgtc3VtbWFyeScgfSk7XG5cbiAgICAvLyBDaGVja3NcbiAgICBmb3IgKGNvbnN0IGNoZWNrIG9mIHJlc3VsdC5jaGVja3MpIHtcbiAgICAgIGNvbnN0IHJvdyA9IGNvbnRhaW5lci5jcmVhdGVEaXYoeyBjbHM6IGBoeWRyYS1jaGVjay1yb3cgaHlkcmEtY2hlY2stJHtjaGVjay5zdGF0dXN9YCB9KTtcbiAgICAgIGNvbnN0IGljb24gPSBjaGVjay5zdGF0dXMgPT09ICdoZWFsdGh5JyA/ICdcdTI3MDUnIDogY2hlY2suc3RhdHVzID09PSAnd2FybmluZycgPyAnXHUyNkEwXHVGRTBGJyA6ICdcdUQ4M0RcdUREMzQnO1xuICAgICAgcm93LmNyZWF0ZUVsKCdzcGFuJywgeyB0ZXh0OiBpY29uLCBjbHM6ICdoeWRyYS1jaGVjay1pY29uJyB9KTtcblxuICAgICAgY29uc3QgaW5mbyA9IHJvdy5jcmVhdGVEaXYoeyBjbHM6ICdoeWRyYS1jaGVjay1pbmZvJyB9KTtcbiAgICAgIGluZm8uY3JlYXRlRWwoJ2RpdicsIHsgdGV4dDogY2hlY2submFtZSwgY2xzOiAnaHlkcmEtY2hlY2stbmFtZScgfSk7XG4gICAgICBpbmZvLmNyZWF0ZUVsKCdkaXYnLCB7IHRleHQ6IGNoZWNrLm1lc3NhZ2UsIGNsczogJ2h5ZHJhLWNoZWNrLW1lc3NhZ2UnIH0pO1xuXG4gICAgICBjb25zdCBiYWRnZSA9IHJvdy5jcmVhdGVFbCgnc3BhbicsIHsgdGV4dDogY2hlY2suc3RhdHVzLnRvVXBwZXJDYXNlKCksIGNsczogYGh5ZHJhLWNoZWNrLWJhZGdlIGh5ZHJhLWJhZGdlLSR7Y2hlY2suc3RhdHVzfWAgfSk7XG4gICAgfVxuICB9XG59XG4iXSwKICAibWFwcGluZ3MiOiAiOzs7Ozs7Ozs7Ozs7Ozs7Ozs7OztBQUFBO0FBQUE7QUFBQTtBQUFBO0FBQUE7QUFBQSxJQUFBQSxtQkFBcUY7OztBQ0NyRixJQUFJLGdCQUFpRztBQUNyRyxJQUFJO0FBQ0YsUUFBTSxFQUFFLFNBQVMsSUFBSSxRQUFRLGVBQWU7QUFDNUMsUUFBTSxFQUFFLFVBQVUsSUFBSSxRQUFRLE1BQU07QUFDcEMsa0JBQWdCLFVBQVUsUUFBUTtBQUNwQyxRQUFRO0FBRVI7QUFrQ08sSUFBTSxjQUFOLE1BQWtCO0FBQUEsRUFDZjtBQUFBLEVBRVIsWUFBWSxZQUFvQjtBQUM5QixTQUFLLGFBQWE7QUFBQSxFQUNwQjtBQUFBLEVBRUEsYUFBYSxNQUFjO0FBQ3pCLFNBQUssYUFBYTtBQUFBLEVBQ3BCO0FBQUE7QUFBQSxFQUlBLE1BQU0sS0FBSyxXQUF3QztBQUNqRCxVQUFNLFNBQVMsTUFBTSxLQUFLLElBQUksQ0FBQyxRQUFRLFdBQVcsU0FBUyxDQUFDO0FBQzVELFdBQU8sS0FBSyxnQkFBZ0IsTUFBTTtBQUFBLEVBQ3BDO0FBQUEsRUFFQSxNQUFNLE9BQU8sV0FBMEM7QUFDckQsVUFBTSxTQUFTLE1BQU0sS0FBSyxJQUFJLENBQUMsVUFBVSxXQUFXLFNBQVMsQ0FBQztBQUM5RCxXQUFPLEtBQUssa0JBQWtCLE1BQU07QUFBQSxFQUN0QztBQUFBLEVBRUEsTUFBTSxPQUFPLFdBQW1CLE9BQWUsUUFBZ0IsSUFBb0I7QUFDakYsVUFBTSxTQUFTLE1BQU0sS0FBSyxJQUFJLENBQUMsVUFBVSxXQUFXLFdBQVcsV0FBVyxPQUFPLFdBQVcsT0FBTyxLQUFLLENBQUMsQ0FBQztBQUMxRyxXQUFPLEtBQUssa0JBQWtCLE1BQU07QUFBQSxFQUN0QztBQUFBLEVBRUEsTUFBTSxTQUFTLFVBQWtCLFNBQTBDO0FBR3pFLFVBQU0sU0FBUyxNQUFNLEtBQUssSUFBSSxDQUFDLFdBQVcsWUFBWSxVQUFVLFdBQVcsQ0FBQztBQUM1RSxXQUFPLEtBQUssb0JBQW9CLFFBQVEsT0FBTztBQUFBLEVBQ2pEO0FBQUEsRUFFQSxNQUFNLGtCQUFrQixVQUFrQixTQUE4QztBQUV0RixVQUFNLFlBQVksS0FBSyxpQkFBaUIsT0FBTztBQUMvQyxVQUFNLE9BQU8sS0FBSyxZQUFZLE9BQU87QUFFckMsV0FBTztBQUFBLE1BQ0wsZUFBZTtBQUFBLFFBQ2IsR0FBRyxVQUFVLElBQUksUUFBTSxFQUFFLE1BQU0sWUFBWSxRQUFRLEdBQUcsWUFBWSxFQUFJLEVBQUU7QUFBQSxRQUN4RSxHQUFHLEtBQUssSUFBSSxRQUFNLEVBQUUsTUFBTSxPQUFPLFFBQVEsSUFBSSxDQUFDLElBQUksWUFBWSxJQUFJLEVBQUU7QUFBQSxNQUN0RTtBQUFBLElBQ0Y7QUFBQSxFQUNGO0FBQUE7QUFBQSxFQUlBLE1BQWMsSUFBSSxNQUFpQztBQUNqRCxRQUFJLENBQUMsZUFBZTtBQUNsQixZQUFNLElBQUksTUFBTSxxREFBZ0Q7QUFBQSxJQUNsRTtBQUNBLFFBQUk7QUFDRixZQUFNLEVBQUUsT0FBTyxJQUFJLE1BQU0sY0FBYyxLQUFLLFlBQVksTUFBTTtBQUFBLFFBQzVELFdBQVcsS0FBSyxPQUFPO0FBQUEsUUFDdkIsU0FBUztBQUFBLE1BQ1gsQ0FBQztBQUNELGFBQU87QUFBQSxJQUNULFNBQVMsS0FBVTtBQUNqQixZQUFNLE1BQU0sS0FBSyxXQUFXLE9BQU8sR0FBRztBQUN0QyxZQUFNLElBQUksTUFBTSx1QkFBdUIsR0FBRyxFQUFFO0FBQUEsSUFDOUM7QUFBQSxFQUNGO0FBQUE7QUFBQSxFQUlRLGdCQUFnQixRQUE0QjtBQUNsRCxVQUFNLFNBQXFCO0FBQUEsTUFDekIsT0FBTztBQUFBLE1BQUcsTUFBTTtBQUFBLE1BQUcsVUFBVTtBQUFBLE1BQUcsYUFBYTtBQUFBLE1BQUcsb0JBQW9CO0FBQUEsTUFBRyxNQUFNLENBQUM7QUFBQSxJQUNoRjtBQUVBLFVBQU0sYUFBYSxPQUFPLE1BQU0sZ0JBQWdCO0FBQ2hELFVBQU0sWUFBWSxPQUFPLE1BQU0sZUFBZTtBQUM5QyxVQUFNLGdCQUFnQixPQUFPLE1BQU0sbUJBQW1CO0FBQ3RELFVBQU0sY0FBYyxPQUFPLE1BQU0sMkJBQTJCO0FBQzVELFVBQU0sbUJBQW1CLE9BQU8sTUFBTSw4QkFBOEI7QUFFcEUsUUFBSSxXQUFZLFFBQU8sUUFBUSxTQUFTLFdBQVcsQ0FBQyxDQUFDO0FBQ3JELFFBQUksVUFBVyxRQUFPLE9BQU8sU0FBUyxVQUFVLENBQUMsQ0FBQztBQUNsRCxRQUFJLGNBQWUsUUFBTyxXQUFXLFNBQVMsY0FBYyxDQUFDLENBQUM7QUFDOUQsUUFBSSxZQUFhLFFBQU8sY0FBYyxTQUFTLFlBQVksQ0FBQyxDQUFDO0FBQzdELFFBQUksaUJBQWtCLFFBQU8scUJBQXFCLFNBQVMsaUJBQWlCLENBQUMsQ0FBQztBQUc5RSxVQUFNLGNBQWMsT0FBTyxNQUFNLGdEQUFnRDtBQUNqRixRQUFJLGFBQWE7QUFDZixZQUFNLFFBQVEsWUFBWSxDQUFDLEVBQUUsS0FBSyxFQUFFLE1BQU0sSUFBSTtBQUM5QyxpQkFBVyxRQUFRLE9BQU87QUFDeEIsY0FBTSxRQUFRLEtBQUssTUFBTSxtQkFBbUI7QUFDNUMsWUFBSSxPQUFPO0FBQ1QsaUJBQU8sS0FBSyxLQUFLLEVBQUUsVUFBVSxNQUFNLENBQUMsR0FBRyxPQUFPLFNBQVMsTUFBTSxDQUFDLENBQUMsRUFBRSxDQUFDO0FBQUEsUUFDcEU7QUFBQSxNQUNGO0FBQUEsSUFDRjtBQUVBLFdBQU87QUFBQSxFQUNUO0FBQUEsRUFFUSxrQkFBa0IsUUFBOEI7QUFDdEQsVUFBTSxTQUE2RSxDQUFDO0FBRXBGLFVBQU0sUUFBUSxPQUFPLE1BQU0sSUFBSTtBQUMvQixlQUFXLFFBQVEsT0FBTztBQUN4QixZQUFNLFFBQVEsS0FBSyxNQUFNLDJCQUEyQjtBQUNwRCxVQUFJLE9BQU87QUFDVCxjQUFNLE9BQU8sTUFBTSxDQUFDLEVBQUUsS0FBSztBQUMzQixjQUFNLFVBQVUsTUFBTSxDQUFDLEVBQUUsS0FBSztBQUM5QixZQUFJLFNBQVM7QUFDYixZQUFJLEtBQUssU0FBUyxjQUFJLEVBQUcsVUFBUztBQUFBLGlCQUN6QixLQUFLLFNBQVMsV0FBSSxFQUFHLFVBQVM7QUFDdkMsZUFBTyxLQUFLLEVBQUUsTUFBTSxRQUFRLFNBQVMsT0FBTyxFQUFFLENBQUM7QUFBQSxNQUNqRDtBQUFBLElBQ0Y7QUFFQSxVQUFNLGVBQWUsT0FBTyxNQUFNLGtCQUFrQjtBQUNwRCxVQUFNLGVBQWUsT0FBTyxNQUFNLGlCQUFpQjtBQUVuRCxXQUFPO0FBQUEsTUFDTCxRQUFRLGVBQWUsYUFBYSxDQUFDLEVBQUUsWUFBWSxJQUFJO0FBQUEsTUFDdkQsU0FBUyxlQUFlLGFBQWEsQ0FBQyxJQUFJO0FBQUEsTUFDMUM7QUFBQSxJQUNGO0FBQUEsRUFDRjtBQUFBLEVBRVEsa0JBQWtCLFFBQXVCO0FBQy9DLFVBQU0sVUFBaUIsQ0FBQztBQUN4QixVQUFNLFFBQVEsT0FBTyxNQUFNLElBQUk7QUFDL0IsZUFBVyxRQUFRLE9BQU87QUFDeEIsVUFBSSxLQUFLLEtBQUssRUFBRSxXQUFXLE9BQU8sRUFBRztBQUNyQyxVQUFJLEtBQUssS0FBSyxFQUFFLFdBQVcsUUFBRyxFQUFHO0FBQ2pDLFVBQUksS0FBSyxLQUFLLEVBQUUsU0FBUyxFQUFHO0FBRTVCLFlBQU0sUUFBUSxLQUFLLE1BQU0sK0JBQStCO0FBQ3hELFVBQUksT0FBTztBQUNULGdCQUFRLEtBQUs7QUFBQSxVQUNYLE9BQU8sTUFBTSxDQUFDLEVBQUUsS0FBSztBQUFBLFVBQ3JCLE1BQU0sTUFBTSxDQUFDLElBQUksTUFBTSxDQUFDLEVBQUUsTUFBTSxJQUFJLEVBQUUsSUFBSSxDQUFDLE1BQWMsRUFBRSxLQUFLLENBQUMsSUFBSSxDQUFDO0FBQUEsUUFDeEUsQ0FBQztBQUFBLE1BQ0g7QUFBQSxJQUNGO0FBQ0EsV0FBTztBQUFBLEVBQ1Q7QUFBQSxFQUVRLG9CQUFvQixRQUFnQixTQUFpQztBQUUzRSxVQUFNLE9BQU8sS0FBSyxZQUFZLE9BQU87QUFDckMsVUFBTSxZQUFZLEtBQUssaUJBQWlCLE9BQU87QUFFL0MsV0FBTztBQUFBLE1BQ0w7QUFBQSxNQUNBO0FBQUEsTUFDQSxNQUFNO0FBQUEsTUFDTixXQUFXO0FBQUEsTUFDWCxZQUFZO0FBQUEsTUFDWixlQUFlLFVBQVUsSUFBSSxRQUFNLEVBQUUsTUFBTSxjQUFjLFFBQVEsRUFBRSxFQUFFO0FBQUEsSUFDdkU7QUFBQSxFQUNGO0FBQUE7QUFBQSxFQUlRLGlCQUFpQixTQUEyQjtBQUNsRCxVQUFNLFVBQVUsUUFBUSxTQUFTLGlDQUFpQztBQUNsRSxXQUFPLE1BQU0sS0FBSyxPQUFPLEVBQUUsSUFBSSxPQUFLLEVBQUUsQ0FBQyxFQUFFLEtBQUssQ0FBQztBQUFBLEVBQ2pEO0FBQUEsRUFFUSxZQUFZLFNBQTJCO0FBQzdDLFVBQU0sT0FBTyxvQkFBSSxJQUFZO0FBRTdCLFVBQU0sVUFBVSxRQUFRLFNBQVMscUNBQXFDO0FBQ3RFLGVBQVcsU0FBUyxTQUFTO0FBQzNCLFdBQUssSUFBSSxNQUFNLENBQUMsRUFBRSxZQUFZLENBQUM7QUFBQSxJQUNqQztBQUNBLFdBQU8sTUFBTSxLQUFLLElBQUk7QUFBQSxFQUN4QjtBQUNGOzs7QUMxTkEsc0JBQStDO0FBSXhDLElBQU0sb0JBQW9CO0FBRTFCLElBQU0sbUJBQU4sY0FBK0IseUJBQVM7QUFBQSxFQUM3QztBQUFBLEVBQ1EsYUFBZ0M7QUFBQSxFQUNoQyxxQkFBcUU7QUFBQSxFQUNyRSx1QkFBa0Q7QUFBQSxFQUUxRCxZQUFZLE1BQXFCLFFBQXFCO0FBQ3BELFVBQU0sSUFBSTtBQUNWLFNBQUssU0FBUztBQUFBLEVBQ2hCO0FBQUEsRUFFQSxjQUFzQjtBQUFFLFdBQU87QUFBQSxFQUFtQjtBQUFBLEVBQ2xELGlCQUF5QjtBQUFFLFdBQU87QUFBQSxFQUFTO0FBQUEsRUFDM0MsVUFBa0I7QUFBRSxXQUFPO0FBQUEsRUFBVztBQUFBLEVBRXRDLE1BQU0sU0FBUztBQUNiLFNBQUssT0FBTztBQUFBLEVBQ2Q7QUFBQSxFQUVBLE1BQU0sVUFBVTtBQUFBLEVBQUM7QUFBQTtBQUFBLEVBSWpCLGlCQUFpQixRQUFvQjtBQUNuQyxTQUFLLGFBQWE7QUFDbEIsU0FBSyxPQUFPO0FBQUEsRUFDZDtBQUFBLEVBRUEsa0JBQWtCLE1BQWEsUUFBd0I7QUFDckQsU0FBSyxxQkFBcUIsRUFBRSxNQUFNLE9BQU87QUFDekMsU0FBSyxPQUFPO0FBQUEsRUFDZDtBQUFBLEVBRUEsbUJBQW1CLE1BQWdCO0FBQ2pDLFNBQUsscUJBQXFCLElBQUk7QUFBQSxFQUNoQztBQUFBLEVBRUEsa0JBQWtCLE1BQTBCO0FBQzFDLFNBQUssdUJBQXVCO0FBQzVCLFNBQUssT0FBTztBQUFBLEVBQ2Q7QUFBQTtBQUFBLEVBSVEsU0FBUztBQUNmLFVBQU0sWUFBWSxLQUFLO0FBQ3ZCLGNBQVUsTUFBTTtBQUNoQixjQUFVLFNBQVMsZUFBZTtBQUdsQyxVQUFNLFNBQVMsVUFBVSxVQUFVLEVBQUUsS0FBSyxlQUFlLENBQUM7QUFDMUQsV0FBTyxTQUFTLFFBQVEsRUFBRSxNQUFNLFNBQVMsS0FBSyxhQUFhLENBQUM7QUFDNUQsV0FBTyxTQUFTLFFBQVEsRUFBRSxNQUFNLHFCQUFxQixLQUFLLGdCQUFnQixDQUFDO0FBRzNFLFFBQUksS0FBSyxZQUFZO0FBQ25CLFdBQUssWUFBWSxTQUFTO0FBQUEsSUFDNUI7QUFHQSxRQUFJLEtBQUssb0JBQW9CO0FBQzNCLFdBQUssa0JBQWtCLFNBQVM7QUFBQSxJQUNsQztBQUdBLFFBQUksS0FBSyxzQkFBc0I7QUFDN0IsV0FBSyxvQkFBb0IsU0FBUztBQUFBLElBQ3BDO0FBR0EsU0FBSyxjQUFjLFNBQVM7QUFBQSxFQUM5QjtBQUFBLEVBRVEsWUFBWSxXQUF3QjtBQUMxQyxVQUFNLElBQUksS0FBSztBQUNmLFVBQU0sUUFBUSxVQUFVLFVBQVUsRUFBRSxLQUFLLGNBQWMsQ0FBQztBQUV4RCxVQUFNLFFBQVE7QUFBQSxNQUNaLEVBQUUsT0FBTyxTQUFTLE9BQU8sRUFBRSxPQUFPLE1BQU0sWUFBSztBQUFBLE1BQzdDLEVBQUUsT0FBTyxRQUFRLE9BQU8sRUFBRSxNQUFNLE1BQU0sa0JBQU07QUFBQSxNQUM1QyxFQUFFLE9BQU8sWUFBWSxPQUFPLEVBQUUsVUFBVSxNQUFNLFlBQUs7QUFBQSxNQUNuRCxFQUFFLE9BQU8sVUFBVSxPQUFPLEVBQUUsYUFBYSxNQUFNLFlBQUs7QUFBQSxJQUN0RDtBQUVBLGVBQVcsUUFBUSxPQUFPO0FBQ3hCLFlBQU0sS0FBSyxNQUFNLFVBQVUsRUFBRSxLQUFLLGtCQUFrQixDQUFDO0FBQ3JELFNBQUcsU0FBUyxRQUFRLEVBQUUsTUFBTSxLQUFLLE1BQU0sS0FBSyxrQkFBa0IsQ0FBQztBQUMvRCxTQUFHLFNBQVMsUUFBUSxFQUFFLE1BQU0sT0FBTyxLQUFLLEtBQUssR0FBRyxLQUFLLG1CQUFtQixDQUFDO0FBQ3pFLFNBQUcsU0FBUyxRQUFRLEVBQUUsTUFBTSxLQUFLLE9BQU8sS0FBSyxtQkFBbUIsQ0FBQztBQUFBLElBQ25FO0FBR0EsUUFBSSxFQUFFLEtBQUssU0FBUyxHQUFHO0FBQ3JCLFlBQU0sT0FBTyxVQUFVLFVBQVUsRUFBRSxLQUFLLGFBQWEsQ0FBQztBQUN0RCxXQUFLLFNBQVMsT0FBTyxFQUFFLE1BQU0sa0JBQWtCLEtBQUssc0JBQXNCLENBQUM7QUFDM0UsaUJBQVcsS0FBSyxFQUFFLEtBQUssTUFBTSxHQUFHLENBQUMsR0FBRztBQUNsQyxjQUFNLE1BQU0sS0FBSyxVQUFVLEVBQUUsS0FBSyxpQkFBaUIsQ0FBQztBQUNwRCxZQUFJLFNBQVMsUUFBUSxFQUFFLE1BQU0sRUFBRSxVQUFVLEtBQUssaUJBQWlCLENBQUM7QUFDaEUsWUFBSSxTQUFTLFFBQVEsRUFBRSxNQUFNLE9BQU8sRUFBRSxLQUFLLEdBQUcsS0FBSyxtQkFBbUIsQ0FBQztBQUFBLE1BQ3pFO0FBQUEsSUFDRjtBQUFBLEVBQ0Y7QUFBQSxFQUVRLGtCQUFrQixXQUF3QjtBQUNoRCxVQUFNLElBQUksS0FBSztBQUNmLFVBQU0sVUFBVSxVQUFVLFVBQVUsRUFBRSxLQUFLLG9CQUFvQixDQUFDO0FBQ2hFLFlBQVEsU0FBUyxPQUFPLEVBQUUsTUFBTSxrQkFBa0IsS0FBSyxzQkFBc0IsQ0FBQztBQUU5RSxlQUFXLE9BQU8sRUFBRSxPQUFPLE1BQU07QUFDL0IsWUFBTSxPQUFPLFFBQVEsVUFBVSxFQUFFLEtBQUssaUJBQWlCLENBQUM7QUFDeEQsV0FBSyxTQUFTLFFBQVEsRUFBRSxNQUFNLEtBQUssS0FBSyxpQkFBaUIsQ0FBQztBQUMxRCxXQUFLLFNBQVMsUUFBUSxFQUFFLE1BQU0sSUFBSSxDQUFDO0FBQ25DLFdBQUssYUFBYSxNQUFNO0FBQ3RCLGFBQUssU0FBUyxFQUFFLE1BQU0sR0FBRztBQUN6QixhQUFLLFNBQVMsbUJBQW1CO0FBQUEsTUFDbkMsQ0FBQztBQUFBLElBQ0g7QUFFQSxRQUFJLEVBQUUsT0FBTyxVQUFVLFNBQVMsR0FBRztBQUNqQyxjQUFRLFNBQVMsT0FBTyxFQUFFLE1BQU0sYUFBYSxLQUFLLHNCQUFzQixDQUFDO0FBQ3pFLGlCQUFXLFFBQVEsRUFBRSxPQUFPLFdBQVc7QUFDckMsY0FBTSxLQUFLLFFBQVEsVUFBVSxFQUFFLEtBQUssaUJBQWlCLENBQUM7QUFDdEQsV0FBRyxTQUFTLFFBQVEsRUFBRSxNQUFNLE1BQU0sS0FBSyxxQkFBcUIsQ0FBQztBQUM3RCxXQUFHLFNBQVMsUUFBUSxFQUFFLE1BQU0sS0FBSyxDQUFDO0FBQ2xDLFdBQUcsU0FBUyxRQUFRLEVBQUUsTUFBTSxNQUFNLEtBQUsscUJBQXFCLENBQUM7QUFBQSxNQUMvRDtBQUFBLElBQ0Y7QUFBQSxFQUNGO0FBQUEsRUFFUSxvQkFBb0IsV0FBd0I7QUFDbEQsVUFBTSxPQUFPLEtBQUs7QUFDbEIsVUFBTSxVQUFVLFVBQVUsVUFBVSxFQUFFLEtBQUssc0JBQXNCLENBQUM7QUFDbEUsWUFBUSxTQUFTLE9BQU8sRUFBRSxNQUFNLGlCQUFpQixLQUFLLHNCQUFzQixDQUFDO0FBRTdFLGVBQVcsT0FBTyxLQUFLLGVBQWU7QUFDcEMsWUFBTSxLQUFLLFFBQVEsVUFBVSxFQUFFLEtBQUssZ0JBQWdCLENBQUM7QUFDckQsU0FBRyxTQUFTLFFBQVEsRUFBRSxNQUFNLElBQUksTUFBTSxLQUFLLGlCQUFpQixDQUFDO0FBQzdELFNBQUcsU0FBUyxRQUFRLEVBQUUsTUFBTSxVQUFLLEtBQUssa0JBQWtCLENBQUM7QUFDekQsU0FBRyxTQUFTLFFBQVEsRUFBRSxNQUFNLElBQUksUUFBUSxLQUFLLG1CQUFtQixDQUFDO0FBQUEsSUFDbkU7QUFBQSxFQUNGO0FBQUEsRUFFUSxxQkFBcUIsTUFBZ0I7QUFDM0MsVUFBTSxZQUFZLEtBQUs7QUFDdkIsY0FBVSxNQUFNO0FBQ2hCLGNBQVUsU0FBUyxlQUFlO0FBRWxDLGNBQVUsU0FBUyxPQUFPLEVBQUUsTUFBTSxrQkFBa0IsS0FBSyxzQkFBc0IsQ0FBQztBQUNoRixlQUFXLE9BQU8sTUFBTTtBQUN0QixZQUFNLE9BQU8sVUFBVSxVQUFVLEVBQUUsS0FBSyxpQkFBaUIsQ0FBQztBQUMxRCxXQUFLLFNBQVMsUUFBUSxFQUFFLE1BQU0sS0FBSyxLQUFLLGlCQUFpQixDQUFDO0FBQzFELFdBQUssU0FBUyxRQUFRLEVBQUUsTUFBTSxJQUFJLENBQUM7QUFBQSxJQUNyQztBQUFBLEVBQ0Y7QUFBQSxFQUVRLGNBQWMsV0FBd0I7QUFDNUMsVUFBTSxVQUFVLFVBQVUsVUFBVSxFQUFFLEtBQUssZ0JBQWdCLENBQUM7QUFFNUQsVUFBTSxVQUFVLFFBQVEsU0FBUyxVQUFVLEVBQUUsTUFBTSxjQUFjLEtBQUssWUFBWSxDQUFDO0FBQ25GLFlBQVEsYUFBYSxNQUFNLEtBQUssT0FBTyxVQUFVLENBQUM7QUFFbEQsVUFBTSxZQUFZLFFBQVEsU0FBUyxVQUFVLEVBQUUsTUFBTSxVQUFVLEtBQUssWUFBWSxDQUFDO0FBQ2pGLGNBQVUsYUFBYSxNQUFNLEtBQUssT0FBTyxXQUFXLENBQUM7QUFBQSxFQUN2RDtBQUFBLEVBRUEsTUFBYyxTQUFTLE1BQWEsS0FBYTtBQUMvQyxVQUFNLFVBQVUsTUFBTSxLQUFLLElBQUksTUFBTSxLQUFLLElBQUk7QUFFOUMsUUFBSSxRQUFRLFlBQVksRUFBRSxTQUFTLElBQUksSUFBSSxZQUFZLENBQUMsRUFBRSxFQUFHO0FBRzdELFFBQUksUUFBUSxXQUFXLEtBQUssR0FBRztBQUM3QixZQUFNLE1BQU0sUUFBUSxRQUFRLFNBQVMsQ0FBQztBQUN0QyxVQUFJLE1BQU0sR0FBRztBQUNYLGNBQU0sVUFBVSxRQUFRLFVBQVUsR0FBRyxHQUFHLElBQUk7QUFBQSxNQUFjLEdBQUc7QUFBQSxJQUFPLFFBQVEsVUFBVSxHQUFHO0FBQ3pGLGNBQU0sS0FBSyxJQUFJLE1BQU0sT0FBTyxNQUFNLE9BQU87QUFDekM7QUFBQSxNQUNGO0FBQUEsSUFDRjtBQUNBLFVBQU0sS0FBSyxJQUFJLE1BQU0sT0FBTyxNQUFNLFVBQVU7QUFBQTtBQUFBLEdBQVEsR0FBRyxFQUFFO0FBQUEsRUFDM0Q7QUFDRjs7O0FDM0xBLElBQUFDLG1CQUF3QztBQUlqQyxJQUFNLG1CQUFtQjtBQUV6QixJQUFNLGtCQUFOLGNBQThCLDBCQUFTO0FBQUEsRUFDNUM7QUFBQSxFQUVBLFlBQVksTUFBcUIsUUFBcUI7QUFDcEQsVUFBTSxJQUFJO0FBQ1YsU0FBSyxTQUFTO0FBQUEsRUFDaEI7QUFBQSxFQUVBLGNBQXNCO0FBQUUsV0FBTztBQUFBLEVBQWtCO0FBQUEsRUFDakQsaUJBQXlCO0FBQUUsV0FBTztBQUFBLEVBQWdCO0FBQUEsRUFDbEQsVUFBa0I7QUFBRSxXQUFPO0FBQUEsRUFBZTtBQUFBLEVBRTFDLE1BQU0sU0FBUztBQUNiLFNBQUssT0FBTztBQUFBLEVBQ2Q7QUFBQSxFQUVBLE1BQU0sVUFBVTtBQUFBLEVBQUM7QUFBQSxFQUVqQixnQkFBZ0IsUUFBc0I7QUFDcEMsU0FBSyxPQUFPLE1BQU07QUFBQSxFQUNwQjtBQUFBLEVBRVEsT0FBTyxRQUF1QjtBQUNwQyxVQUFNLFlBQVksS0FBSztBQUN2QixjQUFVLE1BQU07QUFDaEIsY0FBVSxTQUFTLGNBQWM7QUFFakMsUUFBSSxDQUFDLFFBQVE7QUFDWCxnQkFBVSxTQUFTLEtBQUssRUFBRSxNQUFNLHFDQUFxQyxDQUFDO0FBQ3RFLFlBQU0sTUFBTSxVQUFVLFNBQVMsVUFBVSxFQUFFLE1BQU0sb0JBQW9CLEtBQUssWUFBWSxDQUFDO0FBQ3ZGLFVBQUksYUFBYSxNQUFNLEtBQUssT0FBTyxXQUFXLENBQUM7QUFDL0M7QUFBQSxJQUNGO0FBR0EsVUFBTSxTQUFTLFVBQVUsVUFBVSxFQUFFLEtBQUssb0NBQW9DLE9BQU8sTUFBTSxHQUFHLENBQUM7QUFDL0YsV0FBTyxTQUFTLFFBQVEsRUFBRSxNQUFNLE9BQU8sT0FBTyxZQUFZLEdBQUcsS0FBSyxzQkFBc0IsQ0FBQztBQUN6RixXQUFPLFNBQVMsUUFBUSxFQUFFLE1BQU0sT0FBTyxTQUFTLEtBQUssdUJBQXVCLENBQUM7QUFHN0UsZUFBVyxTQUFTLE9BQU8sUUFBUTtBQUNqQyxZQUFNLE1BQU0sVUFBVSxVQUFVLEVBQUUsS0FBSywrQkFBK0IsTUFBTSxNQUFNLEdBQUcsQ0FBQztBQUN0RixZQUFNLE9BQU8sTUFBTSxXQUFXLFlBQVksV0FBTSxNQUFNLFdBQVcsWUFBWSxpQkFBTztBQUNwRixVQUFJLFNBQVMsUUFBUSxFQUFFLE1BQU0sTUFBTSxLQUFLLG1CQUFtQixDQUFDO0FBRTVELFlBQU0sT0FBTyxJQUFJLFVBQVUsRUFBRSxLQUFLLG1CQUFtQixDQUFDO0FBQ3RELFdBQUssU0FBUyxPQUFPLEVBQUUsTUFBTSxNQUFNLE1BQU0sS0FBSyxtQkFBbUIsQ0FBQztBQUNsRSxXQUFLLFNBQVMsT0FBTyxFQUFFLE1BQU0sTUFBTSxTQUFTLEtBQUssc0JBQXNCLENBQUM7QUFFeEUsWUFBTSxRQUFRLElBQUksU0FBUyxRQUFRLEVBQUUsTUFBTSxNQUFNLE9BQU8sWUFBWSxHQUFHLEtBQUssaUNBQWlDLE1BQU0sTUFBTSxHQUFHLENBQUM7QUFBQSxJQUMvSDtBQUFBLEVBQ0Y7QUFDRjs7O0FIMUNBLElBQU0sbUJBQWtDO0FBQUEsRUFDdEMsWUFBWTtBQUFBO0FBQUEsRUFDWixTQUFTO0FBQUEsRUFDVCxVQUFVO0FBQUEsRUFDVixxQkFBcUI7QUFBQSxFQUNyQixpQkFBaUI7QUFBQTtBQUFBLEVBQ2pCLG9CQUFvQjtBQUN0QjtBQUlBLElBQXFCLGNBQXJCLGNBQXlDLHdCQUFPO0FBQUEsRUFDOUMsV0FBMEI7QUFBQSxFQUMxQjtBQUFBLEVBQ1EsZUFBOEI7QUFBQSxFQUV0QyxNQUFNLFNBQVM7QUFDYixRQUFJO0FBQ0YsWUFBTSxLQUFLLGlCQUFpQjtBQUFBLElBQzlCLFNBQVMsS0FBSztBQUNaLFlBQU0sTUFBTSxlQUFlLFFBQVEsSUFBSSxVQUFVLE9BQU8sR0FBRztBQUMzRCxVQUFJLHdCQUFPLDJCQUEyQixHQUFHLElBQUksR0FBSTtBQUNqRCxjQUFRLE1BQU0sdUJBQXVCLEdBQUc7QUFBQSxJQUMxQztBQUFBLEVBQ0Y7QUFBQSxFQUVBLE1BQWMsbUJBQW1CO0FBQy9CLFVBQU0sS0FBSyxhQUFhO0FBR3hCLFNBQUssU0FBUyxJQUFJLFlBQVksS0FBSyxTQUFTLGNBQWMsTUFBTSxLQUFLLGFBQWEsQ0FBQztBQUduRixTQUFLLGFBQWEsbUJBQW1CLENBQUMsU0FBUyxJQUFJLGlCQUFpQixNQUFNLElBQUksQ0FBQztBQUMvRSxTQUFLLGFBQWEsa0JBQWtCLENBQUMsU0FBUyxJQUFJLGdCQUFnQixNQUFNLElBQUksQ0FBQztBQUc3RSxTQUFLLGNBQWMsV0FBVyxTQUFTLE1BQU07QUFDM0MsV0FBSyxnQkFBZ0I7QUFBQSxJQUN2QixDQUFDO0FBR0QsU0FBSyxXQUFXO0FBQUEsTUFDZCxJQUFJO0FBQUEsTUFDSixNQUFNO0FBQUEsTUFDTixVQUFVLE1BQU0sS0FBSyxVQUFVO0FBQUEsSUFDakMsQ0FBQztBQUVELFNBQUssV0FBVztBQUFBLE1BQ2QsSUFBSTtBQUFBLE1BQ0osTUFBTTtBQUFBLE1BQ04sVUFBVSxNQUFNLEtBQUssbUJBQW1CO0FBQUEsSUFDMUMsQ0FBQztBQUVELFNBQUssV0FBVztBQUFBLE1BQ2QsSUFBSTtBQUFBLE1BQ0osTUFBTTtBQUFBLE1BQ04sVUFBVSxNQUFNLEtBQUssV0FBVztBQUFBLElBQ2xDLENBQUM7QUFFRCxTQUFLLFdBQVc7QUFBQSxNQUNkLElBQUk7QUFBQSxNQUNKLE1BQU07QUFBQSxNQUNOLFVBQVUsTUFBTSxLQUFLLFlBQVk7QUFBQSxJQUNuQyxDQUFDO0FBRUQsU0FBSyxXQUFXO0FBQUEsTUFDZCxJQUFJO0FBQUEsTUFDSixNQUFNO0FBQUEsTUFDTixVQUFVLE1BQU0sS0FBSyxrQkFBa0I7QUFBQSxJQUN6QyxDQUFDO0FBR0QsU0FBSyxjQUFjLElBQUksZ0JBQWdCLEtBQUssS0FBSyxJQUFJLENBQUM7QUFHdEQsU0FBSztBQUFBLE1BQ0gsS0FBSyxJQUFJLE1BQU0sR0FBRyxVQUFVLENBQUMsU0FBUztBQUNwQyxZQUFJLGdCQUFnQiwwQkFBUyxLQUFLLGNBQWMsUUFBUSxLQUFLLFNBQVMsU0FBUztBQUM3RSxlQUFLLFlBQVksSUFBSTtBQUFBLFFBQ3ZCO0FBQUEsTUFDRixDQUFDO0FBQUEsSUFDSDtBQUdBLFNBQUssa0JBQWtCO0FBRXZCLFlBQVEsSUFBSSxxQkFBcUI7QUFBQSxFQUNuQztBQUFBLEVBRUEsV0FBVztBQUNULFFBQUksS0FBSyxjQUFjO0FBQ3JCLGFBQU8sY0FBYyxLQUFLLFlBQVk7QUFBQSxJQUN4QztBQUFBLEVBQ0Y7QUFBQTtBQUFBLEVBSUEsTUFBYyxlQUFnQztBQUU1QyxVQUFNLGFBQWE7QUFBQSxNQUNqQjtBQUFBLE1BQ0E7QUFBQSxNQUNBLEdBQUcsUUFBUSxJQUFJLElBQUk7QUFBQSxJQUNyQjtBQUVBLFFBQUksZUFBb0I7QUFDeEIsUUFBSTtBQUFFLHFCQUFlLFFBQVEsZUFBZSxFQUFFO0FBQUEsSUFBYyxRQUFRO0FBQUEsSUFBQztBQUNyRSxlQUFXLFFBQVEsWUFBWTtBQUM3QixVQUFJO0FBQ0YscUJBQWEsTUFBTSxDQUFDLFdBQVcsR0FBRyxFQUFFLE9BQU8sU0FBUyxDQUFDO0FBQ3JELGVBQU87QUFBQSxNQUNULFFBQVE7QUFDTjtBQUFBLE1BQ0Y7QUFBQSxJQUNGO0FBRUEsUUFBSSx3QkFBTyxpREFBaUQsR0FBSTtBQUNoRSxXQUFPO0FBQUEsRUFDVDtBQUFBO0FBQUEsRUFJQSxNQUFNLFlBQVk7QUFDaEIsUUFBSSx3QkFBTywwQkFBMEI7QUFDckMsUUFBSTtBQUNGLFlBQU0sU0FBUyxNQUFNLEtBQUssT0FBTyxLQUFLLEtBQUssSUFBSSxNQUFNLFFBQVEsWUFBWSxDQUFDO0FBQzFFLFVBQUksd0JBQU8sVUFBVSxPQUFPLEtBQUssV0FBVyxPQUFPLElBQUksVUFBVSxPQUFPLFFBQVEsV0FBVztBQUczRixZQUFNLFVBQVUsS0FBSyxXQUFXO0FBQ2hDLFVBQUksUUFBUyxTQUFRLGlCQUFpQixNQUFNO0FBQUEsSUFDOUMsU0FBUyxLQUFLO0FBQ1osVUFBSSx3QkFBTyw2QkFBd0IsSUFBSSxPQUFPLEVBQUU7QUFBQSxJQUNsRDtBQUFBLEVBQ0Y7QUFBQSxFQUVBLE1BQU0scUJBQXFCO0FBQ3pCLFVBQU0sT0FBTyxLQUFLLElBQUksVUFBVSxjQUFjO0FBQzlDLFFBQUksQ0FBQyxRQUFRLEtBQUssY0FBYyxNQUFNO0FBQ3BDLFVBQUksd0JBQU8sbUNBQW1DO0FBQzlDO0FBQUEsSUFDRjtBQUNBLFVBQU0sS0FBSyxZQUFZLElBQUk7QUFBQSxFQUM3QjtBQUFBLEVBRUEsTUFBYyxZQUFZLE1BQWE7QUFDckMsUUFBSTtBQUNGLFlBQU0sVUFBVSxNQUFNLEtBQUssSUFBSSxNQUFNLEtBQUssSUFBSTtBQUM5QyxZQUFNLGNBQWMsTUFBTSxLQUFLLE9BQU8sU0FBUyxLQUFLLE1BQU0sT0FBTztBQUVqRSxVQUFJLFlBQVksS0FBSyxTQUFTLEtBQUssS0FBSyxTQUFTLFNBQVM7QUFDeEQsY0FBTSxVQUFVLEtBQUssVUFBVSxTQUFTLFlBQVksSUFBSTtBQUN4RCxZQUFJLFlBQVksU0FBUztBQUN2QixnQkFBTSxLQUFLLElBQUksTUFBTSxPQUFPLE1BQU0sT0FBTztBQUFBLFFBQzNDO0FBQUEsTUFDRjtBQUdBLFlBQU0sVUFBVSxLQUFLLFdBQVc7QUFDaEMsVUFBSSxRQUFTLFNBQVEsa0JBQWtCLE1BQU0sV0FBVztBQUFBLElBQzFELFNBQVMsS0FBSztBQUVaLGNBQVEsS0FBSywwQkFBMEIsR0FBRztBQUFBLElBQzVDO0FBQUEsRUFDRjtBQUFBLEVBRUEsTUFBTSxjQUFjO0FBQ2xCLFVBQU0sT0FBTyxLQUFLLElBQUksVUFBVSxjQUFjO0FBQzlDLFFBQUksQ0FBQyxLQUFNO0FBRVgsVUFBTSxVQUFVLE1BQU0sS0FBSyxJQUFJLE1BQU0sS0FBSyxJQUFJO0FBQzlDLFVBQU0sY0FBYyxNQUFNLEtBQUssT0FBTyxTQUFTLEtBQUssTUFBTSxPQUFPO0FBRWpFLFVBQU0sVUFBVSxNQUFNLEtBQUssZ0JBQWdCO0FBQzNDLFlBQVEsbUJBQW1CLFlBQVksSUFBSTtBQUFBLEVBQzdDO0FBQUEsRUFFQSxNQUFNLG9CQUFvQjtBQUN4QixVQUFNLE9BQU8sS0FBSyxJQUFJLFVBQVUsY0FBYztBQUM5QyxRQUFJLENBQUMsS0FBTTtBQUVYLFVBQU0sVUFBVSxNQUFNLEtBQUssSUFBSSxNQUFNLEtBQUssSUFBSTtBQUM5QyxVQUFNLE9BQU8sTUFBTSxLQUFLLE9BQU8sa0JBQWtCLEtBQUssVUFBVSxPQUFPO0FBRXZFLFVBQU0sVUFBVSxNQUFNLEtBQUssZ0JBQWdCO0FBQzNDLFlBQVEsa0JBQWtCLElBQUk7QUFBQSxFQUNoQztBQUFBLEVBRUEsTUFBTSxhQUFhO0FBQ2pCLFVBQU0sU0FBUyxNQUFNLEtBQUssT0FBTyxPQUFPLEtBQUssSUFBSSxNQUFNLFFBQVEsWUFBWSxDQUFDO0FBQzVFLFVBQU0sT0FBTyxLQUFLLElBQUksVUFBVSxhQUFhLEtBQUs7QUFDbEQsUUFBSSxNQUFNO0FBQ1IsWUFBTSxLQUFLLGFBQWEsRUFBRSxNQUFNLGtCQUFrQixPQUFPLE9BQU8sQ0FBQztBQUNqRSxXQUFLLElBQUksVUFBVSxXQUFXLElBQUk7QUFBQSxJQUNwQztBQUFBLEVBQ0Y7QUFBQTtBQUFBLEVBSVEsVUFBVSxTQUFpQixNQUF3QjtBQUV6RCxRQUFJLFFBQVEsV0FBVyxLQUFLLEdBQUc7QUFDN0IsWUFBTSxNQUFNLFFBQVEsUUFBUSxTQUFTLENBQUM7QUFDdEMsVUFBSSxNQUFNLEdBQUc7QUFDWCxjQUFNLGNBQWMsUUFBUSxVQUFVLEdBQUcsR0FBRztBQUM1QyxjQUFNLFVBQVUsWUFBWSxTQUFTLE9BQU87QUFDNUMsWUFBSSxTQUFTO0FBRVgsZ0JBQU0sU0FBUyxZQUFZLFFBQVEsTUFBTSxZQUFZLFFBQVEsT0FBTyxDQUFDO0FBQ3JFLGdCQUFNLFVBQVUsS0FBSyxJQUFJLE9BQUssT0FBTyxDQUFDLEVBQUUsRUFBRSxLQUFLLElBQUk7QUFDbkQsaUJBQU8sUUFBUSxVQUFVLEdBQUcsU0FBUyxDQUFDLElBQUksVUFBVSxRQUFRLFVBQVUsTUFBTTtBQUFBLFFBQzlFLE9BQU87QUFFTCxnQkFBTSxZQUFZO0FBQUEsRUFBVSxLQUFLLElBQUksT0FBSyxPQUFPLENBQUMsRUFBRSxFQUFFLEtBQUssSUFBSSxDQUFDO0FBQUE7QUFDaEUsaUJBQU8sUUFBUSxVQUFVLEdBQUcsR0FBRyxJQUFJLFlBQVksUUFBUSxVQUFVLEdBQUc7QUFBQSxRQUN0RTtBQUFBLE1BQ0Y7QUFBQSxJQUNGO0FBRUEsVUFBTSxZQUFZLEtBQUssSUFBSSxPQUFLLElBQUksQ0FBQyxFQUFFLEVBQUUsS0FBSyxHQUFHO0FBQ2pELFdBQU8sVUFBVSxTQUFTO0FBQUEsRUFDNUI7QUFBQSxFQUVRLG9CQUFvQjtBQUMxQixRQUFJLEtBQUssYUFBYyxRQUFPLGNBQWMsS0FBSyxZQUFZO0FBQzdELFNBQUssZUFBZSxPQUFPLFlBQVksTUFBTTtBQUMzQyxXQUFLLFVBQVU7QUFBQSxJQUNqQixHQUFHLEtBQUssU0FBUyxrQkFBa0IsR0FBSTtBQUFBLEVBQ3pDO0FBQUE7QUFBQSxFQUlRLGFBQXNDO0FBQzVDLFVBQU0sU0FBUyxLQUFLLElBQUksVUFBVSxnQkFBZ0IsaUJBQWlCO0FBQ25FLFdBQU8sT0FBTyxTQUFTLElBQUksT0FBTyxDQUFDLEVBQUUsT0FBMkI7QUFBQSxFQUNsRTtBQUFBLEVBRUEsTUFBYyxrQkFBNkM7QUFDekQsVUFBTSxXQUFXLEtBQUssV0FBVztBQUNqQyxRQUFJLFNBQVUsUUFBTztBQUVyQixVQUFNLE9BQU8sS0FBSyxJQUFJLFVBQVUsYUFBYSxLQUFLO0FBQ2xELFFBQUksQ0FBQyxLQUFNLE9BQU0sSUFBSSxNQUFNLDJCQUEyQjtBQUN0RCxVQUFNLEtBQUssYUFBYSxFQUFFLE1BQU0sa0JBQWtCLENBQUM7QUFDbkQsU0FBSyxJQUFJLFVBQVUsV0FBVyxJQUFJO0FBQ2xDLFdBQU8sS0FBSztBQUFBLEVBQ2Q7QUFBQSxFQUVBLE1BQU0sZUFBZTtBQUNuQixTQUFLLFdBQVcsT0FBTyxPQUFPLENBQUMsR0FBRyxrQkFBa0IsTUFBTSxLQUFLLFNBQVMsQ0FBQztBQUFBLEVBQzNFO0FBQUEsRUFFQSxNQUFNLGVBQWU7QUFDbkIsVUFBTSxLQUFLLFNBQVMsS0FBSyxRQUFRO0FBQ2pDLFNBQUssT0FBTyxhQUFhLEtBQUssU0FBUyxVQUFVO0FBQ2pELFNBQUssa0JBQWtCO0FBQUEsRUFDekI7QUFDRjtBQUlBLElBQU0sa0JBQU4sY0FBOEIsa0NBQWlCO0FBQUEsRUFDN0M7QUFBQSxFQUVBLFlBQVksS0FBVSxRQUFxQjtBQUN6QyxVQUFNLEtBQUssTUFBTTtBQUNqQixTQUFLLFNBQVM7QUFBQSxFQUNoQjtBQUFBLEVBRUEsVUFBZ0I7QUFDZCxVQUFNLEVBQUUsWUFBWSxJQUFJO0FBQ3hCLGdCQUFZLE1BQU07QUFFbEIsZ0JBQVksU0FBUyxNQUFNLEVBQUUsTUFBTSxpQkFBaUIsQ0FBQztBQUVyRCxRQUFJLHlCQUFRLFdBQVcsRUFDcEIsUUFBUSxhQUFhLEVBQ3JCLFFBQVEsOEJBQThCLEVBQ3RDLFFBQVEsVUFBUSxLQUNkLGVBQWUsYUFBYSxFQUM1QixTQUFTLEtBQUssT0FBTyxTQUFTLFVBQVUsRUFDeEMsU0FBUyxPQUFPLFVBQVU7QUFDekIsV0FBSyxPQUFPLFNBQVMsYUFBYTtBQUNsQyxZQUFNLEtBQUssT0FBTyxhQUFhO0FBQUEsSUFDakMsQ0FBQyxDQUFDO0FBRU4sUUFBSSx5QkFBUSxXQUFXLEVBQ3BCLFFBQVEsVUFBVSxFQUNsQixRQUFRLDBEQUEwRCxFQUNsRSxVQUFVLFlBQVUsT0FDbEIsU0FBUyxLQUFLLE9BQU8sU0FBUyxPQUFPLEVBQ3JDLFNBQVMsT0FBTyxVQUFVO0FBQ3pCLFdBQUssT0FBTyxTQUFTLFVBQVU7QUFDL0IsWUFBTSxLQUFLLE9BQU8sYUFBYTtBQUFBLElBQ2pDLENBQUMsQ0FBQztBQUVOLFFBQUkseUJBQVEsV0FBVyxFQUNwQixRQUFRLFdBQVcsRUFDbkIsUUFBUSx1REFBdUQsRUFDL0QsVUFBVSxZQUFVLE9BQ2xCLFNBQVMsS0FBSyxPQUFPLFNBQVMsUUFBUSxFQUN0QyxTQUFTLE9BQU8sVUFBVTtBQUN6QixXQUFLLE9BQU8sU0FBUyxXQUFXO0FBQ2hDLFlBQU0sS0FBSyxPQUFPLGFBQWE7QUFBQSxJQUNqQyxDQUFDLENBQUM7QUFFTixRQUFJLHlCQUFRLFdBQVcsRUFDcEIsUUFBUSxzQkFBc0IsRUFDOUIsUUFBUSwyREFBc0QsRUFDOUQsVUFBVSxZQUFVLE9BQ2xCLFVBQVUsR0FBRyxHQUFHLElBQUksRUFDcEIsU0FBUyxLQUFLLE9BQU8sU0FBUyxtQkFBbUIsRUFDakQsa0JBQWtCLEVBQ2xCLFNBQVMsT0FBTyxVQUFVO0FBQ3pCLFdBQUssT0FBTyxTQUFTLHNCQUFzQjtBQUMzQyxZQUFNLEtBQUssT0FBTyxhQUFhO0FBQUEsSUFDakMsQ0FBQyxDQUFDO0FBRU4sUUFBSSx5QkFBUSxXQUFXLEVBQ3BCLFFBQVEsa0JBQWtCLEVBQzFCLFFBQVEsdUNBQXVDLEVBQy9DLFFBQVEsVUFBUSxLQUNkLFNBQVMsT0FBTyxLQUFLLE9BQU8sU0FBUyxlQUFlLENBQUMsRUFDckQsU0FBUyxPQUFPLFVBQVU7QUFDekIsWUFBTSxNQUFNLFNBQVMsS0FBSztBQUMxQixVQUFJLENBQUMsTUFBTSxHQUFHLEtBQUssTUFBTSxHQUFHO0FBQzFCLGFBQUssT0FBTyxTQUFTLGtCQUFrQjtBQUN2QyxjQUFNLEtBQUssT0FBTyxhQUFhO0FBQUEsTUFDakM7QUFBQSxJQUNGLENBQUMsQ0FBQztBQUFBLEVBQ1I7QUFDRjsiLAogICJuYW1lcyI6IFsiaW1wb3J0X29ic2lkaWFuIiwgImltcG9ydF9vYnNpZGlhbiJdCn0K
