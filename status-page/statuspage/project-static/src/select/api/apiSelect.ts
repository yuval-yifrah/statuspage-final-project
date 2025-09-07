import { readableColor } from 'color2k';
import debounce from 'just-debounce-it';
import queryString from 'query-string';
import SlimSelect from 'slim-select';
import { hasUrl, hasExclusions, isTrigger } from '../util';
import { DynamicParamsMap } from './dynamicParams';
import { isStaticParams, isOption } from './types';
import {
  hasMore,
  hasError,
  isTruthy,
  getApiData,
  getElement,
  isApiError,
  replaceAll,
  createElement,
  uniqueByProperty,
  findFirstAdjacent,
} from '../../util';

import type { Stringifiable } from 'query-string';
import type { Option } from 'slim-select/dist/data';
import type { Trigger, PathFilter, ApplyMethod, QueryFilter } from './types';
import { createToast } from "../../lib/toast";

// Empty placeholder option.
const EMPTY_PLACEHOLDER = {
  value: '',
  text: '',
  placeholder: true,
} as Option;

// Attributes which if truthy should render the option disabled.
const DISABLED_ATTRIBUTES = ['occupied'] as string[];

/**
 * Manage a single API-backed select element's state. Each API select element is likely controlled
 * or dynamically updated by one or more other API select (or static select) elements' values.
 */
export class APISelect {
  /**
   * Base `<select/>` DOM element.
   */
  private readonly base: HTMLSelectElement;

  /**
   * Form field name.
   */
  public readonly name: string;

  /**
   * Form field placeholder.
   */
  public readonly placeholder: string;

  /**
   * Empty/placeholder option. Display text is optionally overridden via the `data-empty-option`
   * attribute.
   */
  public readonly emptyOption: Option;

  /**
   * Null option. When `data-null-option` attribute is a string, the value is used to created an
   * option of type `{text: '<value from data-null-option>': 'null'}`.
   */
  public readonly nullOption: Nullable<Option> = null;

  /**
   * Event that will initiate the API call to StatusPage to load option data. By default, the trigger
   * is `'load'`, so data will be fetched when the element renders on the page.
   */
  private readonly trigger: Trigger;

  /**
   * If `true`, a refresh button will be added next to the search/filter `<input/>` element.
   */
  private readonly allowRefresh: boolean = true;

  /**
   * Event to be dispatched when dependent fields' values change.
   */
  private readonly loadEvent: InstanceType<typeof Event>;

  /**
   * Event to be dispatched when the scroll position of this element's optinos list is at the
   * bottom.
   */
  private readonly bottomEvent: InstanceType<typeof Event>;

  /**
   * SlimSelect instance for this element.
   */
  private readonly slim: InstanceType<typeof SlimSelect>;

  /**
   * Post-parsed URL query parameters for API queries.
   */
  private readonly queryParams: QueryFilter = new Map();

  /**
   * API query parameters that should be applied to API queries for this field. This will be
   * updated as other dependent fields' values change. This is a mapping of:
   *
   *     Form Field Names → Object containing:
   *                         - Query parameter key name
   *                         - Query value
   *
   * This is different from `queryParams` in that it tracks all _possible_ related fields and their
   * values, even if they are empty. Further, the keys in `queryParams` correspond to the actual
   * query parameter keys, which are not necessarily the same as the form field names, depending on
   * the model. For example, `tenant_group` would be the field name, but `group_id` would be the
   * query parameter.
   */
  private readonly dynamicParams: DynamicParamsMap = new DynamicParamsMap();

  /**
   * API query parameters that are already known by the server and should not change.
   */
  private readonly staticParams: QueryFilter = new Map();

