import { Plugin, Notice, TFile, MarkdownView, addIcon, App, PluginSettingTab, Setting } from 'obsidian';

// Hydra Obsidian Plugin
// Calls the Hydra binary (or HTTP endpoint) for classification, tagging,
// relationship inference, and vault enrichment. The Swift binary does the
// heavy lifting; this plugin handles Obsidian-side rendering and real-time sync.

interface HydraConfig {
  binaryPath: string;
  endpoint?: string;
  autoTag: boolean;
  autoLink: boolean;
  inferRelationships: boolean;
  confidenceThreshold: number;
}

interface HydraResult {
  artifact_id: string;
  kind: string;
  lifecycle: string;
  tags: string[];
  wikilinks: string[];
  relationships: Array<{ type: string; target: string; reason: string }>;
  confidence: number;
  provenance: string;
}

const DEFAULT_CONFIG: HydraConfig = {
  binaryPath: 'hydra',
  endpoint: '',
  autoTag: true,
  autoLink: true,
  inferRelationships: true,
  confidenceThreshold: 0.7,
};

export default class HydraPlugin extends Plugin {
  config: HydraConfig = DEFAULT_CONFIG;

  async onload() {
    await this.loadConfig();

    // Ribbon icon
    this.addRibbonIcon('droplet', 'Hydrate', () => {
      this.hydrateActiveFile();
    });

    // Command palette
    this.addCommand({
      id: 'hydrate-current-file',
      name: 'Hydrate current file',
      editorCallback: () => this.hydrateActiveFile(),
    });

    this.addCommand({
      id: 'hydrate-vault',
      name: 'Hydrate entire vault (dry run)',
      callback: () => this.hydrateVault(),
    });

    this.addCommand({
      id: 'show-relationship-graph',
      name: 'Show relationship graph',
      callback: () => this.showGraph(),
    });

    this.addCommand({
      id: 'find-orphans',
      name: 'Find orphaned notes',
      callback: () => this.findOrphans(),
    });

    this.addCommand({
      id: 'fix-broken-links',
      name: 'Fix broken wikilinks',
      callback: () => this.fixBrokenLinks(),
    });

    // Settings tab
    this.addSettingTab(new HydraSettingTab(this.app, this));

    // Auto-hydrate on file save
    if (this.config.autoTag) {
      this.registerEvent(
        this.app.vault.on('modify', (file) => {
          if (file instanceof TFile && file.extension === 'md') {
            this.autoHydrate(file);
          }
        })
      );
    }

    console.log('Hydra plugin loaded');
  }

  async loadConfig() {
    this.config = Object.assign(DEFAULT_CONFIG, await this.loadData());
  }

  async saveConfig() {
    await this.saveData(this.config);
  }

