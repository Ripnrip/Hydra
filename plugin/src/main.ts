import { Plugin, WorkspaceLeaf, TFile, Notice, Setting, PluginSettingTab, App } from 'obsidian';
import { HydraBridge } from './bridge';
import { HydraSidebarView, SIDEBAR_VIEW_TYPE } from './sidebar';
import { HydraHealthView, HEALTH_VIEW_TYPE } from './health-widget';

// MARK: - Settings

interface HydraSettings {
  binaryPath: string;
  autoTag: boolean;
  autoLink: boolean;
  confidenceThreshold: number;
  refreshInterval: number;
  enableGraphOverlay: boolean;
}

const DEFAULT_SETTINGS: HydraSettings = {
  binaryPath: '',  // auto-detect if empty
  autoTag: true,
  autoLink: true,
  confidenceThreshold: 0.6,
  refreshInterval: 300,  // seconds
  enableGraphOverlay: true,
};

// MARK: - Plugin

export default class HydraPlugin extends Plugin {
  settings: HydraSettings = DEFAULT_SETTINGS;
  bridge: HydraBridge;
  private refreshTimer: number | null = null;

  async onload() {
    try {
      await this.initializePlugin();
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      new Notice(`Hydra partially failed: ${msg}`, 8000);
      console.error('Hydra onload error:', err);
    }
  }

  private async initializePlugin() {
    await this.loadSettings();

    // Initialize the bridge to the Hydra binary
    this.bridge = new HydraBridge(this.settings.binaryPath || await this.detectBinary());

    // Register views
    this.registerView(SIDEBAR_VIEW_TYPE, (leaf) => new HydraSidebarView(leaf, this));
    this.registerView(HEALTH_VIEW_TYPE, (leaf) => new HydraHealthView(leaf, this));

    // Ribbon icon
    this.addRibbonIcon('droplet', 'Hydra', () => {
      this.activateSidebar();
    });

    // Commands
    this.addCommand({
      id: 'hydra-scan',
      name: 'Scan vault',
      callback: () => this.scanVault(),
    });

    this.addCommand({
      id: 'hydra-hydrate-current',
      name: 'Hydrate current note',
      callback: () => this.hydrateCurrentNote(),
    });

    this.addCommand({
      id: 'hydra-health',
      name: 'Show vault health',
      callback: () => this.showHealth(),
    });

    this.addCommand({
      id: 'hydra-suggest-tags',
      name: 'Suggest tags for current note',
      callback: () => this.suggestTags(),
    });

    this.addCommand({
      id: 'hydra-find-relations',
      name: 'Find relationships for current note',
      callback: () => this.findRelationships(),
    });

    // Settings tab
    this.addSettingTab(new HydraSettingTab(this.app, this));

    // Auto-refresh on note save
    this.registerEvent(
      this.app.vault.on('modify', (file) => {
        if (file instanceof TFile && file.extension === 'md' && this.settings.autoTag) {
          this.hydrateNote(file);
        }
      })
    );

    // Start refresh timer
    this.startRefreshTimer();

    console.log('Hydra plugin loaded');
  }

  onunload() {
    if (this.refreshTimer) {
      window.clearInterval(this.refreshTimer);
    }
  }

  // MARK: - Binary detection

  private async detectBinary(): Promise<string> {
    // Try common locations
    const candidates = [
      '/usr/local/bin/hydra',
      '/opt/homebrew/bin/hydra',
      `${process.env.HOME}/.local/bin/hydra`,
    ];

    let execFileSync: any = null;
    try { execFileSync = require('child_process').execFileSync; } catch {}
    for (const path of candidates) {
      try {
        execFileSync(path, ['--version'], { stdio: 'ignore' });
        return path;
      } catch {
        continue;
      }
    }

    new Notice('Hydra binary not found. Set path in settings.', 5000);
    return 'hydra';
  }

  // MARK: - Actions

  async scanVault() {
    new Notice('Hydra: Scanning vault...');
    try {
      const result = await this.bridge.scan(this.app.vault.adapter.getBasePath());
      new Notice(`Hydra: ${result.notes} notes, ${result.tags} tags, ${result.orphaned} orphaned`);

      // Update sidebar
      const sidebar = this.getSidebar();
      if (sidebar) sidebar.updateScanResult(result);
    } catch (err) {
      new Notice(`Hydra: Scan failed — ${err.message}`);
    }
  }

  async hydrateCurrentNote() {
    const file = this.app.workspace.getActiveFile();
    if (!file || file.extension !== 'md') {
      new Notice('Hydra: Open a markdown file first');
      return;
    }
    await this.hydrateNote(file);
  }

