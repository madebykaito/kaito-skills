export const noop = {
  cloud: true,
  prepareAheadMs: 20 * 60 * 1000,
  prepare({ ref }, { now }) {
    return { id: `noop-prepared-${ref}`, expiresAt: now() + 60 * 60 * 1000 };
  },
  publish({ ref }, { preparedId }) {
    if (globalThis.process?.env.KAITO_TEST_NOOP_CRASH === '1') process.kill(process.pid, 'SIGKILL');
    return { result: 'ok', remoteId: preparedId ?? `noop-${ref}` };
  },
};