  /**
   * Mapping of URL template key/value pairs. If this element's URL contains Django template tags
   * (e.g., `{{key}}`), `key` will be added to `pathValue` and the `id_key` form element will be
   * tracked for changes. When the `id_key` element's value changes, the new value will be added
   * to this map. For example, if the template key is `rack`, and the `id_rack` field's value is
   * `1`, `pathValues` would be updated to reflect a `"rack" => 1` mapping. When the query URL is
   * updated, the URL would change from `/dcim/racks/{{rack}}/` to `/dcim/racks/1/`.
   */
  private readonly pathValues: PathFilter = new Map();

  /**
   * Original API query URL passed via the `data-href` attribute from the server. This is kept so
   * that the URL can be reconstructed as form values change.
   */
  private readonly url: string = '';

  /**
   * API query URL. This will be updated dynamically to include any query parameters in `queryParameters`.
   */
  private queryUrl: string = '';

  /**
   * Scroll position of options is at the bottom of the list, or not. Used to determine if
   * additional options should be fetched from the API.
   */
  private atBottom: boolean = false;

  /**
   * API URL for additional options, if applicable. `null` indicates no options remain.
   */
  private more: Nullable<string> = null;

  /**
   * Array of options values which should be considered disabled or static.
   */
  private disabledOptions: Array<string> = [];

  /**
   * Array of properties which if truthy on an API object should be considered disabled.
   */
  private disabledAttributes: Array<string> = DISABLED_ATTRIBUTES;

  constructor(base: HTMLSelectElement) {
    // Initialize readonly properties.
    this.base = base;
    this.name = base.name;

    if (hasUrl(base)) {
      const url = base.getAttribute('data-url') as string;
      this.url = url;
      this.queryUrl = url;
    }

    this.loadEvent = new Event(`statuspage.select.onload.${base.name}`);
    this.bottomEvent = new Event(`statuspage.select.atbottom.${base.name}`);

    this.placeholder = this.getPlaceholder();
    this.disabledOptions = this.getDisabledOptions();
    this.disabledAttributes = this.getDisabledAttributes();

    const emptyOption = base.getAttribute('data-empty-option');
    if (isTruthy(emptyOption)) {
      this.emptyOption = {
        text: emptyOption,
        value: '',
      };
    } else {
      this.emptyOption = EMPTY_PLACEHOLDER;
    }

    const nullOption = base.getAttribute('data-null-option');
    if (isTruthy(nullOption)) {
      this.nullOption = {
        text: nullOption,
        value: 'null',
      };
    }

    this.slim = new SlimSelect({
      select: this.base,
      allowDeselect: true,
      deselectLabel: `<i class="mdi mdi-close-circle" style="color:currentColor;"></i>`,
      placeholder: this.placeholder,
      searchPlaceholder: 'Filter',
      onChange: () => this.handleSlimChange(),
    });

    // Don't close on select if multiple select
    if (this.base.multiple) {
      this.slim.config.closeOnSelect = false;
    }

    // Initialize API query properties.
    this.getStaticParams();
    this.getDynamicParams();
    this.getPathKeys();

    // Populate static query parameters.
    for (const [key, value] of this.staticParams.entries()) {
      this.queryParams.set(key, value);
    }

    // Populate dynamic query parameters with any form values that are already known.
    for (const filter of this.dynamicParams.keys()) {
      this.updateQueryParams(filter);
    }

    // Populate dynamic path values with any form values that are already known.
    for (const filter of this.pathValues.keys()) {
      this.updatePathValues(filter);
    }

    this.queryParams.set('brief', [true]);
    this.updateQueryUrl();

    // Initialize element styling.
    this.resetClasses();
    this.setSlimStyles();

    // Initialize controlling elements.
    this.initResetButton();

    // Add the refresh button to the search element.
    this.initRefreshButton();

    // Add dependency event listeners.
    this.addEventListeners();

    // Determine if the fetch trigger has been set.
    const triggerAttr = this.base.getAttribute('data-fetch-trigger');

    // Determine if this element is part of collapsible element.
    const collapse = this.base.closest('.content-container .collapse');

    if (isTrigger(triggerAttr)) {
      this.trigger = triggerAttr;
    } else if (collapse !== null) {
      this.trigger = 'collapse';
    } else {
      this.trigger = 'open';
    }

    switch (this.trigger) {
      case 'collapse':
        if (collapse !== null) {
          // If this element is part of a collapsible element, only load the data when the
          // collapsible element is shown.
          // See: https://getbootstrap.com/docs/5.0/components/collapse/#events
          collapse.addEventListener('show.bs.collapse', () => this.loadData());
          collapse.addEventListener('hide.bs.collapse', () => this.resetOptions());
        }
        break;
      case 'open':
        // If the trigger is 'open', only load API data when the select element is opened.
        this.slim.beforeOpen = () => this.loadData();
        break;
      case 'load':
        // Otherwise, load the data immediately.
        Promise.all([this.loadData()]);
        break;
    }
  }

