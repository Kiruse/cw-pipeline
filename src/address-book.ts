import fs from 'fs/promises';
import os from 'os';
import path from 'path';
import YAML from 'yaml';

type AddressBook = {
  [key: string]: {
    address: string;
    note?: string;
  } | undefined;
}

const FILEPATH = path.join(os.homedir(), '.cw-pipeline', 'address-book.yml');

await fs.mkdir(path.dirname(FILEPATH), { recursive: true });

const DATA = await readAddresses();

export default Object.assign({}, DATA, {
  async $save() {
    await fs.writeFile(FILEPATH, YAML.stringify(this.$clean()));
  },
  $clean(): AddressBook {
    return Object.fromEntries(
      Object.entries(this).filter(([key]) => !key.startsWith('$') && !key.startsWith('_'))
    ) as any;
  },
});

async function readAddresses(): Promise<AddressBook> {
  try {
    const content = await fs.readFile(FILEPATH, 'utf-8');
    return YAML.parse(content);
  } catch (error) {
    return {};
  }
}
