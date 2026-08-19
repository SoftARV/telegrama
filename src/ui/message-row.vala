[GtkTemplate (ui = "/dev/miguel/Telegrama/message-row.ui")]
public class Telegrama.MessageRow : Gtk.Box {

    [GtkChild] private unowned Gtk.Label service_label;
    [GtkChild] private unowned Gtk.Box bubble;
    [GtkChild] private unowned Gtk.Label sender_label;
    [GtkChild] private unowned Gtk.Label text_label;
    [GtkChild] private unowned Gtk.Label time_label;

    private Message? message = null;
    private ulong handler = 0;

    construct {
        // Any click on the text reveals every spoiler in that message. Telegram
        // reveals them one at a time, which needs hit-testing into the Pango
        // layout; this is the honest simplification.
        var reveal = new Gtk.GestureClick ();
        reveal.released.connect (() => {
            if (message != null && !message.spoilers_revealed) {
                message.spoilers_revealed = true;
            }
        });
        text_label.add_controller (reveal);
    }

    public void bind (Message message) {
        unbind ();

        this.message = message;
        handler = message.notify.connect ((source, spec) => {
            refresh ();
        });

        refresh ();
    }

    public void unbind () {
        if (message != null && handler != 0) {
            message.disconnect (handler);
        }

        message = null;
        handler = 0;
    }

    // Spoilers are painted in the label's own colour so they read as a solid
    // bar and follow the theme, rather than against a palette we invented.
    private string ink () {
        var colour = text_label.get_color ();
        return "#%02x%02x%02x".printf (
            (int) (colour.red * 255),
            (int) (colour.green * 255),
            (int) (colour.blue * 255)
        );
    }

    private void refresh () {
        if (message == null) {
            return;
        }

        service_label.visible = message.is_service;
        bubble.visible = !message.is_service;

        if (message.is_service) {
            service_label.label = message.text;
            return;
        }

        bubble.halign = message.is_outgoing ? Gtk.Align.END : Gtk.Align.START;

        bubble.remove_css_class (message.is_outgoing ? "bubble-in" : "bubble-out");
        bubble.add_css_class (message.is_outgoing ? "bubble-out" : "bubble-in");

        sender_label.label = message.sender_name;
        sender_label.visible = !message.is_outgoing && message.sender_name != "";

        if (message.formatted != null) {
            text_label.label = Entities.markup (
                message.formatted,
                message.spoilers_revealed,
                ink ()
            );
        } else {
            text_label.label = Markup.escape_text (message.text);
        }

        // Anything the sidebar would summarise is a stand-in rather than words
        // someone typed, so it should not read as if they were.
        if (message.is_media) {
            text_label.add_css_class ("dim-label");
        } else {
            text_label.remove_css_class ("dim-label");
        }

        time_label.label = new DateTime.from_unix_local (message.date).format ("%H:%M");
    }
}
