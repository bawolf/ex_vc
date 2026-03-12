import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const fixturesRoot = path.resolve(__dirname, '../../test/fixtures/upstream/dcb');

const scenarios = [
  {
    id: 'minimal-vc-validation',
    operation: 'validate',
    input: {
      '@context': ['https://www.w3.org/ns/credentials/v2'],
      type: ['VerifiableCredential'],
      issuer: 'did:web:example.com',
      credentialSubject: {id: 'did:key:z6MkwExample'}
    }
  }
];

async function main() {
  const channel = process.argv[2] ?? 'released';

  if(!['released', 'main'].includes(channel)) {
    throw new Error(`unsupported channel: ${channel}`);
  }

  const root = path.join(fixturesRoot, channel);
  const casesDir = path.join(root, 'cases');
  await fs.rm(casesDir, {recursive: true, force: true});
  await fs.mkdir(casesDir, {recursive: true});

  const cases = [];

  for(const scenario of scenarios) {
    const record = {
      id: scenario.id,
      operation: scenario.operation,
      input: scenario.input,
      provenance: {
        sourcePackage: '@digitalbazaar/vc',
        sourceUrl: 'https://www.npmjs.com/package/@digitalbazaar/vc'
      },
      expected: {
        valid: true
      }
    };

    const file = `${scenario.id}.json`;
    await fs.writeFile(path.join(casesDir, file), JSON.stringify(record, null, 2) + '\n');
    cases.push({id: scenario.id, operation: scenario.operation, file});
  }

  const manifest = {
    schemaVersion: 1,
    advisory: channel === 'main',
    channel,
    generatedAt: new Date().toISOString(),
    recorder: {
      name: 'ex_vc_upstream_parity',
      packageManager: 'pnpm'
    },
    packages: {
      '@digitalbazaar/vc': '7.2.0',
      '@digitalbazaar/data-integrity': '2.6.0',
      '@digitalcredentials/sd-jwt-vc': '0.4.0'
    },
    cases
  };

  await fs.writeFile(path.join(root, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});

