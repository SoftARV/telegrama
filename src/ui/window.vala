[GtkTemplate (ui = "/dev/miguel/Telegrama/window.ui")]
public class Telegrama.Window : Adw.ApplicationWindow {

    [GtkChild] private unowned Adw.ToastOverlay toasts;
    [GtkChild] private unowned Gtk.Stack stack;
    [GtkChild] private unowned Adw.Bin login_slot;

    public AuthSession auth { get; construct; }

    // Not "settings": Gtk.Widget already has get_settings(), and a property of
    // that name would silently override it.
    public Settings prefs { get; construct; }

    public Window (Gtk.Application app, AuthSession auth) {
        Object (application: app, auth: auth, prefs: new Settings (Config.APP_ID));
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

        sync_stage ();
    }

    private void sync_stage () {
        stack.visible_child_name = auth.stage == AuthStage.READY ? "main" : "login";
    }
}
