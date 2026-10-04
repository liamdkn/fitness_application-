#!/usr/bin/env node
/*
 * Applies the SQL files in supabase/migrations/ to the database, in order,
 * once each, and remembers which it has run in a `schema_migrations` table -
 * so a fresh database and an old one both end up at the same place.
 *
 *   cd scripts && npm install
 *   node migrate.js status      what's applied and what's waiting
 *   node migrate.js up          apply everything waiting (each file in its own transaction)
 *   node migrate.js baseline    record every file as already applied, WITHOUT running it
 *                               (for a database that was set up by hand up to now)
 *   node migrate.js up --to=0070  stop after that migration
 *
 * DATABASE_URL comes from supabase/.env (or the environment). A migration that
 * fails is rolled back and nothing after it runs.
 *
 * Migrations are applied exactly as written, so they must not rely on being
 * re-run: write new ones as new files, never edit one that has been applied.
 */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
require('dotenv').config({ path: path.join(__dirname, '..', 'supabase', '.env') });
const { Client } = require('pg');

const dir = path.join(__dirname, '..', 'supabase', 'migrations');

function files() {
  return fs.readdirSync(dir).filter((f) => /^\d+.*\.sql$/.test(f)).sort();
}

function checksum(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(path.join(dir, file))).digest('hex');
}

async function main() {
  const [command = 'status', ...rest] = process.argv.slice(2);
  const to = (rest.find((a) => a.startsWith('--to=')) || '').slice(5);
  if (!process.env.DATABASE_URL) throw new Error('DATABASE_URL is not set (supabase/.env)');

  const client = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await client.connect();
  try {
    await client.query(`
      create table if not exists schema_migrations (
        version text primary key,
        checksum text not null,
        applied_at timestamptz not null default now()
      )`);
    const applied = new Map((await client.query('select version, checksum from schema_migrations')).rows.map((r) => [r.version, r.checksum]));
    const all = files();

    // A migration edited after it was applied is a problem worth shouting about.
    for (const file of all) {
      if (applied.has(file) && applied.get(file) !== checksum(file) && applied.get(file) !== 'baseline') {
        console.warn(`warning: ${file} has changed since it was applied`);
      }
    }
    const waiting = all.filter((f) => !applied.has(f));

    if (command === 'status') {
      for (const file of all) console.log(`${applied.has(file) ? 'applied' : 'WAITING'}  ${file}`);
      console.log(`\n${applied.size} applied, ${waiting.length} waiting`);
    } else if (command === 'baseline') {
      for (const file of waiting) {
        await client.query('insert into schema_migrations (version, checksum) values ($1, $2)', [file, checksum(file)]);
      }
      console.log(`Recorded ${waiting.length} migrations as applied (not run).`);
    } else if (command === 'up') {
      let count = 0;
      for (const file of waiting) {
        if (to && file.slice(0, to.length) > to) break;
        const sql = fs.readFileSync(path.join(dir, file), 'utf8');
        process.stdout.write(`applying ${file} ... `);
        try {
          await client.query('begin');
          await client.query(sql);
          await client.query('insert into schema_migrations (version, checksum) values ($1, $2)', [file, checksum(file)]);
          await client.query('commit');
          console.log('ok');
          count++;
        } catch (error) {
          await client.query('rollback');
          console.log('FAILED');
          throw new Error(`${file}: ${error.message}`);
        }
      }
      console.log(`${count} applied.`);
    } else {
      throw new Error(`unknown command "${command}" (status, up, baseline)`);
    }
  } finally {
    await client.end();
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