  /**
   * This instance's available options.
   */
  private get options(): Option[] {
    return this.slim.data.data.filter(isOption);
  }

  /**
   * Apply new options to both the SlimSelect instance and this manager's state.
   */
  private set options(optionsIn: Option[]) {
    let newOptions = optionsIn;
    // Ensure null option is present, if it exists.
    if (this.nullOption !== null) {
      newOptions = [this.nullOption, ...newOptions];
    }
    // Deduplicate options each time they're set.
    const deduplicated = uniqueByProperty(newOptions, 'value');
    // Determine if the new options have a placeholder.
    const hasPlaceholder = typeof deduplicated.find(o => o.value === '') !== 'undefined';
    // Get the placeholder index (note: if there is no placeholder, the index will be `-1`).
    const placeholderIdx = deduplicated.findIndex(o => o.value === '');

    if (hasPlaceholder && placeholderIdx >= 0) {
      // If there is an existing placeholder, replace it.
      deduplicated[placeholderIdx] = this.emptyOption;
    } else {
      // If there is not a placeholder, add one to the front.
      deduplicated.unshift(this.emptyOption);
    }
    this.slim.setData(deduplicated);
  }

  /**
   * Remove all options and reset back to the generic placeholder.
   */
  private resetOptions(): void {
    this.options = [this.emptyOption];
  }

  /**
   * Add or remove a class to the SlimSelect element to match Bootstrap .form-select:disabled styles.
   */
  public disable(): void {
    if (this.slim.slim.singleSelected !== null) {
      if (!this.slim.slim.singleSelected.container.hasAttribute('disabled')) {
        this.slim.slim.singleSelected.container.setAttribute('disabled', '');
      }
    } else if (this.slim.slim.multiSelected !== null) {
      if (!this.slim.slim.multiSelected.container.hasAttribute('disabled')) {
        this.slim.slim.multiSelected.container.setAttribute('disabled', '');
      }
    }
    this.slim.disable();
  }

  /**
   * Add or remove a class to the SlimSelect element to match Bootstrap .form-select:disabled styles.
   */
  public enable(): void {
    if (this.slim.slim.singleSelected !== null) {
      if (this.slim.slim.singleSelected.container.hasAttribute('disabled')) {
        this.slim.slim.singleSelected.container.removeAttribute('disabled');
      }
    } else if (this.slim.slim.multiSelected !== null) {
      if (this.slim.slim.multiSelected.container.hasAttribute('disabled')) {
        this.slim.slim.multiSelected.container.removeAttribute('disabled');
      }
    }
    this.slim.enable();
  }

