install_data('dev.miguel.Telegrama.desktop',
  install_dir: get_option('datadir') / 'applications',
)

install_data('dev.miguel.Telegrama.metainfo.xml',
  install_dir: get_option('datadir') / 'metainfo',
)

install_data('icons/hicolor/scalable/apps/dev.miguel.Telegrama.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps',
)

install_data('icons/hicolor/symbolic/apps/dev.miguel.Telegrama-symbolic.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'symbolic' / 'apps',
)

install_data('dev.miguel.Telegrama.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas',
)

# Also compiled into the build dir so the app can run uninstalled with
# GSETTINGS_SCHEMA_DIR pointing at it.
gnome.compile_schemas(depend_files: files('dev.miguel.Telegrama.gschema.xml'))
