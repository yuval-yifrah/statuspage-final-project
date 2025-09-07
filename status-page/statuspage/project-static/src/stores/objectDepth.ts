import { createState } from '../state';

export const objectDepthState = createState<{ hidden: boolean }>(
  { hidden: false },
  { persist: true, key: 'statuspage-object-depth' },
);
