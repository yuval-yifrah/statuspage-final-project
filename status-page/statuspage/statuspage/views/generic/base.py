from django.shortcuts import render, get_object_or_404
from django.views.generic import View

from utilities.views import ObjectPermissionRequiredMixin


class BaseView(View):
    pass


class BaseTemplateView(BaseView):
    """
    Base view class for reusable generic views.
    Attributes:
        template_name: The name of the HTML template file to render
    """
    template_name = None

    def get(self, request):
        """
        GET request handler. `*args` and `**kwargs` are passed to identify the object being queried.
        Args:
            request: The current request
        """

        return render(request, self.template_name, {
            'request': request,
        })


class BaseObjectView(ObjectPermissionRequiredMixin, View):
    """
    Base view class for reusable generic views.
    Attributes:
        queryset: Django QuerySet from which the object(s) will be fetched
        template_name: The name of the HTML template file to render
    """
    queryset = None
    template_name = None

    def get_object(self, **kwargs):
        """
        Return the object being viewed or modified. The object is identified by an arbitrary set of keyword arguments
        gleaned from the URL, which are passed to `get_object_or_404()`. (Typically, only a primary key is needed.)
        If no matching object is found, return a 404 response.
        """
        return get_object_or_404(self.queryset, **kwargs)

    def get_extra_context(self, request, instance):
        """
        Return any additional context data to include when rendering the template.
        Args:
            request: The current request
            instance: The object being viewed
        """
        return {}


class BaseMultiObjectView(ObjectPermissionRequiredMixin, View):
    """
    Base view class for reusable generic views.
    Attributes:
        queryset: Django QuerySet from which the object(s) will be fetched
        table: The django-tables2 Table class used to render the objects list
        template_name: The name of the HTML template file to render
    """
    queryset = None
    table = None
    template_name = None

    def get_extra_context(self, request):
        """
        Return any additional context data to include when rendering the template.
        Args:
            request: The current request
        """
        return {}