  /**
   * Add event listeners to this element and its dependencies so that when dependencies change
   * this element's options are updated.
   */
  private addEventListeners(): void {
    // Create a debounced function to fetch options based on the search input value.
    const fetcher = debounce((event: Event) => this.handleSearch(event), 300, false);

    // Query the API when the input value changes or a value is pasted.
    this.slim.slim.search.input.addEventListener('keyup', event => {
      // Only search when necessary keys are pressed.
      if (!event.key.match(/^(Arrow|Enter|Tab).*/)) {
        return fetcher(event);
      }
    });
    this.slim.slim.search.input.addEventListener('paste', event => fetcher(event));

    // Watch every scroll event to determine if the scroll position is at bottom.
    this.slim.slim.list.addEventListener('scroll', () => this.handleScroll());

    // When the scroll position is at bottom, fetch additional options.
    this.base.addEventListener(`statuspage.select.atbottom.${this.name}`, () =>
      this.fetchOptions(this.more, 'merge'),
    );

    // When the base select element is disabled or enabled, properly disable/enable this instance.
    this.base.addEventListener(`statuspage.select.disabled.${this.name}`, event =>
      this.handleDisableEnable(event),
    );

    // Create a unique iterator of all possible form fields which, when changed, should cause this
    // element to update its API query.
    // const dependencies = new Set([...this.filterParams.keys(), ...this.pathValues.keys()]);
    const dependencies = new Set([...this.dynamicParams.keys(), ...this.pathValues.keys()]);

    for (const dep of dependencies) {
      const filterElement = document.querySelector(`[name="${dep}"]`);
      if (filterElement !== null) {
        // Subscribe to dependency changes.
        filterElement.addEventListener('change', event => this.handleEvent(event));
      }
      // Subscribe to changes dispatched by this state manager.
      this.base.addEventListener(`statuspage.select.onload.${dep}`, event =>
        this.handleEvent(event),
      );
    }
  }

  /**
   * Load this element's options from the StatusPage API.
   */
  private async loadData(): Promise<void> {
    try {
      this.disable();
      await this.getOptions('replace');
    } catch (err) {
      console.error(err);
    } finally {
      this.setOptionStyles();
      this.enable();
      this.base.dispatchEvent(this.loadEvent);
    }
  }

  /**
   * Get all options from the native select element that are already selected and do not contain
   * placeholder values.
   */
  private getPreselectedOptions(): HTMLOptionElement[] {
    return Array.from(this.base.options)
      .filter(option => option.selected)
      .filter(option => {
        if (option.value === '---------' || option.innerText === '---------') return false;
        return true;
      });
  }

  /**
   * Process a valid API response and add results to this instance's options.
   *
   * @param data Valid API response (not an error).
   */
  private async processOptions(
    data: APIAnswer<APIObjectBase>,
    action: ApplyMethod = 'merge',
  ): Promise<void> {
    // Get all already-selected options.
    const preSelected = this.getPreselectedOptions();

    // Get the values of all already-selected options.
    const selectedValues = preSelected.map(option => option.getAttribute('value')).filter(isTruthy);

    // Build SlimSelect options from all already-selected options.
    const preSelectedOptions = preSelected.map(option => ({
      value: option.value,
      text: option.innerText,
      selected: true,
      disabled: false,
    })) as Option[];

    let options = [] as Option[];

    for (const result of data.results) {
      let text = result.display;

      if (typeof result._depth === 'number' && result._depth > 0) {
        // If the object has a `_depth` property, indent its display text.
        text = `<span class="depth">${'─'.repeat(result._depth)}&nbsp;</span>${text}`;
      }
      const data = {} as Record<string, string>;
      const value = result.id.toString();
      let style, selected, disabled;

      // Set any primitive k/v pairs as data attributes on each option.
      for (const [k, v] of Object.entries(result)) {
        if (!['id', 'slug'].includes(k) && ['string', 'number', 'boolean'].includes(typeof v)) {
          const key = replaceAll(k, '_', '-');
          data[key] = String(v);
        }
        // Set option to disabled if the result contains a matching key and is truthy.
        if (this.disabledAttributes.some(key => key.toLowerCase() === k.toLowerCase())) {
          if (typeof v === 'string' && v.toLowerCase() !== 'false') {
            disabled = true;
          } else if (typeof v === 'boolean' && v === true) {
            disabled = true;
          } else if (typeof v === 'number' && v > 0) {
            disabled = true;
          }
        }
      }

      // Set option to disabled if it is contained within the disabled array.
      if (selectedValues.some(option => this.disabledOptions.includes(option))) {
        disabled = true;
      }

      // Set pre-selected options.
      if (selectedValues.includes(value)) {
        selected = true;
        // If an option is selected, it can't be disabled. Otherwise, it won't be submitted with
        // the rest of the form, resulting in that field's value being deleting from the object.
        disabled = false;
      }

      const option = {
        value,
        text,
        data,
        style,
        selected,
        disabled,
      } as Option;
      options = [...options, option];
    }

    switch (action) {
      case 'merge':
        this.options = [...this.options, ...options];
        break;
      case 'replace':
        this.options = [...preSelectedOptions, ...options];
        break;
    }

    if (hasMore(data)) {
      // If the `next` property in the API response is a URL, there are more options on the server
      // side to be fetched.
      this.more = data.next;
    } else {
      // If the `next` property in the API response is `null`, there are no more options on the
      // server, and no additional fetching needs to occur.
      this.more = null;
    }
  }

