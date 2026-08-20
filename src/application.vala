public class Telegrama.Application : Adw.Application {

    private Td.Client client;
    private AuthSession auth;
    private ChatList chats;
    private UserStore users;
    private MessageList messages;
    private Notifier notifier;
    private Window? window = null;
    private bool closing = false;

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
        chats = new ChatList (client, auth);
        users = new UserStore (client);
        messages = new MessageList (client, users);
        notifier = new Notifier (this, client, auth, chats, users);
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

        var about_action = new SimpleAction ("about", null);
        about_action.activate.connect (show_about);
        add_action (about_action);

        var quit_action = new SimpleAction ("quit", null);
        quit_action.activate.connect (() => {
            shut_down.begin ();
        });
        add_action (quit_action);

        set_accels_for_action ("app.quit", { "<Control>q" });
        set_accels_for_action ("app.about", { "F1" });
    }

    protected override void activate () {
        if (window == null) {
            window = new Window (this, auth, chats, messages);

            // Closing has to wait for TDLib to acknowledge, otherwise the
            // database is left to recover on next launch.
            window.close_request.connect (() => {
                shut_down.begin ();
                return true;
            });
        }
        window.present ();
    }

    private async void shut_down () {
        if (closing) {
            return;
        }
        closing = true;

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
