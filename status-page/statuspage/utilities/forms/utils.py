import re

from django import forms
from django.forms.models import fields_for_model

from utilities.choices import unpack_grouped_choices
from utilities.querysets import RestrictedQuerySet
from .constants import *

__all__ = (
    'add_blank_choice',
    'expand_alphanumeric_pattern',
    'form_from_model',
    'get_selected_values',
    'parse_alphanumeric_range',
    'parse_numeric_range',
    'restrict_form_fields',
    'parse_csv',
    'validate_csv',
)


def parse_numeric_range(string, base=10):
    """
    Expand a numeric range (continuous or not) into a decimal or
    hexadecimal list, as specified by the base parameter
      '0-3,5' => [0, 1, 2, 3, 5]
      '2,8-b,d,f' => [2, 8, 9, a, b, d, f]
    """
    values = list()
    for dash_range in string.split(','):
        try:
            begin, end = dash_range.split('-')
        except ValueError:
            begin, end = dash_range, dash_range
        try:
            begin, end = int(begin.strip(), base=base), int(end.strip(), base=base) + 1
        except ValueError:
            raise forms.ValidationError(f'Range "{dash_range}" is invalid.')
        values.extend(range(begin, end))
    return list(set(values))


def parse_alphanumeric_range(string):
    """
    Expand an alphanumeric range (continuous or not) into a list.
    'a-d,f' => [a, b, c, d, f]
    '0-3,a-d' => [0, 1, 2, 3, a, b, c, d]
    """
    values = []
    for dash_range in string.split(','):
        try:
            begin, end = dash_range.split('-')
            vals = begin + end
            # Break out of loop if there's an invalid pattern to return an error
            if (not (vals.isdigit() or vals.isalpha())) or (vals.isalpha() and not (vals.isupper() or vals.islower())):
                return []
        except ValueError:
            begin, end = dash_range, dash_range
        if begin.isdigit() and end.isdigit():
            for n in list(range(int(begin), int(end) + 1)):
                values.append(n)
        else:
            # Value-based
            if begin == end:
                values.append(begin)
            # Range-based
            else:
                # Not a valid range (more than a single character)
                if not len(begin) == len(end) == 1:
                    raise forms.ValidationError(f'Range "{dash_range}" is invalid.')
                for n in list(range(ord(begin), ord(end) + 1)):
                    values.append(chr(n))
    return values


def expand_alphanumeric_pattern(string):
    """
    Expand an alphabetic pattern into a list of strings.
    """
    lead, pattern, remnant = re.split(ALPHANUMERIC_EXPANSION_PATTERN, string, maxsplit=1)
    parsed_range = parse_alphanumeric_range(pattern)
    for i in parsed_range:
        if re.search(ALPHANUMERIC_EXPANSION_PATTERN, remnant):
            for string in expand_alphanumeric_pattern(remnant):
                yield "{}{}{}".format(lead, i, string)
        else:
            yield "{}{}{}".format(lead, i, remnant)


def get_selected_values(form, field_name):
    """
    Return the list of selected human-friendly values for a form field
    """
    if not hasattr(form, 'cleaned_data'):
        form.is_valid()
    filter_data = form.cleaned_data.get(field_name)
    field = form.fields[field_name]

    # Non-selection field
    if not hasattr(field, 'choices'):
        return [str(filter_data)]

    # Model choice field
    if type(field.choices) is forms.models.ModelChoiceIterator:
        # If this is a single-choice field, wrap its value in a list
        if not hasattr(filter_data, '__iter__'):
            values = [filter_data]
        else:
            values = filter_data

    else:
        # Static selection field
        choices = unpack_grouped_choices(field.choices)
        if type(filter_data) not in (list, tuple):
            filter_data = [filter_data]  # Ensure filter data is iterable
        values = [
            label for value, label in choices if str(value) in filter_data or None in filter_data
        ]

    # If the field has a `null_option` attribute set and it is selected,
    # add it to the field's grouped choices.
    if getattr(field, 'null_option', None) and None in filter_data:
        values.remove(None)
        values.insert(0, field.null_option)

    return values


def add_blank_choice(choices):
    """
    Add a blank choice to the beginning of a choices list.
    """
    return ((None, '---------'),) + tuple(choices)


def form_from_model(model, fields):
    """
    Return a Form class with the specified fields derived from a model. This is useful when we need a form to be used
    for creating objects, but want to avoid the model's validation (e.g. for bulk create/edit functions). All fields
    are marked as not required.
    """
    form_fields = fields_for_model(model, fields=fields)
    for field in form_fields.values():
        field.required = False

    return type('FormFromModel', (forms.Form,), form_fields)


def restrict_form_fields(form, user, action='view'):
    """
    Restrict all form fields which reference a RestrictedQuerySet. This ensures that users see only permitted objects
    as available choices.
    """
    for field in form.fields.values():
        if hasattr(field, 'queryset') and issubclass(field.queryset.__class__, RestrictedQuerySet):
            field.queryset = field.queryset.restrict(user, action)


def parse_csv(reader):
    """
    Parse a csv_reader object into a headers dictionary and a list of records dictionaries. Raise an error
    if the records are formatted incorrectly. Return headers and records as a tuple.
    """
    records = []
    headers = {}

    # Consume the first line of CSV data as column headers. Create a dictionary mapping each header to an optional
    # "to" field specifying how the related object is being referenced. For example, importing a Device might use a
    # `site.slug` header, to indicate the related site is being referenced by its slug.

    for header in next(reader):
        if '.' in header:
            field, to_field = header.split('.', 1)
            headers[field] = to_field
        else:
            headers[header] = None

    # Parse CSV rows into a list of dictionaries mapped from the column headers.
    for i, row in enumerate(reader, start=1):
        if len(row) != len(headers):
            raise forms.ValidationError(
                f"Row {i}: Expected {len(headers)} columns but found {len(row)}"
            )
        row = [col.strip() for col in row]
        record = dict(zip(headers.keys(), row))
        records.append(record)

    return headers, records


def validate_csv(headers, fields, required_fields):
    """
    Validate that parsed csv data conforms to the object's available fields. Raise validation errors
    if parsed csv data contains invalid headers or does not contain required headers.
    """
    # Validate provided column headers
    for field, to_field in headers.items():
        if field not in fields:
            raise forms.ValidationError(f'Unexpected column header "{field}" found.')
        if to_field and not hasattr(fields[field], 'to_field_name'):
            raise forms.ValidationError(f'Column "{field}" is not a related object; cannot use dots')
        if to_field and not hasattr(fields[field].queryset.model, to_field):
            raise forms.ValidationError(f'Invalid related object attribute for column "{field}": {to_field}')

    # Validate required fields
    for f in required_fields:
        if f not in headers:
            raise forms.ValidationError(f'Required column header "{f}" not found.')
