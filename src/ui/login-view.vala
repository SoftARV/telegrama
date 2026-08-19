[GtkTemplate (ui = "/dev/miguel/Telegrama/login-view.ui")]
public class Telegrama.LoginView : Adw.Bin {

    [GtkChild] private unowned Gtk.Stack stack;
    [GtkChild] private unowned Gtk.Entry phone_entry;
    [GtkChild] private unowned Gtk.Button phone_next;
    [GtkChild] private unowned Gtk.Button phone_use_qr;
    [GtkChild] private unowned Adw.Bin qr_slot;
    [GtkChild] private unowned Gtk.Button qr_use_phone;
    [GtkChild] private unowned Adw.StatusPage code_page;
    [GtkChild] private unowned Gtk.Entry code_entry;
    [GtkChild] private unowned Gtk.Button code_next;
    [GtkChild] private unowned Adw.StatusPage password_page;
    [GtkChild] private unowned Gtk.PasswordEntry password_entry;
    [GtkChild] private unowned Gtk.Button password_next;

    private QrCode qr_code = new QrCode ();

    public AuthSession auth { get; construct; }

    public LoginView (AuthSession auth) {
        Object (auth: auth);
    }

    construct {
        phone_entry.activate.connect (submit_phone);
        phone_next.clicked.connect (submit_phone);
        code_entry.activate.connect (submit_code);
        code_next.clicked.connect (submit_code);
        password_entry.activate.connect (submit_password);
        password_next.clicked.connect (submit_password);

        qr_slot.child = qr_code;
        phone_use_qr.clicked.connect (auth.use_qr);
        qr_use_phone.clicked.connect (auth.use_phone);

        // The token rotates without the stage changing, so this is a separate
        // subscription rather than part of sync().
        auth.notify["qr-link"].connect (() => {
            qr_code.link = auth.qr_link;
        });

        auth.notify["stage"].connect (sync);
        sync ();
    }

    private void sync () {
        stack.sensitive = true;

        switch (auth.stage) {
            case AuthStage.UNCONFIGURED:
                stack.visible_child_name = "unconfigured";
                break;

            case AuthStage.PHONE:
                stack.visible_child_name = "phone";
                phone_entry.grab_focus ();
                break;

            case AuthStage.QR:
                qr_code.link = auth.qr_link;
                stack.visible_child_name = "qr";
                break;

            case AuthStage.CODE:
                code_page.description = auth.code_target;
                code_entry.text = "";
                stack.visible_child_name = "code";
                code_entry.grab_focus ();
                break;

            case AuthStage.PASSWORD:
                password_page.description = auth.password_hint == ""
                    ? "Enter your two-step verification password."
                    : @"Password hint: $(auth.password_hint)";
                password_entry.text = "";
                stack.visible_child_name = "password";
                password_entry.grab_focus ();
                break;

            case AuthStage.REGISTRATION:
                stack.visible_child_name = "registration";
                break;

            default:
                stack.visible_child_name = "connecting";
                break;
        }
    }

    private void submit_phone () {
        var number = phone_entry.text.strip ();
        if (number == "") {
            return;
        }

        stack.sensitive = false;
        auth.submit_phone.begin (number, (obj, res) => {
            auth.submit_phone.end (res);
            stack.sensitive = true;
        });
    }

    private void submit_code () {
        var code = code_entry.text.strip ();
        if (code == "") {
            return;
        }

        stack.sensitive = false;
        auth.submit_code.begin (code, (obj, res) => {
            auth.submit_code.end (res);
            stack.sensitive = true;
        });
    }

    private void submit_password () {
        var password = password_entry.text;
        if (password == "") {
            return;
        }

        stack.sensitive = false;
        auth.submit_password.begin (password, (obj, res) => {
            auth.submit_password.end (res);
            stack.sensitive = true;
        });
    }
}
