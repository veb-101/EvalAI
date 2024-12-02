# Generated by Django 2.2.20 on 2024-12-02 17:05

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0002_add_jwt_access_token_model'),
    ]

    operations = [
        migrations.AddField(
            model_name='profile',
            name='confirmed_no_alphabet_affiliation',
            field=models.BooleanField(default=None, help_text='User must confirm that they are not associated with any Alphabet portfolio company'),
        ),
    ]
