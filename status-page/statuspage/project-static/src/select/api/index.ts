import { getElements } from '../../util';
import { APISelect } from './apiSelect';

export function initApiSelect(): void {
  for (const select of getElements<HTMLSelectElement>('.statuspage-api-select')) {
    new APISelect(select);
  }
}

export type { Trigger } from './types';
