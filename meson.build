project('telegrama', ['c', 'vala'],
  version: '0.1.0',
  meson_version: '>= 1.0.0',
  default_options: ['warning_level=1', 'c_std=gnu11'],
)

gnome = import('gnome')

add_project_arguments(
  ['-Wno-unused-variable', '-Wno-unused-but-set-variable', '-Wno-unused-function'],
  language: 'c',
)

app_id = 'dev.miguel.Telegrama'
app_path = '/dev/miguel/Telegrama'

subdir('data')
subdir('src')
subdir('tests')

gnome.post_install(
  gtk_update_icon_cache: true,
  update_desktop_database: true,
  glib_compile_schemas: true,
)
