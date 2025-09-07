from extras.registry import registry
from users.preferences import UserPreference
from utilities.paginator import EnhancedPaginator


def get_page_lengths():
    return [
        (v, str(v)) for v in EnhancedPaginator.default_page_lengths
    ]


PREFERENCES = {

    # User interface
    'ui.colormode': UserPreference(
        label='Color mode',
        choices=(
            ('light', 'Light'),
            ('dark', 'Dark'),
        ),
        default='light',
    ),
    'pagination.per_page': UserPreference(
        label='Page length',
        choices=get_page_lengths(),
        description='The number of objects to display per page',
        coerce=lambda x: int(x)
    ),
    'pagination.placement': UserPreference(
        label='Paginator placement',
        choices=(
            ('bottom', 'Bottom'),
            ('top', 'Top'),
            ('both', 'Both'),
        ),
        description='Where the paginator controls will be displayed relative to a table',
        default='bottom'
    ),

    # Miscellaneous
    'data_format': UserPreference(
        label='Data format',
        choices=(
            ('json', 'JSON'),
            ('yaml', 'YAML'),
        ),
    ),

}

# Register plugin preferences
if registry['plugins']['preferences']:
    plugin_preferences = {}

    for plugin_name, preferences in registry['plugins']['preferences'].items():
        for name, userpreference in preferences.items():
            PREFERENCES[f'plugins.{plugin_name}.{name}'] = userpreference

    PREFERENCES.update(plugin_preferences)
