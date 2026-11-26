import { LATE_MS } from './protocol.mjs';
import { STALE_MS } from '../handlers/contract.mjs';

export function d1Queue(db) {
  const query = (sql, ...args) => db.prepare(sql).bind(...args);
  return {
    async enqueue(job) {
      await query('INSERT INTO jobs (ref, digest, body, signature, due_at) VALUES (?, ?, ?, ?, ?) ON CONFLICT(ref) DO NOTHING',
        job.ref, job.digest, job.body, job.signature, job.due_at).run();
    },
    async status(ref) {
      return query('SELECT digest, state, remote_id FROM jobs WHERE ref = ?', ref).first();
    },
    async sweep(now) {
      await query("UPDATE jobs SET state = 'uncertain', body = '', signature = '' WHERE state = 'claimed' AND claimed_at <= ?", now - STALE_MS).run();
      await query("UPDATE jobs SET state = 'failed', body = '', signature = '' WHERE state = 'queued' AND due_at < ?", now - LATE_MS).run();
    },
    async due(now) {
      const result = await query("SELECT * FROM jobs WHERE state = 'queued' AND due_at <= ? ORDER BY due_at, ref LIMIT 50", now).all();
      return result.results;
    },
    async upcoming(now, lead) {
      const result = await query(`SELECT * FROM jobs WHERE state = 'queued' AND due_at > ? AND due_at <= ?
        AND (prepared_at IS NULL OR (prepared_at <= ? AND coalesce(prepared_until, 0) <= due_at))
        ORDER BY due_at, ref LIMIT 50`, now, now + lead, now - STALE_MS).all();
      return result.results;
    },
    async reservePreparation(ref, at) {
      const result = await query(`UPDATE jobs SET prepared_at = ?, prepared_id = NULL, prepared_until = NULL
        WHERE ref = ? AND state = 'queued' AND due_at > ?
        AND (prepared_at IS NULL OR (prepared_at <= ? AND coalesce(prepared_until, 0) <= due_at))`, at, ref, at, at - STALE_MS).run();
      return result.meta.changes === 1;
    },
    async prepared(ref, at, id, until) {
      await query('UPDATE jobs SET prepared_id = ?, prepared_until = ? WHERE ref = ? AND prepared_at = ? AND state = ?', id, until, ref, at, 'queued').run();
    },
    async claim(ref, now) {
      return query(`UPDATE jobs SET state = 'claimed', claimed_at = ? WHERE ref = ? AND state = 'queued'
        AND due_at <= ? AND due_at >= ? RETURNING prepared_id, prepared_until`, now, ref, now, now - LATE_MS).first();
    },
    async finish(ref, { result, remoteId }) {
      await query("UPDATE jobs SET state = ?, remote_id = ?, body = '', signature = '' WHERE ref = ? AND state = 'claimed'", result, remoteId, ref).run();
    },
  };
}
