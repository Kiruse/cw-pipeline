import { recase } from '@kristiandupont/recase';
import fs from 'fs/promises';
import path from 'path';

export async function tryStat(path: string) {
  try {
    return await fs.stat(path);
  } catch (e) {
    return null;
  }
}

export const isFile = (path: string) => tryStat(path).then(stat => !!stat?.isFile()).catch(() => false);
export const isDir  = (path: string) => tryStat(path).then(stat => !!stat?.isDirectory()).catch(() => false);

export async function getFiles(dir: string) {
  if ((await fs.stat(dir)).isFile()) {
    return [dir];
  }

  const files: string[] = [];
  const recurse = async (dir: string) => {
    const entries = await fs.readdir(dir, { withFileTypes: true });
    for (const entry of entries) {
      if (entry.isDirectory()) {
        await recurse(`${dir}/${entry.name}`);
      } else {
        files.push(`${dir}/${entry.name}`);
      }
    }
  };
  await recurse(dir);
  return files;
}

export const mkdirs = async (dirs: string[]) => await Promise.all(dirs.map(dir => fs.mkdir(dir, { recursive: true })));

/** If it's a file, copy `src` to `dest`. If it's a directory, copy its contents to `dest` recursively. */
export async function copy(src: string, dest: string, predicate: (file: string) => boolean = () => true) {
  const stat = await fs.stat(src);
  if (stat.isDirectory()) {
    const files = await getFiles(src).then(files => files.map(file => path.relative(src, file)));
    const dirs = Array.from(new Set(files.map(file => `${dest}/${path.dirname(file)}`)));
    await mkdirs(dirs);
    await Promise.all(files.map(async file => {
      if (predicate(file)) {
        await fs.copyFile(`${src}/${file}`, `${dest}/${file}`);
      }
    }));
  } else {
    await fs.mkdir(path.dirname(dest), { recursive: true });
    if (predicate(src)) {
      await fs.copyFile(src, dest);
    }
  }
}
export const move = (src: string, dest: string) => fs.rename(src, dest);

export async function substitutePlaceholders(dir: string, data: Record<string, string>) {
  const extensions = ['.toml', '.rs', '.md']
  const files = await getFiles(dir);
  const filteredFiles = files.filter(file => extensions.some(ext => file.endsWith(ext)));
  await Promise.all(filteredFiles.map(async file => {
    let content = await fs.readFile(file, 'utf8');
    for (const [key, val] of Object.entries(data)) {
      content = content.replace(new RegExp(`\\{\\{${key}\\}\\}`, 'g'), val);
    }
    await fs.writeFile(file, content);
  }));
}

export function getSection(contents: string, section: string) {
  const lines = contents.split('\n');
  const start = lines.findIndex(line => line.trim().startsWith(`[${section}]`));
  const end = lines.slice(start + 1).findIndex(line => line.trim().startsWith('['));
  return lines.slice(start + 1, end > -1 ? start + end : undefined).join('\n'); // skip first line which is the [section]
}

export function getWorkspaceDeps(contents: string) {
  const lines = getSection(contents, 'workspace.dependencies').split('\n').filter((line) => !!line.trim());
  return lines.map(line => line.split('=', 2).shift()!.trim())
    .map(dep => `${dep}.workspace = true`)
    .join('\n');
}

export const toCrateName = (dir: string) => recase('mixed', 'snake')(path.basename(dir)).replace(/\s+/g, '_');

export async function getCrateName(dir: string) {
  const contents = await fs.readFile(`${dir}/Cargo.toml`, 'utf8');
  const section = getSection(contents, 'package');
  const lines = section.split('\n');
  const nameLine = lines.find(line => line.startsWith('name ='));
  if (!nameLine) {
    throw new Error('No name found in Cargo.toml');
  }
  return toCrateName(nameLine.split('=', 3)[1].trim().replaceAll('"', ''));
}
