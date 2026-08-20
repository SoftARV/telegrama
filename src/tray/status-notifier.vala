namespace Telegrama {

    [DBus (name = "org.kde.StatusNotifierWatcher")]
    public interface StatusNotifierWatcher : Object {
        public abstract void register_status_notifier_item (string service) throws Error;
        public abstract bool is_status_notifier_host_registered { get; }
    }

    // Hand-written because GTK4 dropped StatusIcon and libappindicator is GTK3,
    // which cannot be linked into this process. This is the protocol underneath
    // both, and it is only a handful of properties.
    [DBus (name = "org.kde.StatusNotifierItem")]
    public class StatusNotifierItem : Object {

        public string category { get; set; default = "Communications"; }
        public string id { get; set; default = "telegrama"; }
        public string title { get; set; default = "Telegrama"; }
        public string status { get; set; default = "Active"; }
        public string icon_name { get; set; default = ""; }
        public string icon_theme_path { get; set; default = ""; }
        public bool item_is_menu { get; set; default = false; }

        // Must be a real ObjectPath. Declaring it as a string with
        // [DBus (signature = "o")] compiles, but the value and the advertised
        // signature disagree and GDBus segfaults marshalling the GetAll reply.
        public ObjectPath menu { get; set; }

        construct {
            menu = new ObjectPath ("/");
        }

        public signal void new_icon ();
        public signal void new_title ();
        public signal void new_status (string status);

        [DBus (visible = false)]
        public signal void activate_requested ();

        public void activate (int x, int y) throws Error {
            activate_requested ();
        }

        public void secondary_activate (int x, int y) throws Error {
            activate_requested ();
        }

        public void context_menu (int x, int y) throws Error {
        }

        public void scroll (int delta, string orientation) throws Error {
        }
    }
}
