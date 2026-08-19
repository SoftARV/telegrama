[GtkTemplate (ui = "/dev/miguel/Telegrama/message-row.ui")]
public class Telegrama.MessageRow : Gtk.Box {

    [GtkChild] private unowned Gtk.Box bubble;
    [GtkChild] private unowned Gtk.Label sender_label;
    [GtkChild] private unowned Gtk.Label text_label;
    [GtkChild] private unowned Gtk.Label time_label;

    private Message? message = null;
    private ulong handler = 0;

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

    private void refresh () {
        if (message == null) {
            return;
        }

        bubble.halign = message.is_outgoing ? Gtk.Align.END : Gtk.Align.START;

        bubble.remove_css_class (message.is_outgoing ? "bubble-in" : "bubble-out");
        bubble.add_css_class (message.is_outgoing ? "bubble-out" : "bubble-in");

        sender_label.label = message.sender_name;
        sender_label.visible = !message.is_outgoing && message.sender_name != "";

        text_label.label = message.text;

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
