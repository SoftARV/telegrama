[GtkTemplate (ui = "/dev/miguel/Telegrama/chat-row.ui")]
public class Telegrama.ChatRow : Gtk.Box {

    [GtkChild] private unowned Adw.Avatar avatar;
    [GtkChild] private unowned Gtk.Label title_label;
    [GtkChild] private unowned Gtk.Label time_label;
    [GtkChild] private unowned Gtk.Label preview_label;
    [GtkChild] private unowned Gtk.Image pin_icon;
    [GtkChild] private unowned Gtk.Label unread_label;

    private Chat? chat = null;
    private ulong handler = 0;

    public void bind (Chat chat) {
        unbind ();

        this.chat = chat;
        handler = chat.notify.connect ((source, spec) => {
            refresh ();
        });

        refresh ();
    }

    public void unbind () {
        if (chat != null && handler != 0) {
            chat.disconnect (handler);
        }

        chat = null;
        handler = 0;
    }

    private void refresh () {
        if (chat == null) {
            return;
        }

        avatar.text = chat.title;
        title_label.label = chat.title;
        preview_label.label = chat.preview;
        time_label.label = Dates.relative (chat.date);

        unread_label.visible = chat.unread_count > 0;
        unread_label.label = chat.unread_count > 99 ? "99+" : chat.unread_count.to_string ();

        // The badge says more than the pin does, so it wins when a pinned chat
        // also has something unread.
        pin_icon.visible = chat.is_pinned && chat.unread_count == 0;
    }
}
