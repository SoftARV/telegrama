project('telegrama', ['c', 'vala'],
  version: '0.1.0',
  meson_version: '>= 1.0.0',
  default_options: ['warning_level=1', 'c_std=gnu11'],
)

add_project_arguments(
  ['-Wno-unused-variable', '-Wno-unused-but-set-variable', '-Wno-unused-function'],
  language: 'c',
)

app_id = 'dev.miguel.Telegrama'
app_path = '/dev/miguel/Telegrama'

subdir('src')
