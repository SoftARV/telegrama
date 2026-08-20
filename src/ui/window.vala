[GtkTemplate (ui = "/dev/miguel/Telegrama/window.ui")]
public class Telegrama.Window : Adw.ApplicationWindow {

    [GtkChild] private unowned Adw.ToastOverlay toasts;
    [GtkChild] private unowned Gtk.Stack stack;
    [GtkChild] private unowned Adw.Bin login_slot;
    [GtkChild] private unowned Adw.NavigationSplitView split;
    [GtkChild] private unowned Gtk.ScrolledWindow chat_scroll;
    [GtkChild] private unowned Gtk.ListView chat_view;
    [GtkChild] private unowned Gtk.ToggleButton search_toggle;
    [GtkChild] private unowned Gtk.SearchBar search_bar;
    [GtkChild] private unowned Gtk.SearchEntry search_entry;
    [GtkChild] private unowned Gtk.Stack sidebar_stack;
    [GtkChild] private unowned Adw.StatusPage no_results;
    [GtkChild] private unowned Adw.NavigationPage content_page;
    [GtkChild] private unowned Adw.WindowTitle chat_title;
    [GtkChild] private unowned Adw.Bin conversation_slot;

    public AuthSession auth { get; construct; }
    public ChatList chats { get; construct; }
    public MessageList messages { get; construct; }

    // Not "settings": Gtk.Widget already has get_settings(), and a property of
    // that name would silently override it.
    public Settings prefs { get; construct; }

    private Gtk.FilterListModel? filtered = null;
    private string query = "";

    public Window (Gtk.Application app, AuthSession auth, ChatList chats, MessageList messages) {
        Object (application: app, auth: auth, chats: chats, messages: messages,
                prefs: new Settings (Config.APP_ID));
    }

    construct {
        login_slot.child = new LoginView (auth);
        conversation_slot.child = new ChatView (messages);

        prefs.bind ("window-width", this, "default-width", SettingsBindFlags.DEFAULT);
        prefs.bind ("window-height", this, "default-height", SettingsBindFlags.DEFAULT);
        prefs.bind ("window-maximized", this, "maximized", SettingsBindFlags.DEFAULT);

        auth.notify["stage"].connect (sync_stage);
        auth.failed.connect ((message) => {
            toasts.add_toast (new Adw.Toast (message));
        });

        messages.notify["activity"].connect (() => {
            chat_title.subtitle = messages.activity;
        });

        setup_chat_list ();
        sync_sidebar ();
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

        var filter = new Gtk.CustomFilter ((item) => {
            if (query == "") {
                return true;
            }
            return ((Chat) item).title.down ().contains (query);
        });
        filtered = new Gtk.FilterListModel (chats.store, filter);

        search_toggle.bind_property ("active", search_bar, "search-mode-enabled",
            BindingFlags.BIDIRECTIONAL);
        search_bar.set_key_capture_widget (this);

        search_entry.search_changed.connect (() => {
            query = search_entry.text.strip ().down ();
            filter.changed (Gtk.FilterChange.DIFFERENT);

            // A query can only match what is loaded, so the first keystroke
            // pulls the rest of the list in behind it.
            if (query != "") {
                chats.load_all.begin ();
            }

            sync_sidebar ();
        });

        filtered.items_changed.connect (() => {
            sync_sidebar ();
        });

        var selection = new Gtk.SingleSelection (filtered) {
            autoselect = false,
            can_unselect = true
        };
        selection.selected = Gtk.INVALID_LIST_POSITION;

        selection.notify["selected-item"].connect (() => {
            var chat = selection.selected_item as Chat;

            content_page.title = chat == null ? "Telegrama" : chat.title;
            chat_title.title = chat == null ? "Telegrama" : chat.title;
            messages.open (chat);

            if (chat != null) {
                split.show_content = true;
            }
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

    // Reached from a notification, which knows a chat id and nothing else.
    public void open_chat (int64 chat_id) {
        // A chat reached from a notification may not match the current query,
        // so the search is dropped rather than hiding what was just asked for.
        search_bar.search_mode_enabled = false;

        var model = chat_view.model as Gtk.SingleSelection;
        if (model == null) {
            return;
        }

        for (uint i = 0; i < model.get_n_items (); i++) {
            if (((Chat) model.get_item (i)).id == chat_id) {
                model.selected = i;
                split.show_content = true;
                return;
            }
        }
    }

    // An empty list means two different things, and saying the wrong one is
    // worse than saying nothing: no chats at all, or none matching a query.
    private void sync_sidebar () {
        if (filtered == null) {
            return;
        }

        if (filtered.get_n_items () > 0) {
            sidebar_stack.visible_child_name = "chats";
            return;
        }

        if (query != "") {
            no_results.description = @"Nothing matches \u201C$(search_entry.text.strip ())\u201D.";
            sidebar_stack.visible_child_name = "no-results";
            return;
        }

        sidebar_stack.visible_child_name = "empty";
    }

    private void sync_stage () {
        stack.visible_child_name = auth.stage == AuthStage.READY ? "main" : "login";
    }
}
