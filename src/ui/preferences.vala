[GtkTemplate (ui = "/dev/miguel/Telegrama/preferences.ui")]
public class Telegrama.Preferences : Adw.PreferencesDialog {

    [GtkChild] private unowned Adw.SwitchRow background_row;
    [GtkChild] private unowned Adw.SwitchRow notifications_row;
    [GtkChild] private unowned Adw.ButtonRow logout_row;

    public Settings prefs { get; construct; }
    public Td.Client client { get; construct; }

    public Preferences (Settings prefs, Td.Client client) {
        Object (prefs: prefs, client: client);
    }

    construct {
        prefs.bind ("run-in-background", background_row, "active", SettingsBindFlags.DEFAULT);
        prefs.bind ("show-notifications", notifications_row, "active", SettingsBindFlags.DEFAULT);

        logout_row.activated.connect (confirm_logout);
    }

    private void confirm_logout () {
        var dialog = new Adw.AlertDialog (
            "Log out?",
            "This device's session ends and its local cache is removed. Your messages stay on Telegram."
        );

        dialog.add_response ("cancel", "Cancel");
        dialog.add_response ("logout", "Log Out");
        dialog.set_response_appearance ("logout", Adw.ResponseAppearance.DESTRUCTIVE);
        dialog.set_close_response ("cancel");
        dialog.set_default_response ("cancel");

        dialog.response.connect ((answer) => {
            if (answer != "logout") {
                return;
            }

            // TDLib closes the client on its way out; the authorization state
            // machine notices and brings the sign-in screen back.
            client.send ("logOut");
            close ();
        });

        dialog.present (this);
    }
}
