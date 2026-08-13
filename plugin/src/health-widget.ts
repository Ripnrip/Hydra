import { ItemView, WorkspaceLeaf } from 'obsidian';
import type HydraPlugin from './main';
import type { HealthResult } from './bridge';

export const HEALTH_VIEW_TYPE = 'hydra-health';

export class HydraHealthView extends ItemView {
  plugin: HydraPlugin;

  constructor(leaf: WorkspaceLeaf, plugin: HydraPlugin) {
    super(leaf);
    this.plugin = plugin;
  }

  getViewType(): string { return HEALTH_VIEW_TYPE; }
  getDisplayText(): string { return 'Hydra Health'; }
  getIcon(): string { return 'heart-pulse'; }

  async onOpen() {
    this.render();
  }

  async onClose() {}

  setHealthResult(result: HealthResult) {
    this.render(result);
  }

  private render(result?: HealthResult) {
    const container = this.contentEl;
    container.empty();
    container.addClass('hydra-health');

    if (!result) {
      container.createEl('p', { text: 'Run a health check to see results.' });
      const btn = container.createEl('button', { text: 'Run Health Check', cls: 'hydra-btn' });
      btn.onClickEvent(() => this.plugin.showHealth());
      return;
    }

    // Overall status
    const banner = container.createDiv({ cls: `hydra-health-banner hydra-health-${result.status}` });
    banner.createEl('span', { text: result.status.toUpperCase(), cls: 'hydra-health-status' });
    banner.createEl('span', { text: result.summary, cls: 'hydra-health-summary' });

    // Checks
    for (const check of result.checks) {
      const row = container.createDiv({ cls: `hydra-check-row hydra-check-${check.status}` });
      const icon = check.status === 'healthy' ? '✅' : check.status === 'warning' ? '⚠️' : '🔴';
      row.createEl('span', { text: icon, cls: 'hydra-check-icon' });

      const info = row.createDiv({ cls: 'hydra-check-info' });
      info.createEl('div', { text: check.name, cls: 'hydra-check-name' });
      info.createEl('div', { text: check.message, cls: 'hydra-check-message' });

      const badge = row.createEl('span', { text: check.status.toUpperCase(), cls: `hydra-check-badge hydra-badge-${check.status}` });
    }
  }
}