  /**
   * Fetch options from the given API URL and add them to the instance.
   *
   * @param url API URL
   */
  private async fetchOptions(url: Nullable<string>, action: ApplyMethod = 'merge'): Promise<void> {
    if (typeof url === 'string') {
      const data = await getApiData(url);

      if (hasError(data)) {
        if (isApiError(data)) {
          return this.handleError(data.exception, data.error);
        }
        return this.handleError(`Error Fetching Options for field '${this.name}'`, data.error);
      }
      await this.processOptions(data, action);
    }
  }

  /**
   * Query the StatusPage API for this element's options.
   */
  private async getOptions(action: ApplyMethod = 'merge'): Promise<void> {
    if (this.queryUrl.includes(`{{`)) {
      this.resetOptions();
      return;
    }
    await this.fetchOptions(this.queryUrl, action);
  }

  /**
   * Query the API for a specific search pattern and add the results to the available options.
   */
  private async handleSearch(event: Event) {
    const { value: q } = event.target as HTMLInputElement;
    const url = queryString.stringifyUrl({ url: this.queryUrl, query: { q } });
    if (!url.includes(`{{`)) {
      await this.fetchOptions(url, 'merge');
      this.slim.data.search(q);
      this.slim.render();
    }
    return;
  }

  /**
   * Determine if the user has scrolled to the bottom of the options list. If so, try to load
   * additional paginated options.
   */
  private handleScroll(): void {
    // Floor scrollTop as chrome can return fractions on some zoom levels.
    const atBottom =
      Math.floor(this.slim.slim.list.scrollTop) + this.slim.slim.list.offsetHeight ===
      this.slim.slim.list.scrollHeight;

    if (this.atBottom && !atBottom) {
      this.atBottom = false;
      this.base.dispatchEvent(this.bottomEvent);
    } else if (!this.atBottom && atBottom) {
      this.atBottom = true;
      this.base.dispatchEvent(this.bottomEvent);
    }
  }

  /**
   * Event handler to be dispatched any time a dependency's value changes. For example, when the
   * value of `tenant_group` changes, `handleEvent` is called to get the current value of
   * `tenant_group` and update the query parameters and API query URL for the `tenant` field.
   */
  private handleEvent(event: Event): void {
    const target = event.target as HTMLSelectElement;
    // Update the element's URL after any changes to a dependency.
    this.updateQueryParams(target.name);
    this.updatePathValues(target.name);
    this.updateQueryUrl();

    // Load new data.
    Promise.all([this.loadData()]);
  }

  /**
   * Event handler to be dispatched when the base select element is disabled or enabled. When that
   * occurs, run the instance's `disable()` or `enable()` methods to synchronize UI state with
   * desired action.
   *
   * @param event Dispatched event matching pattern `statuspage.select.disabled.<name>`
   */
  private handleDisableEnable(event: Event): void {
    const target = event.target as HTMLSelectElement;

    if (target.disabled === true) {
      this.disable();
    } else if (target.disabled === false) {
      this.enable();
    }
  }

