from django import forms
from django.contrib.auth.forms import AuthenticationForm, PasswordChangeForm as DjangoPasswordChangeForm
from django.contrib.postgres.forms import SimpleArrayField
from django.utils.safestring import mark_safe
from django_otp.plugins.otp_totp.models import TOTPDevice
from otp_yubikey.models import RemoteYubikeyDevice

from statuspage.formfields import IPNetworkFormField
from statuspage.preferences import PREFERENCES
from users.models import UserConfig, Token
from utilities.forms import TailwindMixin, StaticSelect, DateTimePicker
from utilities.utils import flatten_dict


class LoginForm(AuthenticationForm):
    pass


class PasswordChangeForm(TailwindMixin, DjangoPasswordChangeForm):
    pass


class UserConfigFormMetaclass(forms.models.ModelFormMetaclass):

    def __new__(mcs, name, bases, attrs):

        # Emulate a declared field for each supported user preference
        preference_fields = {}
        for field_name, preference in PREFERENCES.items():
            description = f'{preference.description}<br />' if preference.description else ''
            help_text = f'{description}<code>{field_name}</code>'
            field_kwargs = {
                'label': preference.label,
                'choices': preference.choices,
                'help_text': mark_safe(help_text),
                'coerce': preference.coerce,
                'required': False,
                'widget': StaticSelect,
            }
            preference_fields[field_name] = forms.TypedChoiceField(**field_kwargs)
        attrs.update(preference_fields)

        return super().__new__(mcs, name, bases, attrs)


class UserConfigForm(TailwindMixin, forms.ModelForm, metaclass=UserConfigFormMetaclass):
    fieldsets = (
        ('User Interface', (
            'pagination.per_page',
            'pagination.placement',
            # 'ui.colormode',
        )),
        ('Miscellaneous', (
            'data_format',
        )),
    )
    # List of clearable preferences
    pk = forms.MultipleChoiceField(
        choices=[],
        required=False
    )

    class Meta:
        model = UserConfig
        fields = ()

    def __init__(self, *args, instance=None, **kwargs):

        # Get initial data from UserConfig instance
        initial_data = flatten_dict(instance.data)
        kwargs['initial'] = initial_data

        super().__init__(*args, instance=instance, **kwargs)

        # Compile clearable preference choices
        self.fields['pk'].choices = (
            (f'tables.{table_name}', '') for table_name in instance.data.get('tables', [])
        )

    def save(self, *args, **kwargs):

        # Set UserConfig data
        for pref_name, value in self.cleaned_data.items():
            if pref_name == 'pk':
                continue
            self.instance.set(pref_name, value, commit=False)

        # Clear selected preferences
        for preference in self.cleaned_data['pk']:
            self.instance.clear(preference)

        return super().save(*args, **kwargs)

    @property
    def plugin_fields(self):
        return [
            name for name in self.fields.keys() if name.startswith('plugins.')
        ]


class TokenForm(TailwindMixin, forms.ModelForm):
    key = forms.CharField(
        required=False,
        help_text="If no key is provided, one will be generated automatically."
    )
    allowed_ips = SimpleArrayField(
        base_field=IPNetworkFormField(),
        required=False,
        label='Allowed IPs',
        help_text='Allowed IPv4/IPv6 networks from where the token can be used. Leave blank for no restrictions. '
                  'Example: <code>10.1.1.0/24,192.168.10.16/32,2001:db8:1::/64</code>',
    )

    class Meta:
        model = Token
        fields = [
            'key', 'write_enabled', 'expires', 'description', 'allowed_ips',
        ]
        widgets = {
            'expires': DateTimePicker(),
        }


class TwoFactorDeviceSelectForm(TailwindMixin, forms.Form):
    device_type = forms.ChoiceField(
        # choices=(('totp', 'Time-Based'), ('yubikey', 'Yubikey OTP')),
        choices=(('totp', 'Time-Based'),),
        widget=StaticSelect(),
        label='',
    )


class TwoFactorTOTPForm(TailwindMixin, forms.ModelForm):
    name = forms.CharField()
    device_type = forms.CharField(
        widget=forms.HiddenInput(),
        required=True,
    )

    class Meta:
        model = TOTPDevice
        fields = [
            'name',
        ]


class TwoFactorYubikeyForm(TailwindMixin, forms.ModelForm):
    name = forms.CharField()
    device_type = forms.CharField(
        widget=forms.HiddenInput(),
        required=True,
    )

    class Meta:
        model = RemoteYubikeyDevice
        fields = [
            'name',
        ]
