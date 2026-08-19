cc = meson.get_compiler('c')

# TDLib ships no pkg-config file.
tdjson_dep = cc.find_library('tdjson', required: true)

deps = [
  dependency('glib-2.0', version: '>= 2.76'),
  dependency('gobject-2.0'),
  dependency('gio-2.0'),
  dependency('json-glib-1.0'),
  tdjson_dep,
]

conf = configuration_data()
conf.set_quoted('APP_ID', app_id)
conf.set_quoted('APP_PATH', app_path)
conf.set_quoted('VERSION', meson.project_version())
conf.set('API_ID', get_option('api_id'))
conf.set_quoted('API_HASH', get_option('api_hash'))

config_vala = configure_file(
  input: 'config.vala.in',
  output: 'config.vala',
  configuration: conf,
)

sources = files(
  '../vapi/tdjson.vapi',
  'main.vala',
  'td/client.vala',
)

executable('telegrama',
  sources,
  config_vala,
  dependencies: deps,
  install: true,
)
