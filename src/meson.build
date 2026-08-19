cc = meson.get_compiler('c')

# TDLib ships no pkg-config file.
tdjson_dep = cc.find_library('tdjson', required: true)

# libqrencode does ship a .pc, but meson would then hand valac
# "--pkg libqrencode" and collide with the vapi below, which is named for the
# header rather than the pkg-config module.
qrencode_dep = cc.find_library('qrencode', required: true)

conf = configuration_data()
conf.set('APP_ID', app_id)
conf.set('APP_PATH', app_path)
conf.set('VERSION', meson.project_version())
conf.set('API_ID', get_option('api_id'))
conf.set('API_HASH', get_option('api_hash'))

config_vala = configure_file(
  input: 'config.vala.in',
  output: 'config.vala',
  configuration: conf,
)

blueprint_compiler = find_program('blueprint-compiler')

# One target per file with an explicit output. A single batch-compile target
# writing into a directory is not tracked reliably: other build steps touch
# that directory, so ninja sees the output as newer than the input and
# silently skips regenerating the .ui files.
blueprint_files = {
  'window.ui': 'ui/window.blp',
  'login-view.ui': 'ui/login-view.blp',
  'chat-row.ui': 'ui/chat-row.blp',
  'message-row.ui': 'ui/message-row.blp',
  'chat-view.ui': 'ui/chat-view.blp',
}

blueprints = []
foreach output_name, source_name : blueprint_files
  blueprints += custom_target(output_name,
    input: files(source_name),
    output: output_name,
    command: [blueprint_compiler, 'compile', '--output', '@OUTPUT@', '@INPUT@'],
  )
endforeach

resources = gnome.compile_resources('telegrama-resources',
  'telegrama.gresource.xml',
  source_dir: [meson.current_build_dir(), meson.current_source_dir()],
  dependencies: blueprints,
)

sources = files(
  '../vapi/tdjson.vapi',
  '../vapi/qrencode.vapi',
  'main.vala',
  'application.vala',
  'td/client.vala',
  'model/auth.vala',
  'model/chat.vala',
  'model/chat-list.vala',
  'model/message.vala',
  'model/message-list.vala',
  'model/user-store.vala',
  'ui/window.vala',
  'ui/qr-code.vala',
  'ui/chat-row.vala',
  'ui/message-row.vala',
  'ui/chat-view.vala',
  'ui/login-view.vala',
  'util/keyring.vala',
  'util/dates.vala',
  'util/content.vala',
  'util/entities.vala',
)

executable('telegrama',
  sources, config_vala, resources,
  dependencies: [
    dependency('glib-2.0', version: '>= 2.76'),
    dependency('gobject-2.0'),
    dependency('gio-2.0'),
    dependency('json-glib-1.0'),
    dependency('gtk4', version: '>= 4.10'),
    dependency('libadwaita-1', version: '>= 1.7'),
    dependency('libsecret-1'),
    dependency('cairo'),
    tdjson_dep,
    qrencode_dep,
  ],
  vala_args: ['--gresourcesdir=' + meson.current_build_dir()],
  install: true,
)
