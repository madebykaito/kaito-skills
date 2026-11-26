import { noop } from './noop-test.mjs';

// Only handlers that run in both Node and Workers belong here.
export const cloudHandlers = new Map([['noop-test', noop]]);
