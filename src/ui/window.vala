[GtkTemplate (ui = "/dev/miguel/Telegrama/window.ui")]
public class Telegrama.Window : Adw.ApplicationWindow {

    [GtkChild] private unowned Adw.ToastOverlay toasts;
    [GtkChild] private unowned Gtk.Stack stack;
    [GtkChild] private unowned Adw.Bin login_slot;
    [GtkChild] private unowned Adw.NavigationSplitView split;
    [GtkChild] private unowned Gtk.ScrolledWindow chat_scroll;
    [GtkChild] private unowned Gtk.ListView chat_view;
    [GtkChild] private unowned Adw.StatusPage placeholder;

    public AuthSession auth { get; construct; }
    public ChatList chats { get; construct; }

    // Not "settings": Gtk.Widget already has get_settings(), and a property of
    // that name would silently override it.
    public Settings prefs { get; construct; }

    public Window (Gtk.Application app, AuthSession auth, ChatList chats) {
        Object (application: app, auth: auth, chats: chats, prefs: new Settings (Config.APP_ID));
    }

    construct {
        login_slot.child = new LoginView (auth);

        prefs.bind ("window-width", this, "default-width", SettingsBindFlags.DEFAULT);
        prefs.bind ("window-height", this, "default-height", SettingsBindFlags.DEFAULT);
        prefs.bind ("window-maximized", this, "maximized", SettingsBindFlags.DEFAULT);

        auth.notify["stage"].connect (sync_stage);
        auth.failed.connect ((message) => {
            toasts.add_toast (new Adw.Toast (message));
        });

        setup_chat_list ();
        sync_stage ();
    }

    private void setup_chat_list () {
        var factory = new Gtk.SignalListItemFactory ();

        factory.setup.connect ((object) => {
            ((Gtk.ListItem) object).child = new ChatRow ();
        });

        factory.bind.connect ((object) => {
            var item = (Gtk.ListItem) object;
            ((ChatRow) item.child).bind ((Chat) item.item);
        });

        factory.unbind.connect ((object) => {
            ((ChatRow) ((Gtk.ListItem) object).child).unbind ();
        });

        var selection = new Gtk.SingleSelection (chats.store) {
            autoselect = false,
            can_unselect = true
        };
        selection.selected = Gtk.INVALID_LIST_POSITION;

        selection.notify["selected-item"].connect (() => {
            var chat = selection.selected_item as Chat;
            if (chat == null) {
                placeholder.title = "Select a chat";
                placeholder.description = "Message history arrives in phase 3.";
                return;
            }

            placeholder.title = chat.title;
            placeholder.description = "Message history arrives in phase 3.";
            split.show_content = true;
        });

        chat_view.factory = factory;
        chat_view.model = selection;

        // Paging happens on approach rather than on arrival, so the next batch
        // is usually already there by the time the list runs out.
        chat_scroll.vadjustment.value_changed.connect (() => {
            var adjustment = chat_scroll.vadjustment;
            if (adjustment.upper - (adjustment.value + adjustment.page_size) < adjustment.page_size) {
                chats.load.begin ();
            }
        });
    }

    private void sync_stage () {
        stack.visible_child_name = auth.stage == AuthStage.READY ? "main" : "login";
    }
}