  private async hydrateNote(file: TFile) {
    try {
      const content = await this.app.vault.read(file);
      const suggestions = await this.bridge.classify(file.path, content);

      if (suggestions.tags.length > 0 && this.settings.autoTag) {
        const updated = this.applyTags(content, suggestions.tags);
        if (updated !== content) {
          await this.app.vault.modify(file, updated);
        }
      }

      // Update sidebar with suggestions
      const sidebar = this.getSidebar();
      if (sidebar) sidebar.updateSuggestions(file, suggestions);
    } catch (err) {
      // Silent fail for auto-hydration — don't disrupt writing
      console.warn('Hydra hydration error:', err);
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

  private applyTags(content: string, tags: string[]): string {
    // Add tags to frontmatter or append at end
    if (content.startsWith('---')) {
      const end = content.indexOf('\n---', 3);
      if (end > 0) {
        const frontmatter = content.substring(0, end);
        const hasTags = frontmatter.includes('tags:');
        if (hasTags) {
          // Append to existing tags
          const tagEnd = frontmatter.indexOf('\n', frontmatter.indexOf('tags:'));
          const newTags = tags.map(t => `  - ${t}`).join('\n');
          return content.substring(0, tagEnd + 1) + newTags + content.substring(tagEnd);
        } else {
          // Add tags field
          const tagsField = `tags:\n${tags.map(t => `  - ${t}`).join('\n')}\n`;
          return content.substring(0, end) + tagsField + content.substring(end);
        }
      }
    }
    // No frontmatter — append tags at end
    const tagString = tags.map(t => `#${t}`).join(' ');
    return content + '\n\n' + tagString;
  }

  private startRefreshTimer() {
    if (this.refreshTimer) window.clearInterval(this.refreshTimer);
    this.refreshTimer = window.setInterval(() => {
      this.scanVault();
    }, this.settings.refreshInterval * 1000);
  }

  // MARK: - Sidebar

  private getSidebar(): HydraSidebarView | null {
    const leaves = this.app.workspace.getLeavesOfType(SIDEBAR_VIEW_TYPE);
    return leaves.length > 0 ? leaves[0].view as HydraSidebarView : null;
  }

  private async activateSidebar(): Promise<HydraSidebarView> {
    const existing = this.getSidebar();
    if (existing) return existing;

    const leaf = this.app.workspace.getRightLeaf(false);
    if (!leaf) throw new Error('No sidebar leaf available');
    await leaf.setViewState({ type: SIDEBAR_VIEW_TYPE });
    this.app.workspace.revealLeaf(leaf);
    return leaf.view as HydraSidebarView;
  }

  async loadSettings() {
    this.settings = Object.assign({}, DEFAULT_SETTINGS, await this.loadData());
  }

  async saveSettings() {
    await this.saveData(this.settings);
    this.bridge.updateBinary(this.settings.binaryPath);
    this.startRefreshTimer();
  }
}

// MARK: - Settings Tab

class HydraSettingTab extends PluginSettingTab {
  plugin: HydraPlugin;

  constructor(app: App, plugin: HydraPlugin) {
    super(app, plugin);
    this.plugin = plugin;
  }

  display(): void {
    const { containerEl } = this;
    containerEl.empty();

    containerEl.createEl('h3', { text: 'Hydra Settings' });

    new Setting(containerEl)
      .setName('Binary path')
      .setDesc('Path to the hydra CLI binary')
      .addText(text => text
        .setPlaceholder('Auto-detect')
        .setValue(this.plugin.settings.binaryPath)
        .onChange(async (value) => {
          this.plugin.settings.binaryPath = value;
          await this.plugin.saveSettings();
        }));

    new Setting(containerEl)
      .setName('Auto-tag')
      .setDesc('Automatically add suggested tags when notes are modified')
      .addToggle(toggle => toggle
        .setValue(this.plugin.settings.autoTag)
        .onChange(async (value) => {
          this.plugin.settings.autoTag = value;
          await this.plugin.saveSettings();
        }));

    new Setting(containerEl)
      .setName('Auto-link')
      .setDesc('Automatically suggest wikilinks between related notes')
      .addToggle(toggle => toggle
        .setValue(this.plugin.settings.autoLink)
        .onChange(async (value) => {
          this.plugin.settings.autoLink = value;
          await this.plugin.saveSettings();
        }));

    new Setting(containerEl)
      .setName('Confidence threshold')
      .setDesc('Minimum confidence for auto-classification (0.0–1.0)')
      .addSlider(slider => slider
        .setLimits(0, 1, 0.05)
        .setValue(this.plugin.settings.confidenceThreshold)
        .setDynamicTooltip()
        .onChange(async (value) => {
          this.plugin.settings.confidenceThreshold = value;
          await this.plugin.saveSettings();
        }));

    new Setting(containerEl)
      .setName('Refresh interval')
      .setDesc('Seconds between automatic vault scans')
      .addText(text => text
        .setValue(String(this.plugin.settings.refreshInterval))
        .onChange(async (value) => {
          const num = parseInt(value);
          if (!isNaN(num) && num > 0) {
            this.plugin.settings.refreshInterval = num;
            await this.plugin.saveSettings();
          }
        }));
  }
}
