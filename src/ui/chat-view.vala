[GtkTemplate (ui = "/dev/miguel/Telegrama/chat-view.ui")]
public class Telegrama.ChatView : Adw.Bin {

    // How close to an edge counts as being at it.
    private const double EDGE = 240;

    [GtkChild] private unowned Gtk.Stack stack;
    [GtkChild] private unowned Gtk.ScrolledWindow scroll;
    [GtkChild] private unowned Gtk.ListView list;

    public MessageList messages { get; construct; }

    // Distance from the bottom to restore once the newly prepended rows have
    // been measured. Negative means nothing is waiting.
    private double anchor = -1;
    private bool follow = true;

    public ChatView (MessageList messages) {
        Object (messages: messages);
    }

    construct {
        var factory = new Gtk.SignalListItemFactory ();

        factory.setup.connect ((object) => {
            ((Gtk.ListItem) object).child = new MessageRow ();
        });

        factory.bind.connect ((object) => {
            var item = (Gtk.ListItem) object;
            ((MessageRow) item.child).bind ((Message) item.item);
        });

        factory.unbind.connect ((object) => {
            ((MessageRow) ((Gtk.ListItem) object).child).unbind ();
        });

        list.factory = factory;
        list.model = new Gtk.NoSelection (messages.store);

        messages.notify["chat"].connect (() => {
            follow = true;
            anchor = -1;
            stack.visible_child_name = messages.chat == null ? "empty" : "messages";
        });

        // Older messages go in at the top, which moves everything below them.
        // Recording the distance from the bottom and restoring it after layout
        // keeps the reader where they were instead of throwing them upward.
        messages.prepended.connect (() => {
            anchor = scroll.vadjustment.upper - scroll.vadjustment.value;
        });

        messages.appended.connect (() => {
            if (follow) {
                to_bottom ();
            }
        });

        scroll.vadjustment.notify["upper"].connect (() => {
            if (anchor >= 0) {
                scroll.vadjustment.value = scroll.vadjustment.upper - anchor;
                anchor = -1;
            } else if (follow) {
                to_bottom ();
            }

            // TDLib's first page is often short. With less than a screenful
            // there is nothing to scroll, so the scroll handler below would
            // never run and nothing would ever ask for the rest.
            if (scroll.vadjustment.upper <= scroll.vadjustment.page_size) {
                messages.load_older ();
            }
        });

        scroll.vadjustment.value_changed.connect (() => {
            var adjustment = scroll.vadjustment;

            follow = adjustment.upper - (adjustment.value + adjustment.page_size) < EDGE;

            if (adjustment.value < EDGE) {
                messages.load_older ();
            }
        });
    }

    private void to_bottom () {
        var adjustment = scroll.vadjustment;
        adjustment.value = adjustment.upper - adjustment.page_size;
    }
}
