from django.contrib.auth.models import Group, User
from django.contrib.contenttypes.models import ContentType
from drf_yasg.utils import swagger_serializer_method
from rest_framework import serializers

from statuspage.api.fields import ContentTypeField
from statuspage.api.serializers import WritableNestedSerializer
from users.models import ObjectPermission, Token

__all__ = [
    'NestedGroupSerializer',
    'NestedObjectPermissionSerializer',
    'NestedTokenSerializer',
    'NestedUserSerializer',
]


class NestedGroupSerializer(WritableNestedSerializer):
    url = serializers.HyperlinkedIdentityField(view_name='users-api:group-detail')

    class Meta:
        model = Group
        fields = ['id', 'url', 'display', 'name']


class NestedUserSerializer(WritableNestedSerializer):
    url = serializers.HyperlinkedIdentityField(view_name='users-api:user-detail')

    class Meta:
        model = User
        fields = ['id', 'url', 'display', 'username']

    def get_display(self, obj):
        if full_name := obj.get_full_name():
            return f"{obj.username} ({full_name})"
        return obj.username


class NestedTokenSerializer(WritableNestedSerializer):
    url = serializers.HyperlinkedIdentityField(view_name='users-api:token-detail')

    class Meta:
        model = Token
        fields = ['id', 'url', 'display', 'key', 'write_enabled']


class NestedObjectPermissionSerializer(WritableNestedSerializer):
    url = serializers.HyperlinkedIdentityField(view_name='users-api:objectpermission-detail')
    object_types = ContentTypeField(
        queryset=ContentType.objects.all(),
        many=True
    )
    groups = serializers.SerializerMethodField(read_only=True)
    users = serializers.SerializerMethodField(read_only=True)

    class Meta:
        model = ObjectPermission
        fields = ['id', 'url', 'display', 'name', 'enabled', 'object_types', 'groups', 'users', 'actions']

    @swagger_serializer_method(serializer_or_field=serializers.ListField)
    def get_groups(self, obj):
        return [g.name for g in obj.groups.all()]

    @swagger_serializer_method(serializer_or_field=serializers.ListField)
    def get_users(self, obj):
        return [u.username for u in obj.users.all()]
