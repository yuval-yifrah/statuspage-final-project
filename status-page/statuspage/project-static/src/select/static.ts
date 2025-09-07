import SlimSelect from 'slim-select';
import { getElements } from '../util';

export function initStaticSelect(): void {
  for (const select of getElements<HTMLSelectElement>('.statuspage-static-select')) {
    if (select !== null) {
      const label = document.querySelector(`label[for="${select.id}"]`) as HTMLLabelElement;

      let placeholder;
      if (label !== null) {
        placeholder = `Select ${label.innerText.trim()}`;
      }

      const instance = new SlimSelect({
        select,
        allowDeselect: true,
        deselectLabel: `<i class="mdi mdi-close-circle"></i>`,
        placeholder,
      });

      // Don't copy classes from select element to SlimSelect instance.
      for (const className of select.classList) {
        instance.slim.container.classList.remove(className);
      }
    }
  }
}
