from contextlib import contextmanager

from django.db.models.signals import m2m_changed, pre_delete, post_save

from extras.signals import handle_changed_object, handle_deleted_object
from statuspage.request_context import set_request


@contextmanager
def change_logging(request):
    """
    Enable change logging by connecting the appropriate signals to their receivers before code is run, and
    disconnecting them afterward.
    :param request: WSGIRequest object with a unique `id` set
    """
    set_request(request)

    # Connect our receivers to the post_save and post_delete signals.
    post_save.connect(handle_changed_object, dispatch_uid='handle_changed_object')
    m2m_changed.connect(handle_changed_object, dispatch_uid='handle_changed_object')
    pre_delete.connect(handle_deleted_object, dispatch_uid='handle_deleted_object')

    yield

    # Disconnect change logging signals. This is necessary to avoid recording any errant
    # changes during test cleanup.
    post_save.disconnect(handle_changed_object, dispatch_uid='handle_changed_object')
    m2m_changed.disconnect(handle_changed_object, dispatch_uid='handle_changed_object')
    pre_delete.disconnect(handle_deleted_object, dispatch_uid='handle_deleted_object')

    # Clear the request from thread-local storage
    set_request(None)