  /**
   * When the API returns an error, show it to the user and reset this element's available options.
   *
   * @param title Error title
   * @param message Error message
   */
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  private handleError(title: string, message: string): void {
    createToast('danger', title, message).show();
    this.resetOptions();
  }

  /**
   * `change` event callback to be called any time the value of a SlimSelect instance is changed.
   */
  private handleSlimChange(): void {
    const element = this.slim.slim;
    if (element) {
      // Toggle form validation classes when form values change. For example, if the field was
      // invalid and the value has now changed, remove the `.is-invalid` class.
      if (
        element.container.classList.contains('is-invalid') ||
        this.base.classList.contains('is-invalid')
      ) {
        element.container.classList.remove('is-invalid');
        this.base.classList.remove('is-invalid');
      }
    }
    this.base.dispatchEvent(this.loadEvent);
  }

  /**
   * Update the API query URL and underlying DOM element's `data-url` attribute.
   */
  private updateQueryUrl(): void {
    // Create new URL query parameters based on the current state of `queryParams` and create an
    // updated API query URL.
    const query = {} as Dict<Stringifiable[]>;
    for (const [key, value] of this.queryParams.entries()) {
      query[key] = value;
    }

    let url = this.url;

    // Replace any Django template variables in the URL with values from `pathValues` if set.
    for (const [key, value] of this.pathValues.entries()) {
      for (const result of this.url.matchAll(new RegExp(`({{${key}}})`, 'g'))) {
        if (isTruthy(value)) {
          url = replaceAll(url, result[1], value.toString());
        }
      }
    }
    const newUrl = queryString.stringifyUrl({ url, query });
    if (this.queryUrl !== newUrl) {
      // Only update the URL if it has changed.
      this.queryUrl = newUrl;
      this.base.setAttribute('data-url', newUrl);
    }
  }

  /**
   * Update an element's API URL based on the value of another element on which this element
   * relies.
   *
   * @param fieldName DOM ID of the other element.
   */
  private updateQueryParams(fieldName: string): void {
    // Find the element dependency.
    const element = document.querySelector<HTMLSelectElement>(`[name="${fieldName}"]`);
    if (element !== null) {
      // Initialize the element value as an array, in case there are multiple values.
      let elementValue = [] as Stringifiable[];

      if (element.multiple) {
        // If this is a multi-select (form filters, tags, etc.), use all selected options as the value.
        elementValue = Array.from(element.options)
          .filter(o => o.selected)
          .map(o => o.value);
      } else if (element.value !== '') {
        // If this is single-select (most fields), use the element's value. This seemingly
        // redundant/verbose check is mainly for performance, so we're not running the above three
        // functions (`Array.from()`, `Array.filter()`, `Array.map()`) every time every select
        // field's value changes.
        elementValue = [element.value];
      }

      if (elementValue.length > 0) {
        // If the field has a value, add it to the map.
        this.dynamicParams.updateValue(fieldName, elementValue);
        // Get the updated value.
        const current = this.dynamicParams.get(fieldName);

        if (typeof current !== 'undefined') {
          const { queryParam, queryValue } = current;
          let value = [] as Stringifiable[];

          if (this.staticParams.has(queryParam)) {
            // If the field is defined in `staticParams`, we should merge the dynamic value with
            // the static value.
            const staticValue = this.staticParams.get(queryParam);
            if (typeof staticValue !== 'undefined') {
              value = [...staticValue, ...queryValue];
            }
          } else {
            // If the field is _not_ defined in `staticParams`, we should replace the current value
            // with the new dynamic value.
            value = queryValue;
          }
          if (value.length > 0) {
            this.queryParams.set(queryParam, value);
          } else {
            this.queryParams.delete(queryParam);
          }
        }
      } else {
        // Otherwise, delete it (we don't want to send an empty query like `?site_id=`)
        const queryParam = this.dynamicParams.queryParam(fieldName);
        if (queryParam !== null) {
          this.queryParams.delete(queryParam);
        }
      }
    }
  }