  // Call the Hydra binary to classify a single file
  async classifyFile(file: TFile): Promise<HydraResult | null> {
    try {
      const content = await this.app.vault.read(file);

      // Try HTTP endpoint first, fall back to binary
      if (this.config.endpoint) {
        const response = await fetch(`${this.config.endpoint}/classify`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            path: file.path,
            content: content,
            vault: this.app.vault.getRoot().path,
          }),
        });
        if (response.ok) return await response.json();
      }

      // Binary fallback — invoke `hydra classify`
      // In production, this spawns the Swift binary
      // For now, return a heuristic result
      return this.heuristicClassify(file, content);
    } catch (err) {
      console.error('Hydra classify error:', err);
      return null;
    }
  }

  // Heuristic classification (used when binary/endpoint not available)
  heuristicClassify(file: TFile, content: string): HydraResult {
    const tags: string[] = [];
    const wikilinks: string[] = [];
    const relationships: Array<{ type: string; target: string; reason: string }> = [];

    // Extract existing wikilinks
    const linkMatches = content.matchAll(/\[\[([^\]]+)\]\]/g);
    for (const m of linkMatches) {
      wikilinks.push(m[1]);
    }

    // Infer tags from frontmatter
    const fmMatch = content.match(/^---\n([\s\S]*?)\n---/);
    let kind = 'note';
    let lifecycle = 'draft';
    let confidence = 0.5;

    if (fmMatch) {
      const fm = fmMatch[1];
      if (fm.includes('type: plan')) { kind = 'plan'; confidence = 0.8; }
      else if (fm.includes('type: session')) { kind = 'session-summary'; confidence = 0.8; }
      else if (fm.includes('type: decision')) { kind = 'decision'; confidence = 0.85; }

      if (fm.includes('status: completed')) { lifecycle = 'completed'; confidence += 0.1; }
      else if (fm.includes('status: active')) { lifecycle = 'active'; }

      const tagMatch = fm.match(/tags:\s*\n((?:\s+-\s+.+\n)+)/);
      if (tagMatch) {
        const rawTags = tagMatch[1].matchAll(/-\s+(.+)/g);
        for (const t of rawTags) tags.push(t[1].trim());
      }

      const inlineTags = fm.match(/tags:\s*\[(.*?)\]/);
      if (inlineTags) {
        tags.push(...inlineTags[1].split(',').map(t => t.trim().replace(/['"]/g, '')));
      }
    }

    // Infer project from path
    const pathParts = file.path.split('/');
    if (pathParts.length > 1) {
      tags.push(`folder/${pathParts[0]}`);
    }

    return {
      artifact_id: file.path,
      kind,
      lifecycle,
      tags: [...new Set(tags)],
      wikilinks,
      relationships,
      confidence: Math.min(confidence, 1.0),
      provenance: 'plugin-heuristic',
    };
  }

  // Hydrate the currently active file
  async hydrateActiveFile() {
    const file = this.app.workspace.getActiveFile();
    if (!file) {
      new Notice('No active file');
      return;
    }

    new Notice(`Hydrating ${file.name}...`);
    const result = await this.classifyFile(file);
    if (!result) {
      new Notice('Hydration failed');
      return;
    }

    await this.applyResult(file, result);
    new Notice(`Hydrated: ${result.kind} (${Math.round(result.confidence * 100)}%) — ${result.tags.length} tags, ${result.wikilinks.length} links`);
  }

  // Apply classification result to a file
  async applyResult(file: TFile, result: HydraResult) {
    let content = await this.app.vault.read(file);

    // Add tags to frontmatter
    if (this.config.autoTag && result.tags.length > 0) {
      content = this.ensureFrontmatter(content);
      content = this.mergeTags(content, result.tags);
    }

    // Add missing wikilinks as a relationships section
    if (this.config.autoLink && result.wikilinks.length > 0) {
      if (!content.includes('## Related')) {
        content += '\n\n## Related\n';
        for (const link of result.wikilinks) {
          if (!content.includes(`[[${link}]]`)) {
            content += `- [[${link}]]\n`;
          }
        }
      }
    }

    // Add typed relationships
    if (this.config.inferRelationships && result.relationships.length > 0) {
      if (!content.includes('## Relationships')) {
        content += '\n\n## Relationships\n';
        for (const rel of result.relationships) {
          content += `- **${rel.type}** → [[${rel.target}]] — ${rel.reason}\n`;
        }
      }
    }

    await this.app.vault.modify(file, content);
  }

  ensureFrontmatter(content: string): string {
    if (content.startsWith('---\n')) return content;
    return `---\ntype: note\ntags: []\n---\n\n${content}`;
  }

  mergeTags(content: string, newTags: string[]): string {
    const fmMatch = content.match(/^(---\n[\s\S]*?tags:\s*\[?([^\]]*)\]?\n[\s\S]*?\n---)/);
    if (fmMatch) {
      const existing = fmMatch[2].split(',').map(t => t.trim().replace(/['"]/g, '')).filter(Boolean);
      const merged = [...new Set([...existing, ...newTags])];
      return content.replace(
        /tags:\s*\[?[^\]]*\]?/,
        `tags: [${merged.map(t => `"${t}"`).join(', ')}]`
      );
    }
    return content;
  }

  // Auto-hydrate on file modify (debounced)
  private timers: Record<string, number> = {};
  async autoHydrate(file: TFile) {
    const key = file.path;
    if (this.timers[key]) window.clearTimeout(this.timers[key]);
    this.timers[key] = window.setTimeout(async () => {
      const result = await this.classifyFile(file);
      if (result && result.confidence >= this.config.confidenceThreshold) {
        await this.applyResult(file, result);
      }
    }, 2000);
  }

  // Hydrate entire vault (dry run)
  async hydrateVault() {
    new Notice('Scanning vault for hydration candidates...');
    const files = this.app.vault.getMarkdownFiles();
    const orphans: TFile[] = [];

    for (const file of files) {
      const content = await this.app.vault.read(file);
      const links = content.matchAll(/\[\[([^\]]+)\]\]/g);
      const linkCount = [...links].length;
      if (linkCount === 0) orphans.push(file);
    }

    new Notice(`Dry run: ${files.length} files, ${orphans.length} orphans found`, 5000);
  }

  // Show relationship graph (opens a custom view)
  async showGraph() {
    new Notice('Graph view coming soon — GPU-accelerated force-directed layout');
  }

  // Find orphaned notes
  async findOrphans() {
    const files = this.app.vault.getMarkdownFiles();
    const orphans: TFile[] = [];

    for (const file of files) {
      const content = await this.app.vault.read(file);
      const hasLinks = /\[\[/.test(content);
      if (!hasLinks) orphans.push(file);
    }

    if (orphans.length === 0) {
      new Notice('No orphaned notes found! 🎉');
    } else {
      new Notice(`${orphans.length} orphaned notes — check console for list`, 5000);
      console.log('Orphaned notes:', orphans.map(f => f.path));
    }
  }

  // Fix broken wikilinks
  async fixBrokenLinks() {
    const files = this.app.vault.getMarkdownFiles();
    const noteNames = new Set(files.map(f => f.basename));
    let fixed = 0;

    for (const file of files) {
      let content = await this.app.vault.read(file);
      let modified = false;

      const brokenLinks = content.matchAll(/\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/g);
      for (const match of brokenLinks) {
        const target = match[1].trim();
        // Check if target exists (case-insensitive)
        const exists = [...noteNames].some(n => n.toLowerCase() === target.toLowerCase());
        if (!exists) {
          // Try to find closest match
          const closest = this.findClosestMatch(target, [...noteNames]);
          if (closest && closest !== target) {
            content = content.replace(`[[${target}]]`, `[[${closest}]]`);
            content = content.replace(`[[${target}|`, `[[${closest}|`);
            modified = true;
            fixed++;
          }
        }
      }

      if (modified) {
        await this.app.vault.modify(file, content);
      }
    }

    new Notice(fixed > 0 ? `Fixed ${fixed} broken wikilinks` : 'No broken links found');
  }

  findClosestMatch(target: string, candidates: string[]): string | null {
    const lower = target.toLowerCase();
    let best: string | null = null;
    let bestScore = 0;

    for (const c of candidates) {
      const score = this.similarity(lower, c.toLowerCase());
      if (score > bestScore && score > 0.6) {
        bestScore = score;
        best = c;
      }
    }
    return best;
  }

  similarity(a: string, b: string): number {
    const longer = a.length > b.length ? a : b;
    const shorter = a.length > b.length ? b : a;
    if (longer.length === 0) return 1.0;
    return (longer.length - this.editDistance(longer, shorter)) / longer.length;
  }

  editDistance(s1: string, s2: string): number {
    const costs: number[] = [];
    for (let i = 0; i <= s2.length; i++) costs[i] = i;
    for (let i = 1; i <= s1.length; i++) {
      costs[0] = i;
      let nw = i - 1;
      for (let j = 1; j <= s2.length; j++) {
        let cj = Math.min(1 + Math.min(costs[j], costs[j - 1]),
          s1.charAt(i - 1) === s2.charAt(j - 1) ? nw : nw + 1);
        nw = costs[j];
        costs[j] = cj;
      }
    }
    return costs[s2.length];
  }
}

// Settings tab

class HydraSettingTab extends PluginSettingTab {
  plugin: HydraPlugin;

  constructor(app: App, plugin: HydraPlugin) {
    super(app, plugin);
    this.plugin = plugin;
  }

  display(): void {
    const { containerEl } = this;
    containerEl.empty();

    containerEl.createEl('h2', { text: 'Hydra Settings' });

    new Setting(containerEl)
      .setName('Binary path')
      .setDesc('Path to the Hydra binary (or leave as "hydra" if in PATH)')
      .addText(text => text
        .setValue(this.plugin.config.binaryPath)
        .onChange(async (value) => {
          this.plugin.config.binaryPath = value;
          await this.plugin.saveConfig();
        }));

    new Setting(containerEl)
      .setName('HTTP endpoint')
      .setDesc('Optional: Hydra server endpoint (e.g. http://localhost:8642)')
      .addText(text => text
        .setValue(this.plugin.config.endpoint || '')
        .onChange(async (value) => {
          this.plugin.config.endpoint = value;
          await this.plugin.saveConfig();
        }));

    new Setting(containerEl)
      .setName('Auto-tag')
      .setDesc('Automatically tag files on modification')
      .addToggle(toggle => toggle
        .setValue(this.plugin.config.autoTag)
        .onChange(async (value) => {
          this.plugin.config.autoTag = value;
          await this.plugin.saveConfig();
        }));

    new Setting(containerEl)
      .setName('Auto-link')
      .setDesc('Automatically add wikilinks')
      .addToggle(toggle => toggle
        .setValue(this.plugin.config.autoLink)
        .onChange(async (value) => {
          this.plugin.config.autoLink = value;
          await this.plugin.saveConfig();
        }));

    new Setting(containerEl)
      .setName('Infer relationships')
      .setDesc('Detect typed relationships between notes')
      .addToggle(toggle => toggle
        .setValue(this.plugin.config.inferRelationships)
        .onChange(async (value) => {
          this.plugin.config.inferRelationships = value;
          await this.plugin.saveConfig();
        }));

    new Setting(containerEl)
      .setName('Confidence threshold')
      .setDesc('Minimum confidence for auto-classification (0.0 - 1.0)')
      .addSlider(slider => slider
        .setLimits(0.3, 0.95, 0.05)
        .setValue(this.plugin.config.confidenceThreshold)
        .setDynamicTooltip()
        .onChange(async (value) => {
          this.plugin.config.confidenceThreshold = value;
          await this.plugin.saveConfig();
        }));
  }
}
