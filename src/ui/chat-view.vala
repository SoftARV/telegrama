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
    private Message? flashing = null;
    private uint flash_source = 0;
    private bool flash_variant = false;

    public ChatView (MessageList messages) {
        Object (messages: messages);
    }

    construct {
        var factory = new Gtk.SignalListItemFactory ();

        factory.setup.connect ((object) => {
            var row = new MessageRow (messages.users);
            row.jump.connect (jump_to);
            ((Gtk.ListItem) object).child = row;
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

    private void jump_to (int64 message_id) {
        reach.begin (message_id);
    }

    private async void reach (int64 message_id) {
        var found = yield messages.reach (message_id);
        if (!found) {
            return;
        }

        uint position;
        if (!messages.position_of (message_id, out position)) {
            return;
        }

        // Paging back to find it will have armed the anchor, which would pull
        // the view straight back to where the reader was.
        anchor = -1;
        follow = false;

        list.scroll_to (position, Gtk.ListScrollFlags.NONE, null);

        flash ((Message) messages.store.get_item (position));
    }

    // Jumping again before the previous pulse finishes has to clear the old
    // highlight first, or the second jump lands on a message already wearing
    // the class and nothing happens.
    private void flash (Message target) {
        if (flash_source != 0) {
            Source.remove (flash_source);
            flash_source = 0;
        }

        if (flashing != null) {
            flashing.highlighted = false;
        }

        flash_variant = !flash_variant;
        target.flash_variant = flash_variant;
        target.highlighted = true;
        flashing = target;

        // Outlasts the animation, or the class would be pulled mid-pulse.
        flash_source = Timeout.add (1700, () => {
            target.highlighted = false;
            flashing = null;
            flash_source = 0;
            return Source.REMOVE;
        });
    }

    private void to_bottom () {
        var adjustment = scroll.vadjustment;
        adjustment.value = adjustment.upper - adjustment.page_size;
    }
}
