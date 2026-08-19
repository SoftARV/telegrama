# Entity conversion needs no GTK, so the suite stays fast and headless.
# Named test-entities so its generated C does not collide with the shared
# source, which is also entities.vala. The shared source is named from the root: meson places generated C
# beside the target, and a relative "../" path lands it somewhere it cannot
# then find.
entities_test = executable('test-entities',
  files('test-entities.vala'),
  meson.project_source_root() / 'src' / 'util' / 'entities.vala',
  dependencies: [
    dependency('glib-2.0'),
    dependency('gobject-2.0'),
    dependency('json-glib-1.0'),
  ],
)

test('entities', entities_test)
