// Present only while the app runs in the background: its job is to say the
// process is still alive and give it back, which is exactly the situation a
// hidden window creates.
public class Telegrama.TrayIcon : Object {

    // The watcher resolves the item by bus name and expects it here.
    private const string ITEM_PATH = "/StatusNotifierItem";
    private const string WATCHER = "org.kde.StatusNotifierWatcher";

    public signal void show_requested ();

    private DBusConnection? bus = null;
    private StatusNotifierItem? item = null;
    private uint watch_id = 0;
    private bool enabled = false;

    public void start () {
        export.begin ();
    }

    // Hosts hide a Passive item, which is a cleaner way to turn the icon off
    // than tearing the export down and rebuilding it.
    public void set_enabled (bool value) {
        enabled = value;

        if (item == null) {
            return;
        }

        var state = value ? "Active" : "Passive";
        if (item.status != state) {
            item.status = state;
            item.new_status (state);
        }
    }

    private async void export () {
        try {
            bus = yield Bus.get (BusType.SESSION);

            item = new StatusNotifierItem ();
            item.id = Config.APP_ID;
            item.status = enabled ? "Active" : "Passive";
            item.icon_theme_path = icon_theme_path ();
            item.icon_name = Config.APP_ID;
            item.activate_requested.connect (() => {
                show_requested ();
            });

            bus.register_object (ITEM_PATH, item);

            // Re-register when the host restarts: a panel reload drops every
            // item it was tracking, and nothing tells us except the name going
            // away and coming back.
            watch_id = Bus.watch_name (BusType.SESSION, WATCHER, BusNameWatcherFlags.NONE,
                (conn, name, owner) => {
                    register.begin ();
                },
                (conn, name) => { });
        } catch (Error e) {
            warning ("tray export: %s", e.message);
        }
    }

    private async void register () {
        try {
            StatusNotifierWatcher watcher = yield Bus.get_proxy<StatusNotifierWatcher> (
                BusType.SESSION, WATCHER, "/StatusNotifierWatcher");
            watcher.register_status_notifier_item (bus.unique_name);
        } catch (Error e) {
            warning ("tray register: %s", e.message);
        }
    }

    // Empty means "use the default icon theme", which is what an installed
    // build wants. Sending a path is actively harmful otherwise: the host
    // replaces its whole search path with it, so a directory that does not hold
    // the icons makes them unfindable even when properly installed. Only the
    // dev override sets it, since an uninstalled build has no themed icon for
    // another process to find.
    private string icon_theme_path () {
        var dev = Environment.get_variable ("TELEGRAMA_ICON_PATH");
        return dev != null ? dev : "";
    }
}
