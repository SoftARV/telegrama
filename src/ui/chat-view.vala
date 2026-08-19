[GtkTemplate (ui = "/dev/miguel/Telegrama/chat-view.ui")]
public class Telegrama.ChatView : Adw.Bin {

    // How close to an edge counts as being at it.
    private const double EDGE = 240;

    [GtkChild] private unowned Gtk.Stack stack;
    [GtkChild] private unowned Gtk.ScrolledWindow scroll;
    [GtkChild] private unowned Gtk.ListView list;
    [GtkChild] private unowned Gtk.Entry entry;
    [GtkChild] private unowned Gtk.Button send;

    public MessageList messages { get; construct; }

    // Distance from the bottom to restore once the newly prepended rows have
    // been measured. Negative means nothing is waiting.
    private double anchor = -1;
    private bool follow = true;
    private Message? flashing = null;
    private uint flash_source = 0;
    private bool flash_variant = false;
    private bool adjusting = false;

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
            var message = (Message) item.item;

            ((MessageRow) item.child).bind (message);

            // Read state follows what actually reaches the screen rather than
            // what happens to be loaded.
            if (!message.is_outgoing) {
                messages.saw (message.id);
            }
        });

        factory.unbind.connect ((object) => {
            ((MessageRow) ((Gtk.ListItem) object).child).unbind ();
        });

        list.factory = factory;
        list.model = new Gtk.NoSelection (messages.store);

        entry.activate.connect (deliver);
        send.clicked.connect (deliver);

        messages.notify["chat"].connect (() => {
            entry.text = "";
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
            // Our own scrolling is not the reader changing their mind about
            // where they want to be.
            if (adjusting) {
                return;
            }

            var adjustment = scroll.vadjustment;

            follow = adjustment.upper - (adjustment.value + adjustment.page_size) < EDGE;

            // Only page back when there is something to scroll. A view whose
            // content does not fill it sits at value 0, which otherwise reads
            // as "the reader is at the top, fetch more".
            if (adjustment.upper > adjustment.page_size && adjustment.value < EDGE) {
                messages.load_older ();
            }
        });
    }

    private void deliver () {
        var text = entry.text;
        if (text.strip () == "") {
            return;
        }

        entry.text = "";

        // Sending scrolls back down: it would be odd to send and not see it.
        follow = true;
        messages.send (text);
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

    // Asking the list for its last row rather than driving the adjustment: the
    // adjustment's upper lags behind rows that have not been measured yet, so
    // computing a position from it lands short and, worse, can look like a
    // scroll to the top.
    private void to_bottom () {
        var count = messages.store.get_n_items ();
        if (count == 0) {
            return;
        }

        adjusting = true;
        list.scroll_to (count - 1, Gtk.ListScrollFlags.NONE, null);

        Idle.add (() => {
            adjusting = false;
            return Source.REMOVE;
        });
    }
}
