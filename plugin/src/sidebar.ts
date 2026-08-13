import { ItemView, WorkspaceLeaf, TFile } from 'obsidian';
import type HydraPlugin from './main';
import type { ScanResult, ClassifyResult, RelationshipResult } from './bridge';

export const SIDEBAR_VIEW_TYPE = 'hydra-sidebar';

export class HydraSidebarView extends ItemView {
  plugin: HydraPlugin;
  private scanResult: ScanResult | null = null;
  private currentSuggestions: { file: TFile; result: ClassifyResult } | null = null;
  private currentRelationships: RelationshipResult | null = null;

  constructor(leaf: WorkspaceLeaf, plugin: HydraPlugin) {
    super(leaf);
    this.plugin = plugin;
  }

  getViewType(): string { return SIDEBAR_VIEW_TYPE; }
  getDisplayText(): string { return 'Hydra'; }
  getIcon(): string { return 'droplet'; }

  async onOpen() {
    this.render();
  }

  async onClose() {}

  // MARK: - Updates

  updateScanResult(result: ScanResult) {
    this.scanResult = result;
    this.render();
  }

  updateSuggestions(file: TFile, result: ClassifyResult) {
    this.currentSuggestions = { file, result };
    this.render();
  }

  showTagSuggestions(tags: string[]) {
    this.renderTagSuggestions(tags);
  }

  showRelationships(rels: RelationshipResult) {
    this.currentRelationships = rels;
    this.render();
  }

  // MARK: - Rendering

  private render() {
    const container = this.contentEl;
    container.empty();
    container.addClass('hydra-sidebar');

    // Header
    const header = container.createDiv({ cls: 'hydra-header' });
    header.createEl('span', { text: 'Hydra', cls: 'hydra-logo' });
    header.createEl('span', { text: 'Context Hydration', cls: 'hydra-tagline' });

    // Stats
    if (this.scanResult) {
      this.renderStats(container);
    }

    // Suggestions
    if (this.currentSuggestions) {
      this.renderSuggestions(container);
    }

    // Relationships
    if (this.currentRelationships) {
      this.renderRelationships(container);
    }

    // Actions
    this.renderActions(container);
  }

  private renderStats(container: HTMLElement) {
    const r = this.scanResult!;
    const stats = container.createDiv({ cls: 'hydra-stats' });

    const cards = [
      { label: 'Notes', value: r.notes, icon: '📄' },
      { label: 'Tags', value: r.tags, icon: '🏷️' },
      { label: 'Orphaned', value: r.orphaned, icon: '👻' },
      { label: 'Broken', value: r.brokenLinks, icon: '🔗' },
    ];

    for (const card of cards) {
      const el = stats.createDiv({ cls: 'hydra-stat-card' });
      el.createEl('span', { text: card.icon, cls: 'hydra-stat-icon' });
      el.createEl('span', { text: String(card.value), cls: 'hydra-stat-value' });
      el.createEl('span', { text: card.label, cls: 'hydra-stat-label' });
    }

    // PARA breakdown
    if (r.para.length > 0) {
      const para = container.createDiv({ cls: 'hydra-para' });
      para.createEl('div', { text: 'PARA BREAKDOWN', cls: 'hydra-section-title' });
      for (const p of r.para.slice(0, 6)) {
        const row = para.createDiv({ cls: 'hydra-para-row' });
        row.createEl('span', { text: p.category, cls: 'hydra-para-cat' });
        row.createEl('span', { text: String(p.count), cls: 'hydra-para-count' });
      }
    }
  }

  private renderSuggestions(container: HTMLElement) {
    const s = this.currentSuggestions!;
    const section = container.createDiv({ cls: 'hydra-suggestions' });
    section.createEl('div', { text: 'SUGGESTED TAGS', cls: 'hydra-section-title' });

    for (const tag of s.result.tags) {
      const chip = section.createDiv({ cls: 'hydra-tag-chip' });
      chip.createEl('span', { text: '#', cls: 'hydra-tag-hash' });
      chip.createEl('span', { text: tag });
      chip.onClickEvent(() => {
        this.applyTag(s.file, tag);
        chip.addClass('hydra-tag-applied');
      });
    }

    if (s.result.wikilinks.length > 0) {
      section.createEl('div', { text: 'WIKILINKS', cls: 'hydra-section-title' });
      for (const link of s.result.wikilinks) {
        const el = section.createDiv({ cls: 'hydra-wikilink' });
        el.createEl('span', { text: '[[', cls: 'hydra-link-bracket' });
        el.createEl('span', { text: link });
        el.createEl('span', { text: ']]', cls: 'hydra-link-bracket' });
      }
    }
  }

  private renderRelationships(container: HTMLElement) {
    const rels = this.currentRelationships!;
    const section = container.createDiv({ cls: 'hydra-relationships' });
    section.createEl('div', { text: 'RELATIONSHIPS', cls: 'hydra-section-title' });

    for (const rel of rels.relationships) {
      const el = section.createDiv({ cls: 'hydra-rel-row' });
      el.createEl('span', { text: rel.type, cls: 'hydra-rel-type' });
      el.createEl('span', { text: '→', cls: 'hydra-rel-arrow' });
      el.createEl('span', { text: rel.target, cls: 'hydra-rel-target' });
    }
  }

  private renderTagSuggestions(tags: string[]) {
    const container = this.contentEl;
    container.empty();
    container.addClass('hydra-sidebar');

    container.createEl('div', { text: 'SUGGESTED TAGS', cls: 'hydra-section-title' });
    for (const tag of tags) {
      const chip = container.createDiv({ cls: 'hydra-tag-chip' });
      chip.createEl('span', { text: '#', cls: 'hydra-tag-hash' });
      chip.createEl('span', { text: tag });
    }
  }

  private renderActions(container: HTMLElement) {
    const actions = container.createDiv({ cls: 'hydra-actions' });

    const scanBtn = actions.createEl('button', { text: 'Scan Vault', cls: 'hydra-btn' });
    scanBtn.onClickEvent(() => this.plugin.scanVault());

    const healthBtn = actions.createEl('button', { text: 'Health', cls: 'hydra-btn' });
    healthBtn.onClickEvent(() => this.plugin.showHealth());
  }

  private async applyTag(file: TFile, tag: string) {
    const content = await this.app.vault.read(file);
    // Check if tag already exists
    if (content.toLowerCase().includes(`#${tag.toLowerCase()}`)) return;

    // Add to frontmatter or append
    if (content.startsWith('---')) {
      const end = content.indexOf('\n---', 3);
      if (end > 0) {
        const updated = content.substring(0, end) + `tags:\n  - ${tag}\n` + content.substring(end);
        await this.app.vault.modify(file, updated);
        return;
      }
    }
    await this.app.vault.modify(file, content + `\n\n#${tag}`);
  }
}
