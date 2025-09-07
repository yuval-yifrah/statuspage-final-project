import collections
import inspect

import django_rq
from packaging import version

from django.apps import AppConfig
from django.core.exceptions import ImproperlyConfigured
from django.template.loader import get_template

from extras.registry import registry

from extras.plugins.utils import import_object
from queuing.apps import get_func_name

# Initialize plugin registry
registry['plugins'] = {
    'menu_items': {},
    'preferences': {},
    'template_extensions': collections.defaultdict(list),
}


#
# Plugin AppConfig class
#

class PluginConfig(AppConfig):
    """
    Subclass of Django's built-in AppConfig class, to be used for Status-Page plugins.
    """
    # Plugin metadata
    author = ''
    author_email = ''
    description = ''
    version = ''

    # Root URL path under /plugins. If not set, the plugin's label will be used.
    base_url = None

    # Minimum/maximum compatible versions of Status-Page
    min_version = None
    max_version = None

    # Default configuration parameters
    default_settings = {}

    # Mandatory configuration parameters
    required_settings = []

    # Middleware classes provided by the plugin
    middleware = []

    # Django-rq queues dedicated to the plugin
    queues = []

    # Default integration paths. Plugin authors can override these to customize the paths to
    # integrated components.
    menu_items = 'navigation.menu_items'
    template_extensions = 'template_content.template_extensions'
    user_preferences = 'preferences.preferences'
    schedules = 'queuing.schedules'

    def ready(self):
        plugin_name = self.name.rsplit('.', 1)[-1]

        # Register template content (if defined)
        template_extensions = import_object(f"{self.__module__}.{self.template_extensions}")
        if template_extensions is not None:
            register_template_extensions(template_extensions)

        # Register navigation menu items (if defined)
        menu_items = import_object(f"{self.__module__}.{self.menu_items}")
        if menu_items is not None:
            register_menu_items(self.verbose_name, menu_items)

        # Register user preferences (if defined)
        user_preferences = import_object(f"{self.__module__}.{self.user_preferences}")
        if user_preferences is not None:
            register_user_preferences(plugin_name, user_preferences)

        # Register schedules (if defined)
        schedules = import_object(f"{self.__module__}.{self.schedules}")
        if schedules is not None:
            register_schedules(plugin_name, schedules)

    @classmethod
    def validate(cls, user_config, statuspage_version):

        # Enforce version constraints
        current_version = version.parse(statuspage_version)
        if cls.min_version is not None:
            min_version = version.parse(cls.min_version)
            if current_version < min_version:
                raise ImproperlyConfigured(
                    f"Plugin {cls.__module__} requires Status-Page minimum version {cls.min_version}."
                )
        if cls.max_version is not None:
            max_version = version.parse(cls.max_version)
            if current_version > max_version:
                raise ImproperlyConfigured(
                    f"Plugin {cls.__module__} requires Status-Page maximum version {cls.max_version}."
                )

        # Verify required configuration settings
        for setting in cls.required_settings:
            if setting not in user_config:
                raise ImproperlyConfigured(
                    f"Plugin {cls.__module__} requires '{setting}' to be present in the PLUGINS_CONFIG section of "
                    f"configuration.py."
                )

        # Apply default configuration values
        for setting, value in cls.default_settings.items():
            if setting not in user_config:
                user_config[setting] = value


#
# Template content injection
#

class PluginTemplateExtension:
    """
    This class is used to register plugin content to be injected into core Status-Page templates. It contains methods
    that are overridden by plugin authors to return template content.

    The `model` attribute on the class defines the which model detail page this class renders content for. It
    should be set as a string in the form '<app_label>.<model_name>'. render() provides the following context data:

    * object - The object being viewed
    * request - The current request
    * settings - Global Status-Page settings
    * config - Plugin-specific configuration parameters
    """
    model = None

    def __init__(self, context):
        self.context = context

    def render(self, template_name, extra_context=None):
        """
        Convenience method for rendering the specified Django template using the default context data. An additional
        context dictionary may be passed as `extra_context`.
        """
        if extra_context is None:
            extra_context = {}
        elif not isinstance(extra_context, dict):
            raise TypeError("extra_context must be a dictionary")

        return get_template(template_name).render({**self.context, **extra_context})

    def left_page(self):
        """
        Content that will be rendered on the left of the detail page view. Content should be returned as an
        HTML string. Note that content does not need to be marked as safe because this is automatically handled.
        """
        raise NotImplementedError

    def right_page(self):
        """
        Content that will be rendered on the right of the detail page view. Content should be returned as an
        HTML string. Note that content does not need to be marked as safe because this is automatically handled.
        """
        raise NotImplementedError

    def full_width_page(self):
        """
        Content that will be rendered within the full width of the detail page view. Content should be returned as an
        HTML string. Note that content does not need to be marked as safe because this is automatically handled.
        """
        raise NotImplementedError

    def buttons(self):
        """
        Buttons that will be rendered and added to the existing list of buttons on the detail page view. Content
        should be returned as an HTML string. Note that content does not need to be marked as safe because this is
        automatically handled.
        """
        raise NotImplementedError


def register_template_extensions(class_list):
    """
    Register a list of PluginTemplateExtension classes
    """
    # Validation
    for template_extension in class_list:
        if not inspect.isclass(template_extension):
            raise TypeError(f"PluginTemplateExtension class {template_extension} was passed as an instance!")
        if not issubclass(template_extension, PluginTemplateExtension):
            raise TypeError(f"{template_extension} is not a subclass of extras.plugins.PluginTemplateExtension!")
        if template_extension.model is None:
            raise TypeError(f"PluginTemplateExtension class {template_extension} does not define a valid model!")

        registry['plugins']['template_extensions'][template_extension.model].append(template_extension)


#
# Navigation menu links
#

class PluginMenuItem:
    """
    This class represents a navigation menu item. This constitutes primary link and its text, but also allows for
    specifying additional link buttons that appear to the right of the item in the van menu.

    Links are specified as Django reverse URL strings.
    Buttons are each specified as a list of PluginMenuButton instances.
    """
    permissions = []

    def __init__(self, link, link_text, permissions=None):
        self.link = link
        self.link_text = link_text
        if permissions is not None:
            if type(permissions) not in (list, tuple):
                raise TypeError("Permissions must be passed as a tuple or list.")
            self.permissions = permissions


def register_menu_items(section_name, class_list):
    """
    Register a list of PluginMenuItem instances for a given menu section (e.g. plugin name)
    """
    # Validation
    for menu_link in class_list:
        if not isinstance(menu_link, PluginMenuItem):
            raise TypeError(f"{menu_link} must be an instance of extras.plugins.PluginMenuItem")

    registry['plugins']['menu_items'][section_name] = class_list


#
# User preferences
#

def register_user_preferences(plugin_name, preferences):
    """
    Register a list of user preferences defined by a plugin.
    """
    registry['plugins']['preferences'][plugin_name] = preferences


#
# Schedules
#

def register_schedules(plugin_name, schedules):
    """
    Register a list of schedules defined by a plugin.
    """
    scheduler = django_rq.get_scheduler('default')
    jobs = list(map(lambda j: j.func_name, scheduler.get_jobs()))

    for method, cron_string in schedules:
        func_name = get_func_name(method)
        if func_name not in jobs:
            scheduler.cron(
                cron_string=cron_string,
                func=method,
                queue_name='default',
            )