  /**
   * Update `pathValues` based on the form value of another element.
   *
   * @param id DOM ID of the other element.
   */
  private updatePathValues(id: string): void {
    const key = replaceAll(id, /^id_/i, '');
    const element = getElement<HTMLSelectElement>(`id_${key}`);
    if (element !== null) {
      // If this element's URL contains Django template tags ({{), replace the template tag
      // with the the dependency's value. For example, if the dependency is the `rack` field,
      // and the `rack` field's value is `1`, this element's URL would change from
      // `/dcim/racks/{{rack}}/` to `/dcim/racks/1/`.
      const hasReplacement =
        this.url.includes(`{{`) && Boolean(this.url.match(new RegExp(`({{(${id})}})`, 'g')));

      if (hasReplacement) {
        if (isTruthy(element.value)) {
          // If the field has a value, add it to the map.
          this.pathValues.set(id, element.value);
        } else {
          // Otherwise, reset the value.
          this.pathValues.set(id, '');
        }
      }
    }
  }

  /**
   * Find the select element's placeholder text/label.
   */
  private getPlaceholder(): string {
    let placeholder = this.name;
    if (this.base.id) {
      const label = document.querySelector(`label[for="${this.base.id}"]`) as HTMLLabelElement;
      // Set the placeholder text to the label value, if it exists.
      if (label !== null) {
        placeholder = `Select ${label.innerText.trim()}`;
      }
    }
    return placeholder;
  }

  /**
   * Get this element's disabled options by value. The `data-query-param-exclude` attribute will
   * contain a stringified JSON array of option values.
   */
  private getDisabledOptions(): string[] {
    let disabledOptions = [] as string[];
    if (hasExclusions(this.base)) {
      try {
        const exclusions = JSON.parse(
          this.base.getAttribute('data-query-param-exclude') ?? '[]',
        ) as string[];
        disabledOptions = [...disabledOptions, ...exclusions];
      } catch (err) {
        console.group(
          `Unable to parse data-query-param-exclude value on select element '${this.name}'`,
        );
        console.warn(err);
        console.groupEnd();
      }
    }
    return disabledOptions;
  }

  /**
   * Get this element's disabled attribute keys. For example, if `disabled-indicator` is set to
   * `'_occupied'` and an API object contains `{ _occupied: true }`, the option will be disabled.
   */
  private getDisabledAttributes(): string[] {
    let disabled = [...DISABLED_ATTRIBUTES] as string[];
    const attr = this.base.getAttribute('disabled-indicator');
    if (isTruthy(attr)) {
      disabled = [...disabled, attr];
    }
    return disabled;
  }

  /**
   * Parse the `data-url` attribute to add any Django template variables to `pathValues` as keys
   * with empty values. As those keys' corresponding form fields' values change, `pathValues` will
   * be updated to reflect the new value.
   */
  private getPathKeys() {
    for (const result of this.url.matchAll(new RegExp(`{{(.+)}}`, 'g'))) {
      this.pathValues.set(result[1], '');
    }
  }

  /**
   * Determine if a this instances' options should be filtered by the value of another select
   * element.
   *
   * Looks for the DOM attribute `data-dynamic-params`, the value of which is a JSON array of
   * objects containing information about how to handle the related field.
   */
  private getDynamicParams(): void {
    const serialized = this.base.getAttribute('data-dynamic-params');
    try {
      this.dynamicParams.addFromJson(serialized);
    } catch (err) {
      console.group(`Unable to determine dynamic query parameters for select field '${this.name}'`);
      console.warn(err);
      console.groupEnd();
    }
  }

