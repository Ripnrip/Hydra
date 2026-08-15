// Lazy-load child_process (not available in all bundler contexts)
let execFileAsync: ((cmd: string, args: string[], opts?: any) => Promise<{stdout: string}>) | null = null;
try {
  const { execFile } = require('child_process');
  const { promisify } = require('util');
  execFileAsync = promisify(execFile);
} catch {
  // child_process unavailable — heuristic-only mode
}

export interface ScanResult {
  notes: number;
  tags: number;
  orphaned: number;
  brokenLinks: number;
  missingFrontmatter: number;
  para: { category: string; count: number }[];
}

export interface ClassifyResult {
  tags: string[];
  wikilinks: string[];
  kind: string;
  lifecycle: string;
  confidence: number;
  relationships: { type: string; target: string }[];
}

export interface HealthResult {
  status: string;
  summary: string;
  checks: { name: string; status: string; message: string; count: number }[];
}

export interface RelationshipResult {
  relationships: { type: string; target: string; confidence: number }[];
}

// MARK: - Hydra Binary Bridge

/// Calls the hydra CLI binary for all heavy lifting.
/// The plugin is a thin TypeScript shell — Swift does the work.
export class HydraBridge {
  private binaryPath: string;

  constructor(binaryPath: string) {
    this.binaryPath = binaryPath;
  }

  updateBinary(path: string) {
    this.binaryPath = path;
  }

  // MARK: - Commands

  async scan(vaultPath: string): Promise<ScanResult> {
    const output = await this.run(['scan', '--vault', vaultPath]);
    return this.parseScanOutput(output);
  }

  async health(vaultPath: string): Promise<HealthResult> {
    const output = await this.run(['health', '--vault', vaultPath]);
    return this.parseHealthOutput(output);
  }

  async search(vaultPath: string, query: string, limit: number = 20): Promise<any[]> {
    const output = await this.run(['search', '--vault', vaultPath, '--query', query, '--limit', String(limit)]);
    return this.parseSearchOutput(output);
  }

  async classify(filePath: string, content: string): Promise<ClassifyResult> {
    // Write content to a temp file, run classifier, return results
    // For now, uses heuristic classification from the adapter
    const result = await this.run(['hydrate', '--source', filePath, '--dry-run']);
    return this.parseClassifyOutput(result, content);
  }

  async findRelationships(noteName: string, content: string): Promise<RelationshipResult> {
    // Extract wikilinks and find related notes
    const wikilinks = this.extractWikilinks(content);
    const tags = this.extractTags(content);

    return {
      relationships: [
        ...wikilinks.map(w => ({ type: 'wikilink', target: w, confidence: 1.0 })),
        ...tags.map(t => ({ type: 'tag', target: `#${t}`, confidence: 0.7 })),
      ],
    };
  }

  // MARK: - Binary execution

  private async run(args: string[]): Promise<string> {
    if (!execFileAsync) {
      throw new Error("Binary mode unavailable — using heuristic mode");
    }
    try {
      const { stdout } = await execFileAsync(this.binaryPath, args, {
        maxBuffer: 10 * 1024 * 1024,
        timeout: 30000,
      });
      return stdout;
    } catch (err: any) {
      const msg = err?.message ?? String(err);
      throw new Error(`Hydra binary error: ${msg}`);
    }
  }

  // MARK: - Output parsers

  private parseScanOutput(output: string): ScanResult {
    const result: ScanResult = {
      notes: 0, tags: 0, orphaned: 0, brokenLinks: 0, missingFrontmatter: 0, para: [],
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

    // Parse PARA breakdown
    const paraSection = output.match(/PARA Breakdown:([\s\S]*?)(?=\n\n|\nOrphaned|$)/);
    if (paraSection) {
      const lines = paraSection[1].trim().split('\n');
      for (const line of lines) {
        const match = line.match(/^\s+(\S+)\s+(\d+)/);
        if (match) {
          result.para.push({ category: match[1], count: parseInt(match[2]) });
        }
      }
    }

    return result;
  }

  private parseHealthOutput(output: string): HealthResult {
    const checks: { name: string; status: string; message: string; count: number }[] = [];

    const lines = output.split('\n');
    for (const line of lines) {
      const match = line.match(/[✅⚠️🔴]\s+(.+?)\s{2,}(.+)/);
      if (match) {
        const name = match[1].trim();
        const message = match[2].trim();
        let status = 'healthy';
        if (line.includes('⚠️')) status = 'warning';
        else if (line.includes('🔴')) status = 'critical';
        checks.push({ name, status, message, count: 0 });
      }
    }

    const overallMatch = output.match(/Overall:\s+(\w+)/);
    const summaryMatch = output.match(/Summary:\s+(.+)/);

    return {
      status: overallMatch ? overallMatch[1].toLowerCase() : 'unknown',
      summary: summaryMatch ? summaryMatch[1] : '',
      checks,
    };
  }

  private parseSearchOutput(output: string): any[] {
    const results: any[] = [];
    const lines = output.split('\n');
    for (const line of lines) {
      if (line.trim().startsWith('Found')) continue;
      if (line.trim().startsWith('—')) continue;
      if (line.trim().length < 3) continue;
      // Parse "Title [tags] / path"
      const match = line.match(/^\s+(.+?)(?:\s+\[(.+)\])?\s*$/);
      if (match) {
        results.push({
          title: match[1].trim(),
          tags: match[2] ? match[2].split(', ').map((t: string) => t.trim()) : [],
        });
      }
    }
    return results;
  }

  private parseClassifyOutput(output: string, content: string): ClassifyResult {
    // Fallback: use content-based heuristics if binary doesn't provide classification
    const tags = this.extractTags(content);
    const wikilinks = this.extractWikilinks(content);

    return {
      tags,
      wikilinks,
      kind: 'note',
      lifecycle: 'draft',
      confidence: 0.5,
      relationships: wikilinks.map(w => ({ type: 'references', target: w })),
    };
  }

  // MARK: - Content helpers

  private extractWikilinks(content: string): string[] {
    const matches = content.matchAll(/\[\[([^\]|]+)(?:\|[^\]]+)?\]\]/g);
    return Array.from(matches).map(m => m[1].trim());
  }

  private extractTags(content: string): string[] {
    const tags = new Set<string>();
    // Inline #tags
    const matches = content.matchAll(/(?:^|\s)#([a-zA-Z][a-zA-Z0-9/_-]*)/g);
    for (const match of matches) {
      tags.add(match[1].toLowerCase());
    }
    return Array.from(tags);
  }
}
