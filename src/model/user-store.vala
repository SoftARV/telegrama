// Names, colours and avatars for message senders. TDLib sends users as updates
// rather than inline with the messages that mention them, so this fills in as
// they arrive and tells the rows to repaint.
public class Telegrama.UserStore : Object {

    // Used until updateAccentColors arrives, and for ids the palette does not
    // cover. These are Telegram's long-standing seven.
    private const string[] BUILT_IN = {
        "#e17076", "#7bc862", "#e5ca77", "#65aadd", "#a695e7", "#ee7aae", "#6ec9cb"
    };

    public signal void changed (int64 user_id);

    private class Contact {
        public string name = "";
        public string username = "";
        public int accent = -1;
        public int photo_id = 0;
        public Gdk.Paintable? photo = null;
    }

    private class Accent {
        public string light = "";
        public string dark = "";
    }

    public Td.Client client { get; construct; }
    public FileStore files { get; construct; }

    private HashTable<string, Contact> people = new HashTable<string, Contact> (str_hash, str_equal);
    private HashTable<string, Accent> palette = new HashTable<string, Accent> (str_hash, str_equal);

    public UserStore (Td.Client client, FileStore files) {
        Object (client: client, files: files);
    }

    construct {
        client.update.connect ((type, body) => {
            switch (type) {
                case "updateUser":
                    remember (body.get_object_member ("user"));
                    break;
                case "updateAccentColors":
                    remember_palette (body.get_array_member ("colors"));
                    break;
                default:
                    break;
            }
        });
    }

    public string name_for (int64 user_id) {
        var contact = people.lookup (user_id.to_string ());
        return contact == null ? "" : contact.name;
    }

    public string username_for (int64 user_id) {
        var contact = people.lookup (user_id.to_string ());
        return contact == null ? "" : contact.username;
    }

    public Gdk.Paintable? photo_for (int64 user_id) {
        var contact = people.lookup (user_id.to_string ());
        return contact == null ? null : contact.photo;
    }

    // Telegram assigns the colour, so this reads it rather than inventing one.
    // Falls back to the built-in seven while the palette is still on its way.
    public string colour_for (int64 user_id) {
        var contact = people.lookup (user_id.to_string ());
        var accent = contact == null ? -1 : contact.accent;

        if (accent < 0) {
            return BUILT_IN[(int) (user_id.abs () % BUILT_IN.length)];
        }

        var entry = palette.lookup (accent.to_string ());
        if (entry != null) {
            var dark = Adw.StyleManager.get_default ().dark;
            var chosen = dark ? entry.dark : entry.light;
            if (chosen != "") {
                return chosen;
            }
        }

        return BUILT_IN[accent % BUILT_IN.length];
    }

    private void remember (Json.Object user) {
        var id = user.get_int_member ("id");
        var key = id.to_string ();

        var contact = people.lookup (key);
        if (contact == null) {
            contact = new Contact ();
            people.insert (key, contact);
        }

        var first = user.get_string_member ("first_name");
        var last = user.get_string_member ("last_name");
        contact.name = (last == "" ? first : @"$first $last").strip ();

        if (user.has_member ("usernames")) {
            var names = user.get_object_member ("usernames");
            if (names.has_member ("active_usernames")) {
                var active = names.get_array_member ("active_usernames");
                if (active.get_length () > 0) {
                    contact.username = active.get_string_element (0);
                }
            }
        }

        if (user.has_member ("accent_color_id")) {
            contact.accent = (int) user.get_int_member ("accent_color_id");
        }

        if (user.has_member ("profile_photo")) {
            request_photo (key, contact, user.get_object_member ("profile_photo"));
        }

        changed (id);
    }

    private void request_photo (string key, Contact contact, Json.Object photo) {
        if (!photo.has_member ("small")) {
            return;
        }

        var small = photo.get_object_member ("small");
        var file_id = (int) small.get_int_member ("id");
        if (file_id == contact.photo_id && contact.photo != null) {
            return;
        }
        contact.photo_id = file_id;

        fetch_photo.begin (key, contact, small);
    }

    private async void fetch_photo (string key, Contact contact, Json.Object file) {
        var path = yield files.fetch_file (file);
        if (path == "") {
            return;
        }

        load (contact, path);
        changed (int64.parse (key));
    }

    private void load (Contact contact, string path) {
        if (path == "") {
            return;
        }

        try {
            contact.photo = Gdk.Texture.from_filename (path);
        } catch (Error e) {
            warning ("could not load avatar %s: %s", path, e.message);
        }
    }

    private void remember_palette (Json.Array colors) {
        for (var i = 0; i < colors.get_length (); i++) {
            var entry = colors.get_object_element (i);
            var accent = new Accent ();

            accent.light = first_colour (entry, "light_theme_colors");
            accent.dark = first_colour (entry, "dark_theme_colors");

            palette.insert (entry.get_int_member ("id").to_string (), accent);
        }
    }

    // Colours arrive as packed RGB integers, and a name only needs the first.
    private static string first_colour (Json.Object entry, string member) {
        if (!entry.has_member (member)) {
            return "";
        }

        var list = entry.get_array_member (member);
        if (list.get_length () == 0) {
            return "";
        }

        return "#%06x".printf ((uint) (list.get_int_element (0) & 0xFFFFFF));
    }
}
