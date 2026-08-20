public class Telegrama.Application : Adw.Application {

    private Td.Client client;
    private AuthSession auth;
    private ChatList chats;
    private UserStore users;
    private FileStore downloads;
    private MediaLoader loader;
    private MessageList messages;
    private Notifier notifier;
    private TrayIcon tray;
    private Window? window = null;
    private bool closing = false;
    private bool holding = false;
    private Settings prefs = new Settings (Config.APP_ID);

    public Application () {
        Object (application_id: Config.APP_ID,
                flags: ApplicationFlags.DEFAULT_FLAGS);
    }

    protected override void startup () {
        base.startup ();

        var provider = new Gtk.CssProvider ();
        provider.load_from_resource (Config.APP_PATH + "/style.css");
        Gtk.StyleContext.add_provider_for_display (
            Gdk.Display.get_default (),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );

        client = new Td.Client ();
        auth = new AuthSession (client);
        downloads = new FileStore (client);
        loader = new MediaLoader (downloads);
        chats = new ChatList (client, auth, downloads);
        users = new UserStore (client, downloads);
        messages = new MessageList (client, users, loader);
        notifier = new Notifier (this, client, auth, chats, users);

        // Tied to background mode rather than a setting of its own: the icon
        // exists to say the process is still there once the window is gone.
        tray = new TrayIcon ();
        tray.show_requested.connect (() => {
            activate ();
        });
        tray.set_enabled (prefs.get_boolean ("run-in-background"));
        tray.start ();
        client.start ();
        auth.start.begin ();

        // Carries an int64 chat id, so a notification can say which chat it came
        // from rather than merely raising the window.
        var open_chat = new SimpleAction ("open-chat", new VariantType ("x"));
        open_chat.activate.connect ((parameter) => {
            activate ();
            if (window != null && parameter != null) {
                window.open_chat (parameter.get_int64 ());
            }
        });
        add_action (open_chat);

        var preferences = new SimpleAction ("preferences", null);
        preferences.activate.connect (() => {
            new Preferences (prefs, client).present (active_window);
        });
        add_action (preferences);

        // Switching it off while the window is already hidden would otherwise
        // leave the process alive with nothing on screen.
        prefs.changed["run-in-background"].connect (() => {
            var on = prefs.get_boolean ("run-in-background");
            tray.set_enabled (on);

            if (!on) {
                release_hold ();
            }
        });

        var about_action = new SimpleAction ("about", null);
        about_action.activate.connect (show_about);
        add_action (about_action);

        var quit_action = new SimpleAction ("quit", null);
        quit_action.activate.connect (() => {
            shut_down.begin ();
        });
        add_action (quit_action);

        set_accels_for_action ("app.quit", { "<Control>q" });
        set_accels_for_action ("app.preferences", { "<Control>comma" });
        set_accels_for_action ("app.about", { "F1" });
    }

    protected override void activate () {
        if (window == null) {
            window = new Window (this, auth, chats, messages);

            window.close_request.connect (() => {
                // Notifications only arrive while the process lives, so closing
                // the window hides it rather than ending it.
                if (prefs.get_boolean ("run-in-background")) {
                    window.set_visible (false);
                    take_hold ();
                    return true;
                }

                // Closing has to wait for TDLib to acknowledge, otherwise the
                // database is left to recover on next launch.
                shut_down.begin ();
                return true;
            });
        }
        window.set_visible (true);
        window.present ();
    }

    // GApplication ends once nothing holds it; a hidden window does not count.
    private void take_hold () {
        if (!holding) {
            hold ();
            holding = true;
        }
    }

    private void release_hold () {
        if (holding) {
            release ();
            holding = false;
        }
    }

    private async void shut_down () {
        if (closing) {
            return;
        }
        closing = true;
        release_hold ();

        yield client.stop ();
        quit ();
    }

    private void show_about () {
        new Adw.AboutDialog () {
            application_name = "Telegrama",
            application_icon = Config.APP_ID,
            version = Config.VERSION,
            developer_name = "Miguel Rincon",
            comments = "A fast, native Telegram client.",
            website = "https://github.com/SoftARV/telegrama",
            issue_url = "https://github.com/SoftARV/telegrama/issues",
            license_type = Gtk.License.GPL_3_0,
            copyright = "© 2026 Miguel Rincon",
        }.present (active_window);
    }
}