  /**
   * Determine if this instance's options should be filtered by static values passed from the
   * server.
   *
   * Looks for the DOM attribute `data-static-params`, the value of which is a JSON array of
   * objects containing key/value pairs to add to `this.staticParams`.
   */
  private getStaticParams(): void {
    const serialized = this.base.getAttribute('data-static-params');

    try {
      if (isTruthy(serialized)) {
        const deserialized = JSON.parse(serialized);
        if (isStaticParams(deserialized)) {
          for (const { queryParam, queryValue } of deserialized) {
            if (Array.isArray(queryValue)) {
              this.staticParams.set(queryParam, queryValue);
            } else {
              this.staticParams.set(queryParam, [queryValue]);
            }
          }
        }
      }
    } catch (err) {
      console.group(`Unable to determine static query parameters for select field '${this.name}'`);
      console.warn(err);
      console.groupEnd();
    }
  }

  /**
   * Set the underlying select element to the same size as the SlimSelect instance. This is
   * primarily for built-in HTML form validation (which doesn't really work) but it also makes
   * things feel cleaner in the DOM.
   */
  private setSlimStyles(): void {
    const { width, height } = this.slim.slim.container.getBoundingClientRect();
    this.base.style.opacity = '0';
    this.base.style.width = `${width}px`;
    this.base.style.height = `${height}px`;
    this.base.style.display = 'block';
    this.base.style.position = 'absolute';
    this.base.style.pointerEvents = 'none';
  }

  /**
   * Add scoped style elements specific to each SlimSelect option, if the color property exists.
   * As of this writing, this attribute only exist on Tags. The color property is used as the
   * background color, and a foreground color is detected based on the luminosity of the background
   * color.
   */
  private setOptionStyles(): void {
    for (const option of this.options) {
      // Only create style elements for options that contain a color attribute.
      if (
        'data' in option &&
        'id' in option &&
        typeof option.data !== 'undefined' &&
        typeof option.id !== 'undefined' &&
        'color' in option.data
      ) {
        const id = option.id as string;
        const data = option.data as { color: string };

        // Create the style element.
        const style = document.createElement('style');

        // Append hash to color to make it a valid hex color.
        const bg = `#${data.color}`;
        // Detect the foreground color.
        const fg = readableColor(bg);

        // Add a unique identifier to the style element.
        style.setAttribute('data-statuspage', id);

        // Scope the CSS to apply both the list item and the selected item.
        style.innerHTML = replaceAll(
          `
  div.ss-values div.ss-value[data-id="${id}"],
  div.ss-list div.ss-option:not(.ss-disabled)[data-id="${id}"]
   {
    background-color: ${bg} !important;
    color: ${fg} !important;
  }
              `,
          '\n',
          '',
        ).trim();

        // Add the style element to the DOM.
        document.head.appendChild(style);
      }
    }
  }

  /**
   * Remove base element classes from SlimSelect instance.
   */
  private resetClasses(): void {
    const element = this.slim.slim;
    if (element) {
      for (const className of this.base.classList) {
        element.container.classList.remove(className);
      }
    }
  }

  /**
   * Initialize any adjacent reset buttons so that when clicked, the page is reloaded without
   * query parameters.
   */
  private initResetButton(): void {
    const resetButton = findFirstAdjacent<HTMLButtonElement>(
      this.base,
      'button[data-reset-select]',
    );
    if (resetButton !== null) {
      resetButton.addEventListener('click', () => {
        window.location.assign(window.location.origin + window.location.pathname);
      });
    }
  }

  /**
   * Add a refresh button to the search container element. When clicked, the API data will be
   * reloaded.
   */
  private initRefreshButton(): void {
    if (this.allowRefresh) {
      const refreshButton = createElement(
        'button',
        { type: 'button' },
        ['btn', 'btn-sm', 'btn-ghost-dark'],
        [createElement('i', null, ['mdi', 'mdi-reload'])],
      );
      refreshButton.addEventListener('click', () => this.loadData());
      refreshButton.type = 'button';
      this.slim.slim.search.container.appendChild(refreshButton);
    }
  }
}
