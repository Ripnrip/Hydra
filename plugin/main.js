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
    try {
      const { stdout } = await execFileAsync(this.binaryPath, args, {
        maxBuffer: 10 * 1024 * 1024,
        timeout: 3e4
      });
      return stdout;
    } catch (err) {
      throw new Error(`Hydra binary error: ${err.message}`);
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
//# sourceMappingURL=data:application/json;base64,ewogICJ2ZXJzaW9uIjogMywKICAic291cmNlcyI6IFsic3JjL21haW4udHMiLCAic3JjL2JyaWRnZS50cyIsICJzcmMvc2lkZWJhci50cyIsICJzcmMvaGVhbHRoLXdpZGdldC50cyJdLAogICJzb3VyY2VzQ29udGVudCI6IFsiaW1wb3J0IHsgUGx1Z2luLCBXb3Jrc3BhY2VMZWFmLCBURmlsZSwgTm90aWNlLCBTZXR0aW5nLCBQbHVnaW5TZXR0aW5nVGFiLCBBcHAgfSBmcm9tICdvYnNpZGlhbic7XG5pbXBvcnQgeyBIeWRyYUJyaWRnZSB9IGZyb20gJy4vYnJpZGdlJztcbmltcG9ydCB7IEh5ZHJhU2lkZWJhclZpZXcsIFNJREVCQVJfVklFV19UWVBFIH0gZnJvbSAnLi9zaWRlYmFyJztcbmltcG9ydCB7IEh5ZHJhSGVhbHRoVmlldywgSEVBTFRIX1ZJRVdfVFlQRSB9IGZyb20gJy4vaGVhbHRoLXdpZGdldCc7XG5cbi8vIE1BUks6IC0gU2V0dGluZ3NcblxuaW50ZXJmYWNlIEh5ZHJhU2V0dGluZ3Mge1xuICBiaW5hcnlQYXRoOiBzdHJpbmc7XG4gIGF1dG9UYWc6IGJvb2xlYW47XG4gIGF1dG9MaW5rOiBib29sZWFuO1xuICBjb25maWRlbmNlVGhyZXNob2xkOiBudW1iZXI7XG4gIHJlZnJlc2hJbnRlcnZhbDogbnVtYmVyO1xuICBlbmFibGVHcmFwaE92ZXJsYXk6IGJvb2xlYW47XG59XG5cbmNvbnN0IERFRkFVTFRfU0VUVElOR1M6IEh5ZHJhU2V0dGluZ3MgPSB7XG4gIGJpbmFyeVBhdGg6ICcnLCAgLy8gYXV0by1kZXRlY3QgaWYgZW1wdHlcbiAgYXV0b1RhZzogdHJ1ZSxcbiAgYXV0b0xpbms6IHRydWUsXG4gIGNvbmZpZGVuY2VUaHJlc2hvbGQ6IDAuNixcbiAgcmVmcmVzaEludGVydmFsOiAzMDAsICAvLyBzZWNvbmRzXG4gIGVuYWJsZUdyYXBoT3ZlcmxheTogdHJ1ZSxcbn07XG5cbi8vIE1BUks6IC0gUGx1Z2luXG5cbmV4cG9ydCBkZWZhdWx0IGNsYXNzIEh5ZHJhUGx1Z2luIGV4dGVuZHMgUGx1Z2luIHtcbiAgc2V0dGluZ3M6IEh5ZHJhU2V0dGluZ3MgPSBERUZBVUxUX1NFVFRJTkdTO1xuICBicmlkZ2U6IEh5ZHJhQnJpZGdlO1xuICBwcml2YXRlIHJlZnJlc2hUaW1lcjogbnVtYmVyIHwgbnVsbCA9IG51bGw7XG5cbiAgYXN5bmMgb25sb2FkKCkge1xuICAgIGF3YWl0IHRoaXMubG9hZFNldHRpbmdzKCk7XG5cbiAgICAvLyBJbml0aWFsaXplIHRoZSBicmlkZ2UgdG8gdGhlIEh5ZHJhIGJpbmFyeVxuICAgIHRoaXMuYnJpZGdlID0gbmV3IEh5ZHJhQnJpZGdlKHRoaXMuc2V0dGluZ3MuYmluYXJ5UGF0aCB8fCBhd2FpdCB0aGlzLmRldGVjdEJpbmFyeSgpKTtcblxuICAgIC8vIFJlZ2lzdGVyIHZpZXdzXG4gICAgdGhpcy5yZWdpc3RlclZpZXcoU0lERUJBUl9WSUVXX1RZUEUsIChsZWFmKSA9PiBuZXcgSHlkcmFTaWRlYmFyVmlldyhsZWFmLCB0aGlzKSk7XG4gICAgdGhpcy5yZWdpc3RlclZpZXcoSEVBTFRIX1ZJRVdfVFlQRSwgKGxlYWYpID0+IG5ldyBIeWRyYUhlYWx0aFZpZXcobGVhZiwgdGhpcykpO1xuXG4gICAgLy8gUmliYm9uIGljb25cbiAgICB0aGlzLmFkZFJpYmJvbkljb24oJ2Ryb3BsZXQnLCAnSHlkcmEnLCAoKSA9PiB7XG4gICAgICB0aGlzLmFjdGl2YXRlU2lkZWJhcigpO1xuICAgIH0pO1xuXG4gICAgLy8gQ29tbWFuZHNcbiAgICB0aGlzLmFkZENvbW1hbmQoe1xuICAgICAgaWQ6ICdoeWRyYS1zY2FuJyxcbiAgICAgIG5hbWU6ICdTY2FuIHZhdWx0JyxcbiAgICAgIGNhbGxiYWNrOiAoKSA9PiB0aGlzLnNjYW5WYXVsdCgpLFxuICAgIH0pO1xuXG4gICAgdGhpcy5hZGRDb21tYW5kKHtcbiAgICAgIGlkOiAnaHlkcmEtaHlkcmF0ZS1jdXJyZW50JyxcbiAgICAgIG5hbWU6ICdIeWRyYXRlIGN1cnJlbnQgbm90ZScsXG4gICAgICBjYWxsYmFjazogKCkgPT4gdGhpcy5oeWRyYXRlQ3VycmVudE5vdGUoKSxcbiAgICB9KTtcblxuICAgIHRoaXMuYWRkQ29tbWFuZCh7XG4gICAgICBpZDogJ2h5ZHJhLWhlYWx0aCcsXG4gICAgICBuYW1lOiAnU2hvdyB2YXVsdCBoZWFsdGgnLFxuICAgICAgY2FsbGJhY2s6ICgpID0+IHRoaXMuc2hvd0hlYWx0aCgpLFxuICAgIH0pO1xuXG4gICAgdGhpcy5hZGRDb21tYW5kKHtcbiAgICAgIGlkOiAnaHlkcmEtc3VnZ2VzdC10YWdzJyxcbiAgICAgIG5hbWU6ICdTdWdnZXN0IHRhZ3MgZm9yIGN1cnJlbnQgbm90ZScsXG4gICAgICBjYWxsYmFjazogKCkgPT4gdGhpcy5zdWdnZXN0VGFncygpLFxuICAgIH0pO1xuXG4gICAgdGhpcy5hZGRDb21tYW5kKHtcbiAgICAgIGlkOiAnaHlkcmEtZmluZC1yZWxhdGlvbnMnLFxuICAgICAgbmFtZTogJ0ZpbmQgcmVsYXRpb25zaGlwcyBmb3IgY3VycmVudCBub3RlJyxcbiAgICAgIGNhbGxiYWNrOiAoKSA9PiB0aGlzLmZpbmRSZWxhdGlvbnNoaXBzKCksXG4gICAgfSk7XG5cbiAgICAvLyBTZXR0aW5ncyB0YWJcbiAgICB0aGlzLmFkZFNldHRpbmdUYWIobmV3IEh5ZHJhU2V0dGluZ1RhYih0aGlzLmFwcCwgdGhpcykpO1xuXG4gICAgLy8gQXV0by1yZWZyZXNoIG9uIG5vdGUgc2F2ZVxuICAgIHRoaXMucmVnaXN0ZXJFdmVudChcbiAgICAgIHRoaXMuYXBwLnZhdWx0Lm9uKCdtb2RpZnknLCAoZmlsZSkgPT4ge1xuICAgICAgICBpZiAoZmlsZSBpbnN0YW5jZW9mIFRGaWxlICYmIGZpbGUuZXh0ZW5zaW9uID09PSAnbWQnICYmIHRoaXMuc2V0dGluZ3MuYXV0b1RhZykge1xuICAgICAgICAgIHRoaXMuaHlkcmF0ZU5vdGUoZmlsZSk7XG4gICAgICAgIH1cbiAgICAgIH0pXG4gICAgKTtcblxuICAgIC8vIFN0YXJ0IHJlZnJlc2ggdGltZXJcbiAgICB0aGlzLnN0YXJ0UmVmcmVzaFRpbWVyKCk7XG5cbiAgICBjb25zb2xlLmxvZygnSHlkcmEgcGx1Z2luIGxvYWRlZCcpO1xuICB9XG5cbiAgb251bmxvYWQoKSB7XG4gICAgaWYgKHRoaXMucmVmcmVzaFRpbWVyKSB7XG4gICAgICB3aW5kb3cuY2xlYXJJbnRlcnZhbCh0aGlzLnJlZnJlc2hUaW1lcik7XG4gICAgfVxuICB9XG5cbiAgLy8gTUFSSzogLSBCaW5hcnkgZGV0ZWN0aW9uXG5cbiAgcHJpdmF0ZSBhc3luYyBkZXRlY3RCaW5hcnkoKTogUHJvbWlzZTxzdHJpbmc+IHtcbiAgICAvLyBUcnkgY29tbW9uIGxvY2F0aW9uc1xuICAgIGNvbnN0IGNhbmRpZGF0ZXMgPSBbXG4gICAgICAnL3Vzci9sb2NhbC9iaW4vaHlkcmEnLFxuICAgICAgJy9vcHQvaG9tZWJyZXcvYmluL2h5ZHJhJyxcbiAgICAgIGAke3Byb2Nlc3MuZW52LkhPTUV9Ly5sb2NhbC9iaW4vaHlkcmFgLFxuICAgIF07XG5cbiAgICBsZXQgZXhlY0ZpbGVTeW5jOiBhbnkgPSBudWxsO1xuICAgIHRyeSB7IGV4ZWNGaWxlU3luYyA9IHJlcXVpcmUoJ2NoaWxkX3Byb2Nlc3MnKS5leGVjRmlsZVN5bmM7IH0gY2F0Y2gge31cbiAgICBmb3IgKGNvbnN0IHBhdGggb2YgY2FuZGlkYXRlcykge1xuICAgICAgdHJ5IHtcbiAgICAgICAgZXhlY0ZpbGVTeW5jKHBhdGgsIFsnLS12ZXJzaW9uJ10sIHsgc3RkaW86ICdpZ25vcmUnIH0pO1xuICAgICAgICByZXR1cm4gcGF0aDtcbiAgICAgIH0gY2F0Y2gge1xuICAgICAgICBjb250aW51ZTtcbiAgICAgIH1cbiAgICB9XG5cbiAgICBuZXcgTm90aWNlKCdIeWRyYSBiaW5hcnkgbm90IGZvdW5kLiBTZXQgcGF0aCBpbiBzZXR0aW5ncy4nLCA1MDAwKTtcbiAgICByZXR1cm4gJ2h5ZHJhJztcbiAgfVxuXG4gIC8vIE1BUks6IC0gQWN0aW9uc1xuXG4gIGFzeW5jIHNjYW5WYXVsdCgpIHtcbiAgICBuZXcgTm90aWNlKCdIeWRyYTogU2Nhbm5pbmcgdmF1bHQuLi4nKTtcbiAgICB0cnkge1xuICAgICAgY29uc3QgcmVzdWx0ID0gYXdhaXQgdGhpcy5icmlkZ2Uuc2Nhbih0aGlzLmFwcC52YXVsdC5hZGFwdGVyLmdldEJhc2VQYXRoKCkpO1xuICAgICAgbmV3IE5vdGljZShgSHlkcmE6ICR7cmVzdWx0Lm5vdGVzfSBub3RlcywgJHtyZXN1bHQudGFnc30gdGFncywgJHtyZXN1bHQub3JwaGFuZWR9IG9ycGhhbmVkYCk7XG5cbiAgICAgIC8vIFVwZGF0ZSBzaWRlYmFyXG4gICAgICBjb25zdCBzaWRlYmFyID0gdGhpcy5nZXRTaWRlYmFyKCk7XG4gICAgICBpZiAoc2lkZWJhcikgc2lkZWJhci51cGRhdGVTY2FuUmVzdWx0KHJlc3VsdCk7XG4gICAgfSBjYXRjaCAoZXJyKSB7XG4gICAgICBuZXcgTm90aWNlKGBIeWRyYTogU2NhbiBmYWlsZWQgXHUyMDE0ICR7ZXJyLm1lc3NhZ2V9YCk7XG4gICAgfVxuICB9XG5cbiAgYXN5bmMgaHlkcmF0ZUN1cnJlbnROb3RlKCkge1xuICAgIGNvbnN0IGZpbGUgPSB0aGlzLmFwcC53b3Jrc3BhY2UuZ2V0QWN0aXZlRmlsZSgpO1xuICAgIGlmICghZmlsZSB8fCBmaWxlLmV4dGVuc2lvbiAhPT0gJ21kJykge1xuICAgICAgbmV3IE5vdGljZSgnSHlkcmE6IE9wZW4gYSBtYXJrZG93biBmaWxlIGZpcnN0Jyk7XG4gICAgICByZXR1cm47XG4gICAgfVxuICAgIGF3YWl0IHRoaXMuaHlkcmF0ZU5vdGUoZmlsZSk7XG4gIH1cblxuICBwcml2YXRlIGFzeW5jIGh5ZHJhdGVOb3RlKGZpbGU6IFRGaWxlKSB7XG4gICAgdHJ5IHtcbiAgICAgIGNvbnN0IGNvbnRlbnQgPSBhd2FpdCB0aGlzLmFwcC52YXVsdC5yZWFkKGZpbGUpO1xuICAgICAgY29uc3Qgc3VnZ2VzdGlvbnMgPSBhd2FpdCB0aGlzLmJyaWRnZS5jbGFzc2lmeShmaWxlLnBhdGgsIGNvbnRlbnQpO1xuXG4gICAgICBpZiAoc3VnZ2VzdGlvbnMudGFncy5sZW5ndGggPiAwICYmIHRoaXMuc2V0dGluZ3MuYXV0b1RhZykge1xuICAgICAgICBjb25zdCB1cGRhdGVkID0gdGhpcy5hcHBseVRhZ3MoY29udGVudCwgc3VnZ2VzdGlvbnMudGFncyk7XG4gICAgICAgIGlmICh1cGRhdGVkICE9PSBjb250ZW50KSB7XG4gICAgICAgICAgYXdhaXQgdGhpcy5hcHAudmF1bHQubW9kaWZ5KGZpbGUsIHVwZGF0ZWQpO1xuICAgICAgICB9XG4gICAgICB9XG5cbiAgICAgIC8vIFVwZGF0ZSBzaWRlYmFyIHdpdGggc3VnZ2VzdGlvbnNcbiAgICAgIGNvbnN0IHNpZGViYXIgPSB0aGlzLmdldFNpZGViYXIoKTtcbiAgICAgIGlmIChzaWRlYmFyKSBzaWRlYmFyLnVwZGF0ZVN1Z2dlc3Rpb25zKGZpbGUsIHN1Z2dlc3Rpb25zKTtcbiAgICB9IGNhdGNoIChlcnIpIHtcbiAgICAgIC8vIFNpbGVudCBmYWlsIGZvciBhdXRvLWh5ZHJhdGlvbiBcdTIwMTQgZG9uJ3QgZGlzcnVwdCB3cml0aW5nXG4gICAgICBjb25zb2xlLndhcm4oJ0h5ZHJhIGh5ZHJhdGlvbiBlcnJvcjonLCBlcnIpO1xuICAgIH1cbiAgfVxuXG4gIGFzeW5jIHN1Z2dlc3RUYWdzKCkge1xuICAgIGNvbnN0IGZpbGUgPSB0aGlzLmFwcC53b3Jrc3BhY2UuZ2V0QWN0aXZlRmlsZSgpO1xuICAgIGlmICghZmlsZSkgcmV0dXJuO1xuXG4gICAgY29uc3QgY29udGVudCA9IGF3YWl0IHRoaXMuYXBwLnZhdWx0LnJlYWQoZmlsZSk7XG4gICAgY29uc3Qgc3VnZ2VzdGlvbnMgPSBhd2FpdCB0aGlzLmJyaWRnZS5jbGFzc2lmeShmaWxlLnBhdGgsIGNvbnRlbnQpO1xuXG4gICAgY29uc3Qgc2lkZWJhciA9IGF3YWl0IHRoaXMuYWN0aXZhdGVTaWRlYmFyKCk7XG4gICAgc2lkZWJhci5zaG93VGFnU3VnZ2VzdGlvbnMoc3VnZ2VzdGlvbnMudGFncyk7XG4gIH1cblxuICBhc3luYyBmaW5kUmVsYXRpb25zaGlwcygpIHtcbiAgICBjb25zdCBmaWxlID0gdGhpcy5hcHAud29ya3NwYWNlLmdldEFjdGl2ZUZpbGUoKTtcbiAgICBpZiAoIWZpbGUpIHJldHVybjtcblxuICAgIGNvbnN0IGNvbnRlbnQgPSBhd2FpdCB0aGlzLmFwcC52YXVsdC5yZWFkKGZpbGUpO1xuICAgIGNvbnN0IHJlbHMgPSBhd2FpdCB0aGlzLmJyaWRnZS5maW5kUmVsYXRpb25zaGlwcyhmaWxlLmJhc2VuYW1lLCBjb250ZW50KTtcblxuICAgIGNvbnN0IHNpZGViYXIgPSBhd2FpdCB0aGlzLmFjdGl2YXRlU2lkZWJhcigpO1xuICAgIHNpZGViYXIuc2hvd1JlbGF0aW9uc2hpcHMocmVscyk7XG4gIH1cblxuICBhc3luYyBzaG93SGVhbHRoKCkge1xuICAgIGNvbnN0IHJlc3VsdCA9IGF3YWl0IHRoaXMuYnJpZGdlLmhlYWx0aCh0aGlzLmFwcC52YXVsdC5hZGFwdGVyLmdldEJhc2VQYXRoKCkpO1xuICAgIGNvbnN0IGxlYWYgPSB0aGlzLmFwcC53b3Jrc3BhY2UuZ2V0UmlnaHRMZWFmKGZhbHNlKTtcbiAgICBpZiAobGVhZikge1xuICAgICAgYXdhaXQgbGVhZi5zZXRWaWV3U3RhdGUoeyB0eXBlOiBIRUFMVEhfVklFV19UWVBFLCBlanNvbjogcmVzdWx0IH0pO1xuICAgICAgdGhpcy5hcHAud29ya3NwYWNlLnJldmVhbExlYWYobGVhZik7XG4gICAgfVxuICB9XG5cbiAgLy8gTUFSSzogLSBIZWxwZXJzXG5cbiAgcHJpdmF0ZSBhcHBseVRhZ3MoY29udGVudDogc3RyaW5nLCB0YWdzOiBzdHJpbmdbXSk6IHN0cmluZyB7XG4gICAgLy8gQWRkIHRhZ3MgdG8gZnJvbnRtYXR0ZXIgb3IgYXBwZW5kIGF0IGVuZFxuICAgIGlmIChjb250ZW50LnN0YXJ0c1dpdGgoJy0tLScpKSB7XG4gICAgICBjb25zdCBlbmQgPSBjb250ZW50LmluZGV4T2YoJ1xcbi0tLScsIDMpO1xuICAgICAgaWYgKGVuZCA+IDApIHtcbiAgICAgICAgY29uc3QgZnJvbnRtYXR0ZXIgPSBjb250ZW50LnN1YnN0cmluZygwLCBlbmQpO1xuICAgICAgICBjb25zdCBoYXNUYWdzID0gZnJvbnRtYXR0ZXIuaW5jbHVkZXMoJ3RhZ3M6Jyk7XG4gICAgICAgIGlmIChoYXNUYWdzKSB7XG4gICAgICAgICAgLy8gQXBwZW5kIHRvIGV4aXN0aW5nIHRhZ3NcbiAgICAgICAgICBjb25zdCB0YWdFbmQgPSBmcm9udG1hdHRlci5pbmRleE9mKCdcXG4nLCBmcm9udG1hdHRlci5pbmRleE9mKCd0YWdzOicpKTtcbiAgICAgICAgICBjb25zdCBuZXdUYWdzID0gdGFncy5tYXAodCA9PiBgICAtICR7dH1gKS5qb2luKCdcXG4nKTtcbiAgICAgICAgICByZXR1cm4gY29udGVudC5zdWJzdHJpbmcoMCwgdGFnRW5kICsgMSkgKyBuZXdUYWdzICsgY29udGVudC5zdWJzdHJpbmcodGFnRW5kKTtcbiAgICAgICAgfSBlbHNlIHtcbiAgICAgICAgICAvLyBBZGQgdGFncyBmaWVsZFxuICAgICAgICAgIGNvbnN0IHRhZ3NGaWVsZCA9IGB0YWdzOlxcbiR7dGFncy5tYXAodCA9PiBgICAtICR7dH1gKS5qb2luKCdcXG4nKX1cXG5gO1xuICAgICAgICAgIHJldHVybiBjb250ZW50LnN1YnN0cmluZygwLCBlbmQpICsgdGFnc0ZpZWxkICsgY29udGVudC5zdWJzdHJpbmcoZW5kKTtcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH1cbiAgICAvLyBObyBmcm9udG1hdHRlciBcdTIwMTQgYXBwZW5kIHRhZ3MgYXQgZW5kXG4gICAgY29uc3QgdGFnU3RyaW5nID0gdGFncy5tYXAodCA9PiBgIyR7dH1gKS5qb2luKCcgJyk7XG4gICAgcmV0dXJuIGNvbnRlbnQgKyAnXFxuXFxuJyArIHRhZ1N0cmluZztcbiAgfVxuXG4gIHByaXZhdGUgc3RhcnRSZWZyZXNoVGltZXIoKSB7XG4gICAgaWYgKHRoaXMucmVmcmVzaFRpbWVyKSB3aW5kb3cuY2xlYXJJbnRlcnZhbCh0aGlzLnJlZnJlc2hUaW1lcik7XG4gICAgdGhpcy5yZWZyZXNoVGltZXIgPSB3aW5kb3cuc2V0SW50ZXJ2YWwoKCkgPT4ge1xuICAgICAgdGhpcy5zY2FuVmF1bHQoKTtcbiAgICB9LCB0aGlzLnNldHRpbmdzLnJlZnJlc2hJbnRlcnZhbCAqIDEwMDApO1xuICB9XG5cbiAgLy8gTUFSSzogLSBTaWRlYmFyXG5cbiAgcHJpdmF0ZSBnZXRTaWRlYmFyKCk6IEh5ZHJhU2lkZWJhclZpZXcgfCBudWxsIHtcbiAgICBjb25zdCBsZWF2ZXMgPSB0aGlzLmFwcC53b3Jrc3BhY2UuZ2V0TGVhdmVzT2ZUeXBlKFNJREVCQVJfVklFV19UWVBFKTtcbiAgICByZXR1cm4gbGVhdmVzLmxlbmd0aCA+IDAgPyBsZWF2ZXNbMF0udmlldyBhcyBIeWRyYVNpZGViYXJWaWV3IDogbnVsbDtcbiAgfVxuXG4gIHByaXZhdGUgYXN5bmMgYWN0aXZhdGVTaWRlYmFyKCk6IFByb21pc2U8SHlkcmFTaWRlYmFyVmlldz4ge1xuICAgIGNvbnN0IGV4aXN0aW5nID0gdGhpcy5nZXRTaWRlYmFyKCk7XG4gICAgaWYgKGV4aXN0aW5nKSByZXR1cm4gZXhpc3Rpbmc7XG5cbiAgICBjb25zdCBsZWFmID0gdGhpcy5hcHAud29ya3NwYWNlLmdldFJpZ2h0TGVhZihmYWxzZSk7XG4gICAgaWYgKCFsZWFmKSB0aHJvdyBuZXcgRXJyb3IoJ05vIHNpZGViYXIgbGVhZiBhdmFpbGFibGUnKTtcbiAgICBhd2FpdCBsZWFmLnNldFZpZXdTdGF0ZSh7IHR5cGU6IFNJREVCQVJfVklFV19UWVBFIH0pO1xuICAgIHRoaXMuYXBwLndvcmtzcGFjZS5yZXZlYWxMZWFmKGxlYWYpO1xuICAgIHJldHVybiBsZWFmLnZpZXcgYXMgSHlkcmFTaWRlYmFyVmlldztcbiAgfVxuXG4gIGFzeW5jIGxvYWRTZXR0aW5ncygpIHtcbiAgICB0aGlzLnNldHRpbmdzID0gT2JqZWN0LmFzc2lnbih7fSwgREVGQVVMVF9TRVRUSU5HUywgYXdhaXQgdGhpcy5sb2FkRGF0YSgpKTtcbiAgfVxuXG4gIGFzeW5jIHNhdmVTZXR0aW5ncygpIHtcbiAgICBhd2FpdCB0aGlzLnNhdmVEYXRhKHRoaXMuc2V0dGluZ3MpO1xuICAgIHRoaXMuYnJpZGdlLnVwZGF0ZUJpbmFyeSh0aGlzLnNldHRpbmdzLmJpbmFyeVBhdGgpO1xuICAgIHRoaXMuc3RhcnRSZWZyZXNoVGltZXIoKTtcbiAgfVxufVxuXG4vLyBNQVJLOiAtIFNldHRpbmdzIFRhYlxuXG5jbGFzcyBIeWRyYVNldHRpbmdUYWIgZXh0ZW5kcyBQbHVnaW5TZXR0aW5nVGFiIHtcbiAgcGx1Z2luOiBIeWRyYVBsdWdpbjtcblxuICBjb25zdHJ1Y3RvcihhcHA6IEFwcCwgcGx1Z2luOiBIeWRyYVBsdWdpbikge1xuICAgIHN1cGVyKGFwcCwgcGx1Z2luKTtcbiAgICB0aGlzLnBsdWdpbiA9IHBsdWdpbjtcbiAgfVxuXG4gIGRpc3BsYXkoKTogdm9pZCB7XG4gICAgY29uc3QgeyBjb250YWluZXJFbCB9ID0gdGhpcztcbiAgICBjb250YWluZXJFbC5lbXB0eSgpO1xuXG4gICAgY29udGFpbmVyRWwuY3JlYXRlRWwoJ2gzJywgeyB0ZXh0OiAnSHlkcmEgU2V0dGluZ3MnIH0pO1xuXG4gICAgbmV3IFNldHRpbmcoY29udGFpbmVyRWwpXG4gICAgICAuc2V0TmFtZSgnQmluYXJ5IHBhdGgnKVxuICAgICAgLnNldERlc2MoJ1BhdGggdG8gdGhlIGh5ZHJhIENMSSBiaW5hcnknKVxuICAgICAgLmFkZFRleHQodGV4dCA9PiB0ZXh0XG4gICAgICAgIC5zZXRQbGFjZWhvbGRlcignQXV0by1kZXRlY3QnKVxuICAgICAgICAuc2V0VmFsdWUodGhpcy5wbHVnaW4uc2V0dGluZ3MuYmluYXJ5UGF0aClcbiAgICAgICAgLm9uQ2hhbmdlKGFzeW5jICh2YWx1ZSkgPT4ge1xuICAgICAgICAgIHRoaXMucGx1Z2luLnNldHRpbmdzLmJpbmFyeVBhdGggPSB2YWx1ZTtcbiAgICAgICAgICBhd2FpdCB0aGlzLnBsdWdpbi5zYXZlU2V0dGluZ3MoKTtcbiAgICAgICAgfSkpO1xuXG4gICAgbmV3IFNldHRpbmcoY29udGFpbmVyRWwpXG4gICAgICAuc2V0TmFtZSgnQXV0by10YWcnKVxuICAgICAgLnNldERlc2MoJ0F1dG9tYXRpY2FsbHkgYWRkIHN1Z2dlc3RlZCB0YWdzIHdoZW4gbm90ZXMgYXJlIG1vZGlmaWVkJylcbiAgICAgIC5hZGRUb2dnbGUodG9nZ2xlID0+IHRvZ2dsZVxuICAgICAgICAuc2V0VmFsdWUodGhpcy5wbHVnaW4uc2V0dGluZ3MuYXV0b1RhZylcbiAgICAgICAgLm9uQ2hhbmdlKGFzeW5jICh2YWx1ZSkgPT4ge1xuICAgICAgICAgIHRoaXMucGx1Z2luLnNldHRpbmdzLmF1dG9UYWcgPSB2YWx1ZTtcbiAgICAgICAgICBhd2FpdCB0aGlzLnBsdWdpbi5zYXZlU2V0dGluZ3MoKTtcbiAgICAgICAgfSkpO1xuXG4gICAgbmV3IFNldHRpbmcoY29udGFpbmVyRWwpXG4gICAgICAuc2V0TmFtZSgnQXV0by1saW5rJylcbiAgICAgIC5zZXREZXNjKCdBdXRvbWF0aWNhbGx5IHN1Z2dlc3Qgd2lraWxpbmtzIGJldHdlZW4gcmVsYXRlZCBub3RlcycpXG4gICAgICAuYWRkVG9nZ2xlKHRvZ2dsZSA9PiB0b2dnbGVcbiAgICAgICAgLnNldFZhbHVlKHRoaXMucGx1Z2luLnNldHRpbmdzLmF1dG9MaW5rKVxuICAgICAgICAub25DaGFuZ2UoYXN5bmMgKHZhbHVlKSA9PiB7XG4gICAgICAgICAgdGhpcy5wbHVnaW4uc2V0dGluZ3MuYXV0b0xpbmsgPSB2YWx1ZTtcbiAgICAgICAgICBhd2FpdCB0aGlzLnBsdWdpbi5zYXZlU2V0dGluZ3MoKTtcbiAgICAgICAgfSkpO1xuXG4gICAgbmV3IFNldHRpbmcoY29udGFpbmVyRWwpXG4gICAgICAuc2V0TmFtZSgnQ29uZmlkZW5jZSB0aHJlc2hvbGQnKVxuICAgICAgLnNldERlc2MoJ01pbmltdW0gY29uZmlkZW5jZSBmb3IgYXV0by1jbGFzc2lmaWNhdGlvbiAoMC4wXHUyMDEzMS4wKScpXG4gICAgICAuYWRkU2xpZGVyKHNsaWRlciA9PiBzbGlkZXJcbiAgICAgICAgLnNldExpbWl0cygwLCAxLCAwLjA1KVxuICAgICAgICAuc2V0VmFsdWUodGhpcy5wbHVnaW4uc2V0dGluZ3MuY29uZmlkZW5jZVRocmVzaG9sZClcbiAgICAgICAgLnNldER5bmFtaWNUb29sdGlwKClcbiAgICAgICAgLm9uQ2hhbmdlKGFzeW5jICh2YWx1ZSkgPT4ge1xuICAgICAgICAgIHRoaXMucGx1Z2luLnNldHRpbmdzLmNvbmZpZGVuY2VUaHJlc2hvbGQgPSB2YWx1ZTtcbiAgICAgICAgICBhd2FpdCB0aGlzLnBsdWdpbi5zYXZlU2V0dGluZ3MoKTtcbiAgICAgICAgfSkpO1xuXG4gICAgbmV3IFNldHRpbmcoY29udGFpbmVyRWwpXG4gICAgICAuc2V0TmFtZSgnUmVmcmVzaCBpbnRlcnZhbCcpXG4gICAgICAuc2V0RGVzYygnU2Vjb25kcyBiZXR3ZWVuIGF1dG9tYXRpYyB2YXVsdCBzY2FucycpXG4gICAgICAuYWRkVGV4dCh0ZXh0ID0+IHRleHRcbiAgICAgICAgLnNldFZhbHVlKFN0cmluZyh0aGlzLnBsdWdpbi5zZXR0aW5ncy5yZWZyZXNoSW50ZXJ2YWwpKVxuICAgICAgICAub25DaGFuZ2UoYXN5bmMgKHZhbHVlKSA9PiB7XG4gICAgICAgICAgY29uc3QgbnVtID0gcGFyc2VJbnQodmFsdWUpO1xuICAgICAgICAgIGlmICghaXNOYU4obnVtKSAmJiBudW0gPiAwKSB7XG4gICAgICAgICAgICB0aGlzLnBsdWdpbi5zZXR0aW5ncy5yZWZyZXNoSW50ZXJ2YWwgPSBudW07XG4gICAgICAgICAgICBhd2FpdCB0aGlzLnBsdWdpbi5zYXZlU2V0dGluZ3MoKTtcbiAgICAgICAgICB9XG4gICAgICAgIH0pKTtcbiAgfVxufVxuIiwgIi8vIExhenktbG9hZCBjaGlsZF9wcm9jZXNzIChub3QgYXZhaWxhYmxlIGluIGFsbCBidW5kbGVyIGNvbnRleHRzKVxubGV0IGV4ZWNGaWxlQXN5bmM6ICgoY21kOiBzdHJpbmcsIGFyZ3M6IHN0cmluZ1tdLCBvcHRzPzogYW55KSA9PiBQcm9taXNlPHtzdGRvdXQ6IHN0cmluZ30+KSB8IG51bGwgPSBudWxsO1xudHJ5IHtcbiAgY29uc3QgeyBleGVjRmlsZSB9ID0gcmVxdWlyZSgnY2hpbGRfcHJvY2VzcycpO1xuICBjb25zdCB7IHByb21pc2lmeSB9ID0gcmVxdWlyZSgndXRpbCcpO1xuICBleGVjRmlsZUFzeW5jID0gcHJvbWlzaWZ5KGV4ZWNGaWxlKTtcbn0gY2F0Y2gge1xuICAvLyBjaGlsZF9wcm9jZXNzIHVuYXZhaWxhYmxlIFx1MjAxNCBoZXVyaXN0aWMtb25seSBtb2RlXG59XG5cbmV4cG9ydCBpbnRlcmZhY2UgU2NhblJlc3VsdCB7XG4gIG5vdGVzOiBudW1iZXI7XG4gIHRhZ3M6IG51bWJlcjtcbiAgb3JwaGFuZWQ6IG51bWJlcjtcbiAgYnJva2VuTGlua3M6IG51bWJlcjtcbiAgbWlzc2luZ0Zyb250bWF0dGVyOiBudW1iZXI7XG4gIHBhcmE6IHsgY2F0ZWdvcnk6IHN0cmluZzsgY291bnQ6IG51bWJlciB9W107XG59XG5cbmV4cG9ydCBpbnRlcmZhY2UgQ2xhc3NpZnlSZXN1bHQge1xuICB0YWdzOiBzdHJpbmdbXTtcbiAgd2lraWxpbmtzOiBzdHJpbmdbXTtcbiAga2luZDogc3RyaW5nO1xuICBsaWZlY3ljbGU6IHN0cmluZztcbiAgY29uZmlkZW5jZTogbnVtYmVyO1xuICByZWxhdGlvbnNoaXBzOiB7IHR5cGU6IHN0cmluZzsgdGFyZ2V0OiBzdHJpbmcgfVtdO1xufVxuXG5leHBvcnQgaW50ZXJmYWNlIEhlYWx0aFJlc3VsdCB7XG4gIHN0YXR1czogc3RyaW5nO1xuICBzdW1tYXJ5OiBzdHJpbmc7XG4gIGNoZWNrczogeyBuYW1lOiBzdHJpbmc7IHN0YXR1czogc3RyaW5nOyBtZXNzYWdlOiBzdHJpbmc7IGNvdW50OiBudW1iZXIgfVtdO1xufVxuXG5leHBvcnQgaW50ZXJmYWNlIFJlbGF0aW9uc2hpcFJlc3VsdCB7XG4gIHJlbGF0aW9uc2hpcHM6IHsgdHlwZTogc3RyaW5nOyB0YXJnZXQ6IHN0cmluZzsgY29uZmlkZW5jZTogbnVtYmVyIH1bXTtcbn1cblxuLy8gTUFSSzogLSBIeWRyYSBCaW5hcnkgQnJpZGdlXG5cbi8vLyBDYWxscyB0aGUgaHlkcmEgQ0xJIGJpbmFyeSBmb3IgYWxsIGhlYXZ5IGxpZnRpbmcuXG4vLy8gVGhlIHBsdWdpbiBpcyBhIHRoaW4gVHlwZVNjcmlwdCBzaGVsbCBcdTIwMTQgU3dpZnQgZG9lcyB0aGUgd29yay5cbmV4cG9ydCBjbGFzcyBIeWRyYUJyaWRnZSB7XG4gIHByaXZhdGUgYmluYXJ5UGF0aDogc3RyaW5nO1xuXG4gIGNvbnN0cnVjdG9yKGJpbmFyeVBhdGg6IHN0cmluZykge1xuICAgIHRoaXMuYmluYXJ5UGF0aCA9IGJpbmFyeVBhdGg7XG4gIH1cblxuICB1cGRhdGVCaW5hcnkocGF0aDogc3RyaW5nKSB7XG4gICAgdGhpcy5iaW5hcnlQYXRoID0gcGF0aDtcbiAgfVxuXG4gIC8vIE1BUks6IC0gQ29tbWFuZHNcblxuICBhc3luYyBzY2FuKHZhdWx0UGF0aDogc3RyaW5nKTogUHJvbWlzZTxTY2FuUmVzdWx0PiB7XG4gICAgY29uc3Qgb3V0cHV0ID0gYXdhaXQgdGhpcy5ydW4oWydzY2FuJywgJy0tdmF1bHQnLCB2YXVsdFBhdGhdKTtcbiAgICByZXR1cm4gdGhpcy5wYXJzZVNjYW5PdXRwdXQob3V0cHV0KTtcbiAgfVxuXG4gIGFzeW5jIGhlYWx0aCh2YXVsdFBhdGg6IHN0cmluZyk6IFByb21pc2U8SGVhbHRoUmVzdWx0PiB7XG4gICAgY29uc3Qgb3V0cHV0ID0gYXdhaXQgdGhpcy5ydW4oWydoZWFsdGgnLCAnLS12YXVsdCcsIHZhdWx0UGF0aF0pO1xuICAgIHJldHVybiB0aGlzLnBhcnNlSGVhbHRoT3V0cHV0KG91dHB1dCk7XG4gIH1cblxuICBhc3luYyBzZWFyY2godmF1bHRQYXRoOiBzdHJpbmcsIHF1ZXJ5OiBzdHJpbmcsIGxpbWl0OiBudW1iZXIgPSAyMCk6IFByb21pc2U8YW55W10+IHtcbiAgICBjb25zdCBvdXRwdXQgPSBhd2FpdCB0aGlzLnJ1bihbJ3NlYXJjaCcsICctLXZhdWx0JywgdmF1bHRQYXRoLCAnLS1xdWVyeScsIHF1ZXJ5LCAnLS1saW1pdCcsIFN0cmluZyhsaW1pdCldKTtcbiAgICByZXR1cm4gdGhpcy5wYXJzZVNlYXJjaE91dHB1dChvdXRwdXQpO1xuICB9XG5cbiAgYXN5bmMgY2xhc3NpZnkoZmlsZVBhdGg6IHN0cmluZywgY29udGVudDogc3RyaW5nKTogUHJvbWlzZTxDbGFzc2lmeVJlc3VsdD4ge1xuICAgIC8vIFdyaXRlIGNvbnRlbnQgdG8gYSB0ZW1wIGZpbGUsIHJ1biBjbGFzc2lmaWVyLCByZXR1cm4gcmVzdWx0c1xuICAgIC8vIEZvciBub3csIHVzZXMgaGV1cmlzdGljIGNsYXNzaWZpY2F0aW9uIGZyb20gdGhlIGFkYXB0ZXJcbiAgICBjb25zdCByZXN1bHQgPSBhd2FpdCB0aGlzLnJ1bihbJ2h5ZHJhdGUnLCAnLS1zb3VyY2UnLCBmaWxlUGF0aCwgJy0tZHJ5LXJ1biddKTtcbiAgICByZXR1cm4gdGhpcy5wYXJzZUNsYXNzaWZ5T3V0cHV0KHJlc3VsdCwgY29udGVudCk7XG4gIH1cblxuICBhc3luYyBmaW5kUmVsYXRpb25zaGlwcyhub3RlTmFtZTogc3RyaW5nLCBjb250ZW50OiBzdHJpbmcpOiBQcm9taXNlPFJlbGF0aW9uc2hpcFJlc3VsdD4ge1xuICAgIC8vIEV4dHJhY3Qgd2lraWxpbmtzIGFuZCBmaW5kIHJlbGF0ZWQgbm90ZXNcbiAgICBjb25zdCB3aWtpbGlua3MgPSB0aGlzLmV4dHJhY3RXaWtpbGlua3MoY29udGVudCk7XG4gICAgY29uc3QgdGFncyA9IHRoaXMuZXh0cmFjdFRhZ3MoY29udGVudCk7XG5cbiAgICByZXR1cm4ge1xuICAgICAgcmVsYXRpb25zaGlwczogW1xuICAgICAgICAuLi53aWtpbGlua3MubWFwKHcgPT4gKHsgdHlwZTogJ3dpa2lsaW5rJywgdGFyZ2V0OiB3LCBjb25maWRlbmNlOiAxLjAgfSkpLFxuICAgICAgICAuLi50YWdzLm1hcCh0ID0+ICh7IHR5cGU6ICd0YWcnLCB0YXJnZXQ6IGAjJHt0fWAsIGNvbmZpZGVuY2U6IDAuNyB9KSksXG4gICAgICBdLFxuICAgIH07XG4gIH1cblxuICAvLyBNQVJLOiAtIEJpbmFyeSBleGVjdXRpb25cblxuICBwcml2YXRlIGFzeW5jIHJ1bihhcmdzOiBzdHJpbmdbXSk6IFByb21pc2U8c3RyaW5nPiB7XG4gICAgdHJ5IHtcbiAgICAgIGNvbnN0IHsgc3Rkb3V0IH0gPSBhd2FpdCBleGVjRmlsZUFzeW5jKHRoaXMuYmluYXJ5UGF0aCwgYXJncywge1xuICAgICAgICBtYXhCdWZmZXI6IDEwICogMTAyNCAqIDEwMjQsXG4gICAgICAgIHRpbWVvdXQ6IDMwMDAwLFxuICAgICAgfSk7XG4gICAgICByZXR1cm4gc3Rkb3V0O1xuICAgIH0gY2F0Y2ggKGVycjogYW55KSB7XG4gICAgICB0aHJvdyBuZXcgRXJyb3IoYEh5ZHJhIGJpbmFyeSBlcnJvcjogJHtlcnIubWVzc2FnZX1gKTtcbiAgICB9XG4gIH1cblxuICAvLyBNQVJLOiAtIE91dHB1dCBwYXJzZXJzXG5cbiAgcHJpdmF0ZSBwYXJzZVNjYW5PdXRwdXQob3V0cHV0OiBzdHJpbmcpOiBTY2FuUmVzdWx0IHtcbiAgICBjb25zdCByZXN1bHQ6IFNjYW5SZXN1bHQgPSB7XG4gICAgICBub3RlczogMCwgdGFnczogMCwgb3JwaGFuZWQ6IDAsIGJyb2tlbkxpbmtzOiAwLCBtaXNzaW5nRnJvbnRtYXR0ZXI6IDAsIHBhcmE6IFtdLFxuICAgIH07XG5cbiAgICBjb25zdCBub3Rlc01hdGNoID0gb3V0cHV0Lm1hdGNoKC9Ob3RlczpcXHMrKFxcZCspLyk7XG4gICAgY29uc3QgdGFnc01hdGNoID0gb3V0cHV0Lm1hdGNoKC9UYWdzOlxccysoXFxkKykvKTtcbiAgICBjb25zdCBvcnBoYW5lZE1hdGNoID0gb3V0cHV0Lm1hdGNoKC9PcnBoYW5lZDpcXHMrKFxcZCspLyk7XG4gICAgY29uc3QgYnJva2VuTWF0Y2ggPSBvdXRwdXQubWF0Y2goL0Jyb2tlbiB3aWtpbGlua3M6XFxzKyhcXGQrKS8pO1xuICAgIGNvbnN0IGZyb250bWF0dGVyTWF0Y2ggPSBvdXRwdXQubWF0Y2goL01pc3NpbmcgZnJvbnRtYXR0ZXI6XFxzKyhcXGQrKS8pO1xuXG4gICAgaWYgKG5vdGVzTWF0Y2gpIHJlc3VsdC5ub3RlcyA9IHBhcnNlSW50KG5vdGVzTWF0Y2hbMV0pO1xuICAgIGlmICh0YWdzTWF0Y2gpIHJlc3VsdC50YWdzID0gcGFyc2VJbnQodGFnc01hdGNoWzFdKTtcbiAgICBpZiAob3JwaGFuZWRNYXRjaCkgcmVzdWx0Lm9ycGhhbmVkID0gcGFyc2VJbnQob3JwaGFuZWRNYXRjaFsxXSk7XG4gICAgaWYgKGJyb2tlbk1hdGNoKSByZXN1bHQuYnJva2VuTGlua3MgPSBwYXJzZUludChicm9rZW5NYXRjaFsxXSk7XG4gICAgaWYgKGZyb250bWF0dGVyTWF0Y2gpIHJlc3VsdC5taXNzaW5nRnJvbnRtYXR0ZXIgPSBwYXJzZUludChmcm9udG1hdHRlck1hdGNoWzFdKTtcblxuICAgIC8vIFBhcnNlIFBBUkEgYnJlYWtkb3duXG4gICAgY29uc3QgcGFyYVNlY3Rpb24gPSBvdXRwdXQubWF0Y2goL1BBUkEgQnJlYWtkb3duOihbXFxzXFxTXSo/KSg/PVxcblxcbnxcXG5PcnBoYW5lZHwkKS8pO1xuICAgIGlmIChwYXJhU2VjdGlvbikge1xuICAgICAgY29uc3QgbGluZXMgPSBwYXJhU2VjdGlvblsxXS50cmltKCkuc3BsaXQoJ1xcbicpO1xuICAgICAgZm9yIChjb25zdCBsaW5lIG9mIGxpbmVzKSB7XG4gICAgICAgIGNvbnN0IG1hdGNoID0gbGluZS5tYXRjaCgvXlxccysoXFxTKylcXHMrKFxcZCspLyk7XG4gICAgICAgIGlmIChtYXRjaCkge1xuICAgICAgICAgIHJlc3VsdC5wYXJhLnB1c2goeyBjYXRlZ29yeTogbWF0Y2hbMV0sIGNvdW50OiBwYXJzZUludChtYXRjaFsyXSkgfSk7XG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9XG5cbiAgICByZXR1cm4gcmVzdWx0O1xuICB9XG5cbiAgcHJpdmF0ZSBwYXJzZUhlYWx0aE91dHB1dChvdXRwdXQ6IHN0cmluZyk6IEhlYWx0aFJlc3VsdCB7XG4gICAgY29uc3QgY2hlY2tzOiB7IG5hbWU6IHN0cmluZzsgc3RhdHVzOiBzdHJpbmc7IG1lc3NhZ2U6IHN0cmluZzsgY291bnQ6IG51bWJlciB9W10gPSBbXTtcblxuICAgIGNvbnN0IGxpbmVzID0gb3V0cHV0LnNwbGl0KCdcXG4nKTtcbiAgICBmb3IgKGNvbnN0IGxpbmUgb2YgbGluZXMpIHtcbiAgICAgIGNvbnN0IG1hdGNoID0gbGluZS5tYXRjaCgvW1x1MjcwNVx1MjZBMFx1RkUwRlx1RDgzRFx1REQzNF1cXHMrKC4rPylcXHN7Mix9KC4rKS8pO1xuICAgICAgaWYgKG1hdGNoKSB7XG4gICAgICAgIGNvbnN0IG5hbWUgPSBtYXRjaFsxXS50cmltKCk7XG4gICAgICAgIGNvbnN0IG1lc3NhZ2UgPSBtYXRjaFsyXS50cmltKCk7XG4gICAgICAgIGxldCBzdGF0dXMgPSAnaGVhbHRoeSc7XG4gICAgICAgIGlmIChsaW5lLmluY2x1ZGVzKCdcdTI2QTBcdUZFMEYnKSkgc3RhdHVzID0gJ3dhcm5pbmcnO1xuICAgICAgICBlbHNlIGlmIChsaW5lLmluY2x1ZGVzKCdcdUQ4M0RcdUREMzQnKSkgc3RhdHVzID0gJ2NyaXRpY2FsJztcbiAgICAgICAgY2hlY2tzLnB1c2goeyBuYW1lLCBzdGF0dXMsIG1lc3NhZ2UsIGNvdW50OiAwIH0pO1xuICAgICAgfVxuICAgIH1cblxuICAgIGNvbnN0IG92ZXJhbGxNYXRjaCA9IG91dHB1dC5tYXRjaCgvT3ZlcmFsbDpcXHMrKFxcdyspLyk7XG4gICAgY29uc3Qgc3VtbWFyeU1hdGNoID0gb3V0cHV0Lm1hdGNoKC9TdW1tYXJ5OlxccysoLispLyk7XG5cbiAgICByZXR1cm4ge1xuICAgICAgc3RhdHVzOiBvdmVyYWxsTWF0Y2ggPyBvdmVyYWxsTWF0Y2hbMV0udG9Mb3dlckNhc2UoKSA6ICd1bmtub3duJyxcbiAgICAgIHN1bW1hcnk6IHN1bW1hcnlNYXRjaCA/IHN1bW1hcnlNYXRjaFsxXSA6ICcnLFxuICAgICAgY2hlY2tzLFxuICAgIH07XG4gIH1cblxuICBwcml2YXRlIHBhcnNlU2VhcmNoT3V0cHV0KG91dHB1dDogc3RyaW5nKTogYW55W10ge1xuICAgIGNvbnN0IHJlc3VsdHM6IGFueVtdID0gW107XG4gICAgY29uc3QgbGluZXMgPSBvdXRwdXQuc3BsaXQoJ1xcbicpO1xuICAgIGZvciAoY29uc3QgbGluZSBvZiBsaW5lcykge1xuICAgICAgaWYgKGxpbmUudHJpbSgpLnN0YXJ0c1dpdGgoJ0ZvdW5kJykpIGNvbnRpbnVlO1xuICAgICAgaWYgKGxpbmUudHJpbSgpLnN0YXJ0c1dpdGgoJ1x1MjAxNCcpKSBjb250aW51ZTtcbiAgICAgIGlmIChsaW5lLnRyaW0oKS5sZW5ndGggPCAzKSBjb250aW51ZTtcbiAgICAgIC8vIFBhcnNlIFwiVGl0bGUgW3RhZ3NdIC8gcGF0aFwiXG4gICAgICBjb25zdCBtYXRjaCA9IGxpbmUubWF0Y2goL15cXHMrKC4rPykoPzpcXHMrXFxbKC4rKVxcXSk/XFxzKiQvKTtcbiAgICAgIGlmIChtYXRjaCkge1xuICAgICAgICByZXN1bHRzLnB1c2goe1xuICAgICAgICAgIHRpdGxlOiBtYXRjaFsxXS50cmltKCksXG4gICAgICAgICAgdGFnczogbWF0Y2hbMl0gPyBtYXRjaFsyXS5zcGxpdCgnLCAnKS5tYXAoKHQ6IHN0cmluZykgPT4gdC50cmltKCkpIDogW10sXG4gICAgICAgIH0pO1xuICAgICAgfVxuICAgIH1cbiAgICByZXR1cm4gcmVzdWx0cztcbiAgfVxuXG4gIHByaXZhdGUgcGFyc2VDbGFzc2lmeU91dHB1dChvdXRwdXQ6IHN0cmluZywgY29udGVudDogc3RyaW5nKTogQ2xhc3NpZnlSZXN1bHQge1xuICAgIC8vIEZhbGxiYWNrOiB1c2UgY29udGVudC1iYXNlZCBoZXVyaXN0aWNzIGlmIGJpbmFyeSBkb2Vzbid0IHByb3ZpZGUgY2xhc3NpZmljYXRpb25cbiAgICBjb25zdCB0YWdzID0gdGhpcy5leHRyYWN0VGFncyhjb250ZW50KTtcbiAgICBjb25zdCB3aWtpbGlua3MgPSB0aGlzLmV4dHJhY3RXaWtpbGlua3MoY29udGVudCk7XG5cbiAgICByZXR1cm4ge1xuICAgICAgdGFncyxcbiAgICAgIHdpa2lsaW5rcyxcbiAgICAgIGtpbmQ6ICdub3RlJyxcbiAgICAgIGxpZmVjeWNsZTogJ2RyYWZ0JyxcbiAgICAgIGNvbmZpZGVuY2U6IDAuNSxcbiAgICAgIHJlbGF0aW9uc2hpcHM6IHdpa2lsaW5rcy5tYXAodyA9PiAoeyB0eXBlOiAncmVmZXJlbmNlcycsIHRhcmdldDogdyB9KSksXG4gICAgfTtcbiAgfVxuXG4gIC8vIE1BUks6IC0gQ29udGVudCBoZWxwZXJzXG5cbiAgcHJpdmF0ZSBleHRyYWN0V2lraWxpbmtzKGNvbnRlbnQ6IHN0cmluZyk6IHN0cmluZ1tdIHtcbiAgICBjb25zdCBtYXRjaGVzID0gY29udGVudC5tYXRjaEFsbCgvXFxbXFxbKFteXFxdfF0rKSg/OlxcfFteXFxdXSspP1xcXVxcXS9nKTtcbiAgICByZXR1cm4gQXJyYXkuZnJvbShtYXRjaGVzKS5tYXAobSA9PiBtWzFdLnRyaW0oKSk7XG4gIH1cblxuICBwcml2YXRlIGV4dHJhY3RUYWdzKGNvbnRlbnQ6IHN0cmluZyk6IHN0cmluZ1tdIHtcbiAgICBjb25zdCB0YWdzID0gbmV3IFNldDxzdHJpbmc+KCk7XG4gICAgLy8gSW5saW5lICN0YWdzXG4gICAgY29uc3QgbWF0Y2hlcyA9IGNvbnRlbnQubWF0Y2hBbGwoLyg/Ol58XFxzKSMoW2EtekEtWl1bYS16QS1aMC05L18tXSopL2cpO1xuICAgIGZvciAoY29uc3QgbWF0Y2ggb2YgbWF0Y2hlcykge1xuICAgICAgdGFncy5hZGQobWF0Y2hbMV0udG9Mb3dlckNhc2UoKSk7XG4gICAgfVxuICAgIHJldHVybiBBcnJheS5mcm9tKHRhZ3MpO1xuICB9XG59XG4iLCAiaW1wb3J0IHsgSXRlbVZpZXcsIFdvcmtzcGFjZUxlYWYsIFRGaWxlIH0gZnJvbSAnb2JzaWRpYW4nO1xuaW1wb3J0IHR5cGUgSHlkcmFQbHVnaW4gZnJvbSAnLi9tYWluJztcbmltcG9ydCB0eXBlIHsgU2NhblJlc3VsdCwgQ2xhc3NpZnlSZXN1bHQsIFJlbGF0aW9uc2hpcFJlc3VsdCB9IGZyb20gJy4vYnJpZGdlJztcblxuZXhwb3J0IGNvbnN0IFNJREVCQVJfVklFV19UWVBFID0gJ2h5ZHJhLXNpZGViYXInO1xuXG5leHBvcnQgY2xhc3MgSHlkcmFTaWRlYmFyVmlldyBleHRlbmRzIEl0ZW1WaWV3IHtcbiAgcGx1Z2luOiBIeWRyYVBsdWdpbjtcbiAgcHJpdmF0ZSBzY2FuUmVzdWx0OiBTY2FuUmVzdWx0IHwgbnVsbCA9IG51bGw7XG4gIHByaXZhdGUgY3VycmVudFN1Z2dlc3Rpb25zOiB7IGZpbGU6IFRGaWxlOyByZXN1bHQ6IENsYXNzaWZ5UmVzdWx0IH0gfCBudWxsID0gbnVsbDtcbiAgcHJpdmF0ZSBjdXJyZW50UmVsYXRpb25zaGlwczogUmVsYXRpb25zaGlwUmVzdWx0IHwgbnVsbCA9IG51bGw7XG5cbiAgY29uc3RydWN0b3IobGVhZjogV29ya3NwYWNlTGVhZiwgcGx1Z2luOiBIeWRyYVBsdWdpbikge1xuICAgIHN1cGVyKGxlYWYpO1xuICAgIHRoaXMucGx1Z2luID0gcGx1Z2luO1xuICB9XG5cbiAgZ2V0Vmlld1R5cGUoKTogc3RyaW5nIHsgcmV0dXJuIFNJREVCQVJfVklFV19UWVBFOyB9XG4gIGdldERpc3BsYXlUZXh0KCk6IHN0cmluZyB7IHJldHVybiAnSHlkcmEnOyB9XG4gIGdldEljb24oKTogc3RyaW5nIHsgcmV0dXJuICdkcm9wbGV0JzsgfVxuXG4gIGFzeW5jIG9uT3BlbigpIHtcbiAgICB0aGlzLnJlbmRlcigpO1xuICB9XG5cbiAgYXN5bmMgb25DbG9zZSgpIHt9XG5cbiAgLy8gTUFSSzogLSBVcGRhdGVzXG5cbiAgdXBkYXRlU2NhblJlc3VsdChyZXN1bHQ6IFNjYW5SZXN1bHQpIHtcbiAgICB0aGlzLnNjYW5SZXN1bHQgPSByZXN1bHQ7XG4gICAgdGhpcy5yZW5kZXIoKTtcbiAgfVxuXG4gIHVwZGF0ZVN1Z2dlc3Rpb25zKGZpbGU6IFRGaWxlLCByZXN1bHQ6IENsYXNzaWZ5UmVzdWx0KSB7XG4gICAgdGhpcy5jdXJyZW50U3VnZ2VzdGlvbnMgPSB7IGZpbGUsIHJlc3VsdCB9O1xuICAgIHRoaXMucmVuZGVyKCk7XG4gIH1cblxuICBzaG93VGFnU3VnZ2VzdGlvbnModGFnczogc3RyaW5nW10pIHtcbiAgICB0aGlzLnJlbmRlclRhZ1N1Z2dlc3Rpb25zKHRhZ3MpO1xuICB9XG5cbiAgc2hvd1JlbGF0aW9uc2hpcHMocmVsczogUmVsYXRpb25zaGlwUmVzdWx0KSB7XG4gICAgdGhpcy5jdXJyZW50UmVsYXRpb25zaGlwcyA9IHJlbHM7XG4gICAgdGhpcy5yZW5kZXIoKTtcbiAgfVxuXG4gIC8vIE1BUks6IC0gUmVuZGVyaW5nXG5cbiAgcHJpdmF0ZSByZW5kZXIoKSB7XG4gICAgY29uc3QgY29udGFpbmVyID0gdGhpcy5jb250ZW50RWw7XG4gICAgY29udGFpbmVyLmVtcHR5KCk7XG4gICAgY29udGFpbmVyLmFkZENsYXNzKCdoeWRyYS1zaWRlYmFyJyk7XG5cbiAgICAvLyBIZWFkZXJcbiAgICBjb25zdCBoZWFkZXIgPSBjb250YWluZXIuY3JlYXRlRGl2KHsgY2xzOiAnaHlkcmEtaGVhZGVyJyB9KTtcbiAgICBoZWFkZXIuY3JlYXRlRWwoJ3NwYW4nLCB7IHRleHQ6ICdIeWRyYScsIGNsczogJ2h5ZHJhLWxvZ28nIH0pO1xuICAgIGhlYWRlci5jcmVhdGVFbCgnc3BhbicsIHsgdGV4dDogJ0NvbnRleHQgSHlkcmF0aW9uJywgY2xzOiAnaHlkcmEtdGFnbGluZScgfSk7XG5cbiAgICAvLyBTdGF0c1xuICAgIGlmICh0aGlzLnNjYW5SZXN1bHQpIHtcbiAgICAgIHRoaXMucmVuZGVyU3RhdHMoY29udGFpbmVyKTtcbiAgICB9XG5cbiAgICAvLyBTdWdnZXN0aW9uc1xuICAgIGlmICh0aGlzLmN1cnJlbnRTdWdnZXN0aW9ucykge1xuICAgICAgdGhpcy5yZW5kZXJTdWdnZXN0aW9ucyhjb250YWluZXIpO1xuICAgIH1cblxuICAgIC8vIFJlbGF0aW9uc2hpcHNcbiAgICBpZiAodGhpcy5jdXJyZW50UmVsYXRpb25zaGlwcykge1xuICAgICAgdGhpcy5yZW5kZXJSZWxhdGlvbnNoaXBzKGNvbnRhaW5lcik7XG4gICAgfVxuXG4gICAgLy8gQWN0aW9uc1xuICAgIHRoaXMucmVuZGVyQWN0aW9ucyhjb250YWluZXIpO1xuICB9XG5cbiAgcHJpdmF0ZSByZW5kZXJTdGF0cyhjb250YWluZXI6IEhUTUxFbGVtZW50KSB7XG4gICAgY29uc3QgciA9IHRoaXMuc2NhblJlc3VsdCE7XG4gICAgY29uc3Qgc3RhdHMgPSBjb250YWluZXIuY3JlYXRlRGl2KHsgY2xzOiAnaHlkcmEtc3RhdHMnIH0pO1xuXG4gICAgY29uc3QgY2FyZHMgPSBbXG4gICAgICB7IGxhYmVsOiAnTm90ZXMnLCB2YWx1ZTogci5ub3RlcywgaWNvbjogJ1x1RDgzRFx1RENDNCcgfSxcbiAgICAgIHsgbGFiZWw6ICdUYWdzJywgdmFsdWU6IHIudGFncywgaWNvbjogJ1x1RDgzQ1x1REZGN1x1RkUwRicgfSxcbiAgICAgIHsgbGFiZWw6ICdPcnBoYW5lZCcsIHZhbHVlOiByLm9ycGhhbmVkLCBpY29uOiAnXHVEODNEXHVEQzdCJyB9LFxuICAgICAgeyBsYWJlbDogJ0Jyb2tlbicsIHZhbHVlOiByLmJyb2tlbkxpbmtzLCBpY29uOiAnXHVEODNEXHVERDE3JyB9LFxuICAgIF07XG5cbiAgICBmb3IgKGNvbnN0IGNhcmQgb2YgY2FyZHMpIHtcbiAgICAgIGNvbnN0IGVsID0gc3RhdHMuY3JlYXRlRGl2KHsgY2xzOiAnaHlkcmEtc3RhdC1jYXJkJyB9KTtcbiAgICAgIGVsLmNyZWF0ZUVsKCdzcGFuJywgeyB0ZXh0OiBjYXJkLmljb24sIGNsczogJ2h5ZHJhLXN0YXQtaWNvbicgfSk7XG4gICAgICBlbC5jcmVhdGVFbCgnc3BhbicsIHsgdGV4dDogU3RyaW5nKGNhcmQudmFsdWUpLCBjbHM6ICdoeWRyYS1zdGF0LXZhbHVlJyB9KTtcbiAgICAgIGVsLmNyZWF0ZUVsKCdzcGFuJywgeyB0ZXh0OiBjYXJkLmxhYmVsLCBjbHM6ICdoeWRyYS1zdGF0LWxhYmVsJyB9KTtcbiAgICB9XG5cbiAgICAvLyBQQVJBIGJyZWFrZG93blxuICAgIGlmIChyLnBhcmEubGVuZ3RoID4gMCkge1xuICAgICAgY29uc3QgcGFyYSA9IGNvbnRhaW5lci5jcmVhdGVEaXYoeyBjbHM6ICdoeWRyYS1wYXJhJyB9KTtcbiAgICAgIHBhcmEuY3JlYXRlRWwoJ2RpdicsIHsgdGV4dDogJ1BBUkEgQlJFQUtET1dOJywgY2xzOiAnaHlkcmEtc2VjdGlvbi10aXRsZScgfSk7XG4gICAgICBmb3IgKGNvbnN0IHAgb2Ygci5wYXJhLnNsaWNlKDAsIDYpKSB7XG4gICAgICAgIGNvbnN0IHJvdyA9IHBhcmEuY3JlYXRlRGl2KHsgY2xzOiAnaHlkcmEtcGFyYS1yb3cnIH0pO1xuICAgICAgICByb3cuY3JlYXRlRWwoJ3NwYW4nLCB7IHRleHQ6IHAuY2F0ZWdvcnksIGNsczogJ2h5ZHJhLXBhcmEtY2F0JyB9KTtcbiAgICAgICAgcm93LmNyZWF0ZUVsKCdzcGFuJywgeyB0ZXh0OiBTdHJpbmcocC5jb3VudCksIGNsczogJ2h5ZHJhLXBhcmEtY291bnQnIH0pO1xuICAgICAgfVxuICAgIH1cbiAgfVxuXG4gIHByaXZhdGUgcmVuZGVyU3VnZ2VzdGlvbnMoY29udGFpbmVyOiBIVE1MRWxlbWVudCkge1xuICAgIGNvbnN0IHMgPSB0aGlzLmN1cnJlbnRTdWdnZXN0aW9ucyE7XG4gICAgY29uc3Qgc2VjdGlvbiA9IGNvbnRhaW5lci5jcmVhdGVEaXYoeyBjbHM6ICdoeWRyYS1zdWdnZXN0aW9ucycgfSk7XG4gICAgc2VjdGlvbi5jcmVhdGVFbCgnZGl2JywgeyB0ZXh0OiAnU1VHR0VTVEVEIFRBR1MnLCBjbHM6ICdoeWRyYS1zZWN0aW9uLXRpdGxlJyB9KTtcblxuICAgIGZvciAoY29uc3QgdGFnIG9mIHMucmVzdWx0LnRhZ3MpIHtcbiAgICAgIGNvbnN0IGNoaXAgPSBzZWN0aW9uLmNyZWF0ZURpdih7IGNsczogJ2h5ZHJhLXRhZy1jaGlwJyB9KTtcbiAgICAgIGNoaXAuY3JlYXRlRWwoJ3NwYW4nLCB7IHRleHQ6ICcjJywgY2xzOiAnaHlkcmEtdGFnLWhhc2gnIH0pO1xuICAgICAgY2hpcC5jcmVhdGVFbCgnc3BhbicsIHsgdGV4dDogdGFnIH0pO1xuICAgICAgY2hpcC5vbkNsaWNrRXZlbnQoKCkgPT4ge1xuICAgICAgICB0aGlzLmFwcGx5VGFnKHMuZmlsZSwgdGFnKTtcbiAgICAgICAgY2hpcC5hZGRDbGFzcygnaHlkcmEtdGFnLWFwcGxpZWQnKTtcbiAgICAgIH0pO1xuICAgIH1cblxuICAgIGlmIChzLnJlc3VsdC53aWtpbGlua3MubGVuZ3RoID4gMCkge1xuICAgICAgc2VjdGlvbi5jcmVhdGVFbCgnZGl2JywgeyB0ZXh0OiAnV0lLSUxJTktTJywgY2xzOiAnaHlkcmEtc2VjdGlvbi10aXRsZScgfSk7XG4gICAgICBmb3IgKGNvbnN0IGxpbmsgb2Ygcy5yZXN1bHQud2lraWxpbmtzKSB7XG4gICAgICAgIGNvbnN0IGVsID0gc2VjdGlvbi5jcmVhdGVEaXYoeyBjbHM6ICdoeWRyYS13aWtpbGluaycgfSk7XG4gICAgICAgIGVsLmNyZWF0ZUVsKCdzcGFuJywgeyB0ZXh0OiAnW1snLCBjbHM6ICdoeWRyYS1saW5rLWJyYWNrZXQnIH0pO1xuICAgICAgICBlbC5jcmVhdGVFbCgnc3BhbicsIHsgdGV4dDogbGluayB9KTtcbiAgICAgICAgZWwuY3JlYXRlRWwoJ3NwYW4nLCB7IHRleHQ6ICddXScsIGNsczogJ2h5ZHJhLWxpbmstYnJhY2tldCcgfSk7XG4gICAgICB9XG4gICAgfVxuICB9XG5cbiAgcHJpdmF0ZSByZW5kZXJSZWxhdGlvbnNoaXBzKGNvbnRhaW5lcjogSFRNTEVsZW1lbnQpIHtcbiAgICBjb25zdCByZWxzID0gdGhpcy5jdXJyZW50UmVsYXRpb25zaGlwcyE7XG4gICAgY29uc3Qgc2VjdGlvbiA9IGNvbnRhaW5lci5jcmVhdGVEaXYoeyBjbHM6ICdoeWRyYS1yZWxhdGlvbnNoaXBzJyB9KTtcbiAgICBzZWN0aW9uLmNyZWF0ZUVsKCdkaXYnLCB7IHRleHQ6ICdSRUxBVElPTlNISVBTJywgY2xzOiAnaHlkcmEtc2VjdGlvbi10aXRsZScgfSk7XG5cbiAgICBmb3IgKGNvbnN0IHJlbCBvZiByZWxzLnJlbGF0aW9uc2hpcHMpIHtcbiAgICAgIGNvbnN0IGVsID0gc2VjdGlvbi5jcmVhdGVEaXYoeyBjbHM6ICdoeWRyYS1yZWwtcm93JyB9KTtcbiAgICAgIGVsLmNyZWF0ZUVsKCdzcGFuJywgeyB0ZXh0OiByZWwudHlwZSwgY2xzOiAnaHlkcmEtcmVsLXR5cGUnIH0pO1xuICAgICAgZWwuY3JlYXRlRWwoJ3NwYW4nLCB7IHRleHQ6ICdcdTIxOTInLCBjbHM6ICdoeWRyYS1yZWwtYXJyb3cnIH0pO1xuICAgICAgZWwuY3JlYXRlRWwoJ3NwYW4nLCB7IHRleHQ6IHJlbC50YXJnZXQsIGNsczogJ2h5ZHJhLXJlbC10YXJnZXQnIH0pO1xuICAgIH1cbiAgfVxuXG4gIHByaXZhdGUgcmVuZGVyVGFnU3VnZ2VzdGlvbnModGFnczogc3RyaW5nW10pIHtcbiAgICBjb25zdCBjb250YWluZXIgPSB0aGlzLmNvbnRlbnRFbDtcbiAgICBjb250YWluZXIuZW1wdHkoKTtcbiAgICBjb250YWluZXIuYWRkQ2xhc3MoJ2h5ZHJhLXNpZGViYXInKTtcblxuICAgIGNvbnRhaW5lci5jcmVhdGVFbCgnZGl2JywgeyB0ZXh0OiAnU1VHR0VTVEVEIFRBR1MnLCBjbHM6ICdoeWRyYS1zZWN0aW9uLXRpdGxlJyB9KTtcbiAgICBmb3IgKGNvbnN0IHRhZyBvZiB0YWdzKSB7XG4gICAgICBjb25zdCBjaGlwID0gY29udGFpbmVyLmNyZWF0ZURpdih7IGNsczogJ2h5ZHJhLXRhZy1jaGlwJyB9KTtcbiAgICAgIGNoaXAuY3JlYXRlRWwoJ3NwYW4nLCB7IHRleHQ6ICcjJywgY2xzOiAnaHlkcmEtdGFnLWhhc2gnIH0pO1xuICAgICAgY2hpcC5jcmVhdGVFbCgnc3BhbicsIHsgdGV4dDogdGFnIH0pO1xuICAgIH1cbiAgfVxuXG4gIHByaXZhdGUgcmVuZGVyQWN0aW9ucyhjb250YWluZXI6IEhUTUxFbGVtZW50KSB7XG4gICAgY29uc3QgYWN0aW9ucyA9IGNvbnRhaW5lci5jcmVhdGVEaXYoeyBjbHM6ICdoeWRyYS1hY3Rpb25zJyB9KTtcblxuICAgIGNvbnN0IHNjYW5CdG4gPSBhY3Rpb25zLmNyZWF0ZUVsKCdidXR0b24nLCB7IHRleHQ6ICdTY2FuIFZhdWx0JywgY2xzOiAnaHlkcmEtYnRuJyB9KTtcbiAgICBzY2FuQnRuLm9uQ2xpY2tFdmVudCgoKSA9PiB0aGlzLnBsdWdpbi5zY2FuVmF1bHQoKSk7XG5cbiAgICBjb25zdCBoZWFsdGhCdG4gPSBhY3Rpb25zLmNyZWF0ZUVsKCdidXR0b24nLCB7IHRleHQ6ICdIZWFsdGgnLCBjbHM6ICdoeWRyYS1idG4nIH0pO1xuICAgIGhlYWx0aEJ0bi5vbkNsaWNrRXZlbnQoKCkgPT4gdGhpcy5wbHVnaW4uc2hvd0hlYWx0aCgpKTtcbiAgfVxuXG4gIHByaXZhdGUgYXN5bmMgYXBwbHlUYWcoZmlsZTogVEZpbGUsIHRhZzogc3RyaW5nKSB7XG4gICAgY29uc3QgY29udGVudCA9IGF3YWl0IHRoaXMuYXBwLnZhdWx0LnJlYWQoZmlsZSk7XG4gICAgLy8gQ2hlY2sgaWYgdGFnIGFscmVhZHkgZXhpc3RzXG4gICAgaWYgKGNvbnRlbnQudG9Mb3dlckNhc2UoKS5pbmNsdWRlcyhgIyR7dGFnLnRvTG93ZXJDYXNlKCl9YCkpIHJldHVybjtcblxuICAgIC8vIEFkZCB0byBmcm9udG1hdHRlciBvciBhcHBlbmRcbiAgICBpZiAoY29udGVudC5zdGFydHNXaXRoKCctLS0nKSkge1xuICAgICAgY29uc3QgZW5kID0gY29udGVudC5pbmRleE9mKCdcXG4tLS0nLCAzKTtcbiAgICAgIGlmIChlbmQgPiAwKSB7XG4gICAgICAgIGNvbnN0IHVwZGF0ZWQgPSBjb250ZW50LnN1YnN0cmluZygwLCBlbmQpICsgYHRhZ3M6XFxuICAtICR7dGFnfVxcbmAgKyBjb250ZW50LnN1YnN0cmluZyhlbmQpO1xuICAgICAgICBhd2FpdCB0aGlzLmFwcC52YXVsdC5tb2RpZnkoZmlsZSwgdXBkYXRlZCk7XG4gICAgICAgIHJldHVybjtcbiAgICAgIH1cbiAgICB9XG4gICAgYXdhaXQgdGhpcy5hcHAudmF1bHQubW9kaWZ5KGZpbGUsIGNvbnRlbnQgKyBgXFxuXFxuIyR7dGFnfWApO1xuICB9XG59XG4iLCAiaW1wb3J0IHsgSXRlbVZpZXcsIFdvcmtzcGFjZUxlYWYgfSBmcm9tICdvYnNpZGlhbic7XG5pbXBvcnQgdHlwZSBIeWRyYVBsdWdpbiBmcm9tICcuL21haW4nO1xuaW1wb3J0IHR5cGUgeyBIZWFsdGhSZXN1bHQgfSBmcm9tICcuL2JyaWRnZSc7XG5cbmV4cG9ydCBjb25zdCBIRUFMVEhfVklFV19UWVBFID0gJ2h5ZHJhLWhlYWx0aCc7XG5cbmV4cG9ydCBjbGFzcyBIeWRyYUhlYWx0aFZpZXcgZXh0ZW5kcyBJdGVtVmlldyB7XG4gIHBsdWdpbjogSHlkcmFQbHVnaW47XG5cbiAgY29uc3RydWN0b3IobGVhZjogV29ya3NwYWNlTGVhZiwgcGx1Z2luOiBIeWRyYVBsdWdpbikge1xuICAgIHN1cGVyKGxlYWYpO1xuICAgIHRoaXMucGx1Z2luID0gcGx1Z2luO1xuICB9XG5cbiAgZ2V0Vmlld1R5cGUoKTogc3RyaW5nIHsgcmV0dXJuIEhFQUxUSF9WSUVXX1RZUEU7IH1cbiAgZ2V0RGlzcGxheVRleHQoKTogc3RyaW5nIHsgcmV0dXJuICdIeWRyYSBIZWFsdGgnOyB9XG4gIGdldEljb24oKTogc3RyaW5nIHsgcmV0dXJuICdoZWFydC1wdWxzZSc7IH1cblxuICBhc3luYyBvbk9wZW4oKSB7XG4gICAgdGhpcy5yZW5kZXIoKTtcbiAgfVxuXG4gIGFzeW5jIG9uQ2xvc2UoKSB7fVxuXG4gIHNldEhlYWx0aFJlc3VsdChyZXN1bHQ6IEhlYWx0aFJlc3VsdCkge1xuICAgIHRoaXMucmVuZGVyKHJlc3VsdCk7XG4gIH1cblxuICBwcml2YXRlIHJlbmRlcihyZXN1bHQ/OiBIZWFsdGhSZXN1bHQpIHtcbiAgICBjb25zdCBjb250YWluZXIgPSB0aGlzLmNvbnRlbnRFbDtcbiAgICBjb250YWluZXIuZW1wdHkoKTtcbiAgICBjb250YWluZXIuYWRkQ2xhc3MoJ2h5ZHJhLWhlYWx0aCcpO1xuXG4gICAgaWYgKCFyZXN1bHQpIHtcbiAgICAgIGNvbnRhaW5lci5jcmVhdGVFbCgncCcsIHsgdGV4dDogJ1J1biBhIGhlYWx0aCBjaGVjayB0byBzZWUgcmVzdWx0cy4nIH0pO1xuICAgICAgY29uc3QgYnRuID0gY29udGFpbmVyLmNyZWF0ZUVsKCdidXR0b24nLCB7IHRleHQ6ICdSdW4gSGVhbHRoIENoZWNrJywgY2xzOiAnaHlkcmEtYnRuJyB9KTtcbiAgICAgIGJ0bi5vbkNsaWNrRXZlbnQoKCkgPT4gdGhpcy5wbHVnaW4uc2hvd0hlYWx0aCgpKTtcbiAgICAgIHJldHVybjtcbiAgICB9XG5cbiAgICAvLyBPdmVyYWxsIHN0YXR1c1xuICAgIGNvbnN0IGJhbm5lciA9IGNvbnRhaW5lci5jcmVhdGVEaXYoeyBjbHM6IGBoeWRyYS1oZWFsdGgtYmFubmVyIGh5ZHJhLWhlYWx0aC0ke3Jlc3VsdC5zdGF0dXN9YCB9KTtcbiAgICBiYW5uZXIuY3JlYXRlRWwoJ3NwYW4nLCB7IHRleHQ6IHJlc3VsdC5zdGF0dXMudG9VcHBlckNhc2UoKSwgY2xzOiAnaHlkcmEtaGVhbHRoLXN0YXR1cycgfSk7XG4gICAgYmFubmVyLmNyZWF0ZUVsKCdzcGFuJywgeyB0ZXh0OiByZXN1bHQuc3VtbWFyeSwgY2xzOiAnaHlkcmEtaGVhbHRoLXN1bW1hcnknIH0pO1xuXG4gICAgLy8gQ2hlY2tzXG4gICAgZm9yIChjb25zdCBjaGVjayBvZiByZXN1bHQuY2hlY2tzKSB7XG4gICAgICBjb25zdCByb3cgPSBjb250YWluZXIuY3JlYXRlRGl2KHsgY2xzOiBgaHlkcmEtY2hlY2stcm93IGh5ZHJhLWNoZWNrLSR7Y2hlY2suc3RhdHVzfWAgfSk7XG4gICAgICBjb25zdCBpY29uID0gY2hlY2suc3RhdHVzID09PSAnaGVhbHRoeScgPyAnXHUyNzA1JyA6IGNoZWNrLnN0YXR1cyA9PT0gJ3dhcm5pbmcnID8gJ1x1MjZBMFx1RkUwRicgOiAnXHVEODNEXHVERDM0JztcbiAgICAgIHJvdy5jcmVhdGVFbCgnc3BhbicsIHsgdGV4dDogaWNvbiwgY2xzOiAnaHlkcmEtY2hlY2staWNvbicgfSk7XG5cbiAgICAgIGNvbnN0IGluZm8gPSByb3cuY3JlYXRlRGl2KHsgY2xzOiAnaHlkcmEtY2hlY2staW5mbycgfSk7XG4gICAgICBpbmZvLmNyZWF0ZUVsKCdkaXYnLCB7IHRleHQ6IGNoZWNrLm5hbWUsIGNsczogJ2h5ZHJhLWNoZWNrLW5hbWUnIH0pO1xuICAgICAgaW5mby5jcmVhdGVFbCgnZGl2JywgeyB0ZXh0OiBjaGVjay5tZXNzYWdlLCBjbHM6ICdoeWRyYS1jaGVjay1tZXNzYWdlJyB9KTtcblxuICAgICAgY29uc3QgYmFkZ2UgPSByb3cuY3JlYXRlRWwoJ3NwYW4nLCB7IHRleHQ6IGNoZWNrLnN0YXR1cy50b1VwcGVyQ2FzZSgpLCBjbHM6IGBoeWRyYS1jaGVjay1iYWRnZSBoeWRyYS1iYWRnZS0ke2NoZWNrLnN0YXR1c31gIH0pO1xuICAgIH1cbiAgfVxufVxuIl0sCiAgIm1hcHBpbmdzIjogIjs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7QUFBQTtBQUFBO0FBQUE7QUFBQTtBQUFBO0FBQUEsSUFBQUEsbUJBQXFGOzs7QUNDckYsSUFBSSxnQkFBaUc7QUFDckcsSUFBSTtBQUNGLFFBQU0sRUFBRSxTQUFTLElBQUksUUFBUSxlQUFlO0FBQzVDLFFBQU0sRUFBRSxVQUFVLElBQUksUUFBUSxNQUFNO0FBQ3BDLGtCQUFnQixVQUFVLFFBQVE7QUFDcEMsUUFBUTtBQUVSO0FBa0NPLElBQU0sY0FBTixNQUFrQjtBQUFBLEVBQ2Y7QUFBQSxFQUVSLFlBQVksWUFBb0I7QUFDOUIsU0FBSyxhQUFhO0FBQUEsRUFDcEI7QUFBQSxFQUVBLGFBQWEsTUFBYztBQUN6QixTQUFLLGFBQWE7QUFBQSxFQUNwQjtBQUFBO0FBQUEsRUFJQSxNQUFNLEtBQUssV0FBd0M7QUFDakQsVUFBTSxTQUFTLE1BQU0sS0FB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
