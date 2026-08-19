[GtkTemplate (ui = "/dev/miguel/Telegrama/chat-view.ui")]
public class Telegrama.ChatView : Adw.Bin {

    // How close to an edge counts as being at it.
    private const double EDGE = 240;

    [GtkChild] private unowned Gtk.Stack stack;
    [GtkChild] private unowned Gtk.ScrolledWindow scroll;
    [GtkChild] private unowned Gtk.ListView list;
    [GtkChild] private unowned Gtk.TextView entry;
    [GtkChild] private unowned Gtk.Label placeholder;
    [GtkChild] private unowned Gtk.ScrolledWindow composer_scroll;
    [GtkChild] private unowned Gtk.Scrollbar composer_bar;
    [GtkChild] private unowned Gtk.Button send;
    [GtkChild] private unowned Gtk.Revealer edit_banner;
    [GtkChild] private unowned Gtk.Label edit_preview;
    [GtkChild] private unowned Gtk.Button edit_cancel;
    [GtkChild] private unowned Gtk.Revealer jump_down;
    [GtkChild] private unowned Gtk.Button to_bottom_button;

    public MessageList messages { get; construct; }

    // Distance from the bottom to restore once the newly prepended rows have
    // been measured. Negative means nothing is waiting.
    private double anchor = -1;
    private bool follow = true;
    private Message? flashing = null;
    private uint flash_source = 0;
    private bool flash_variant = false;
    private bool adjusting = false;
    private uint settle_source = 0;
    private Message? editing = null;
    private Gtk.Popover? menu = null;
    private Gtk.Button? menu_edit = null;
    private Message? menu_target = null;

    public ChatView (MessageList messages) {
        Object (messages: messages);
    }

    construct {
        var factory = new Gtk.SignalListItemFactory ();

        factory.setup.connect ((object) => {
            var row = new MessageRow (messages.users);
            row.jump.connect (jump_to);
            row.edit_requested.connect (begin_edit);
            row.menu_requested.connect ((message, x, y) => {
                open_menu (row, message, x, y);
            });
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

        send.clicked.connect (deliver);

        // The composer's scrollbar policy is external, which is what keeps it
        // from reserving two lines of height. External means no scrollbar of its
        // own, so this is one, shown only once there is something to scroll.
        composer_bar.adjustment = composer_scroll.vadjustment;
        composer_scroll.vadjustment.changed.connect (() => {
            var a = composer_scroll.vadjustment;
            composer_bar.visible = a.upper > a.page_size + 1;
        });

        // A TextView has no placeholder of its own, so one is laid over it.
        entry.buffer.changed.connect (() => {
            placeholder.visible = entry.buffer.text == "";
        });

        edit_cancel.clicked.connect (cancel_edit);

        var keys = new Gtk.EventControllerKey ();
        keys.key_pressed.connect ((keyval, code, state) => {
            var shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;

            // Enter sends, shift+enter breaks the line. Returning false lets the
            // TextView insert the newline itself rather than doing it by hand.
            if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) {
                if (shift) {
                    return false;
                }
                deliver ();
                return true;
            }

            if (keyval == Gdk.Key.Escape && editing != null) {
                cancel_edit ();
                return true;
            }

            // Up on an empty composer reaches for the last thing said, which is
            // what it almost always means.
            if (keyval == Gdk.Key.Up && editing == null && entry.buffer.text == "") {
                var target = messages.last_editable ();
                if (target != null) {
                    begin_edit (target);
                    return true;
                }
            }

            return false;
        });
        entry.add_controller (keys);

        to_bottom_button.clicked.connect (() => {
            set_follow (true);
            to_bottom ();
        });

        messages.notify["chat"].connect (() => {
            cancel_edit ();
            set_follow (true);
            anchor = -1;
            stack.visible_child_name = messages.chat == null ? "empty" : "messages";

            if (messages.chat != null) {
                // Deferred: the stack has only just been told to show this page,
                // and a widget that is not mapped yet cannot take focus.
                Idle.add (() => {
                    entry.grab_focus ();
                    return Source.REMOVE;
                });
            }
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

        // The editing banner shortens the scrolled window, and GtkListView
        // answers a re-allocation by resetting its adjustment to zero rather
        // than clamping it, throwing the reader to the top of the history.
        // Re-pinning here also keeps that reset from reading as the reader
        // scrolling away, since to_bottom raises the guard below.
        scroll.vadjustment.notify["page-size"].connect (() => {
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

            set_follow (adjustment.upper - (adjustment.value + adjustment.page_size) < EDGE);

            // Only page back when there is something to scroll. A view whose
            // content does not fill it sits at value 0, which otherwise reads
            // as "the reader is at the top, fetch more".
            if (adjustment.upper > adjustment.page_size && adjustment.value < EDGE) {
                messages.load_older ();
            }
        });
    }

    private Gtk.Button menu_item (string label, string icon) {
        var line = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
        line.append (new Gtk.Image.from_icon_name (icon));
        line.append (new Gtk.Label (label) {
            halign = Gtk.Align.START,
            hexpand = true
        });

        var button = new Gtk.Button () { child = line, has_frame = false };
        button.add_css_class ("message-menu-item");
        return button;
    }

    // One popover for the whole view, parented outside the scrolled window.
    // Parented to a row instead, it inherited the row's recycling: popping it
    // up pulled focus into the list, which scrolled to reach it, and a row
    // whose allocation was stale put the menu in the corner of the window.
    private void open_menu (Gtk.Widget row, Message message, double x, double y) {
        if (menu == null) {
            var items = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            items.add_css_class ("message-menu");

            var copy = menu_item ("Copy text", "edit-copy-symbolic");
            copy.clicked.connect (() => {
                menu.popdown ();
                if (menu_target != null) {
                    Gdk.Display.get_default ().get_clipboard ().set_text (menu_target.text);
                }
            });
            items.append (copy);

            menu_edit = menu_item ("Edit", "document-edit-symbolic");
            menu_edit.clicked.connect (() => {
                menu.popdown ();
                if (menu_target != null) {
                    begin_edit (menu_target);
                }
            });
            items.append (menu_edit);

            var remove = menu_item ("Delete", "user-trash-symbolic");
            remove.add_css_class ("destructive");
            remove.clicked.connect (() => {
                menu.popdown ();
                if (menu_target != null) {
                    confirm_delete (menu_target);
                }
            });
            items.append (remove);

            menu = new Gtk.Popover () {
                child = items,
                has_arrow = false,
                autohide = true
            };
            menu.add_css_class ("message-menu-popover");
            menu.set_parent (this);
        }

        // The click arrives in the row's coordinates; the popover lives in this
        // view's, so the point has to be translated across.
        Graphene.Point local = { (float) x, (float) y };
        Graphene.Point here;
        if (!row.compute_point (this, local, out here)) {
            return;
        }

        menu_target = message;
        menu_edit.visible = message.editable;

        menu.set_pointing_to ({ (int) here.x, (int) here.y, 1, 1 });
        menu.popup ();
    }

    // Deleting cannot be undone and reaches other people's clients, so it asks
    // first. Whether to take it back from everyone is a checkbox rather than a
    // third button: it is a qualifier on the same action, not a separate one.
    private void confirm_delete (Message target) {
        var dialog = new Adw.AlertDialog (
            "Delete message?",
            "This cannot be undone."
        );

        Gtk.CheckButton? everyone = null;
        if (target.is_outgoing) {
            everyone = new Gtk.CheckButton.with_label ("Also delete for everyone") {
                active = true,
                margin_top = 6
            };
            dialog.set_extra_child (everyone);
        }

        dialog.add_response ("cancel", "Cancel");
        dialog.add_response ("delete", "Delete");
        dialog.set_response_appearance ("delete", Adw.ResponseAppearance.DESTRUCTIVE);
        dialog.set_close_response ("cancel");
        dialog.set_default_response ("cancel");

        var id = target.id;
        dialog.response.connect ((answer) => {
            if (answer != "delete") {
                return;
            }
            messages.discard (id, everyone != null && everyone.active);
        });

        dialog.present (this);
    }

    private void begin_edit (Message target) {
        editing = target;
        edit_preview.label = target.text.replace ("\n", " ").strip ();
        edit_banner.reveal_child = true;

        entry.buffer.text = target.text;
        entry.grab_focus ();

        Gtk.TextIter end;
        entry.buffer.get_end_iter (out end);
        entry.buffer.place_cursor (end);
    }

    private void cancel_edit () {
        editing = null;
        edit_banner.reveal_child = false;
        entry.buffer.text = "";
    }

    private void deliver () {
        var text = entry.buffer.text;
        if (text.strip () == "") {
            return;
        }

        if (editing != null) {
            messages.edit (editing.id, text);
            cancel_edit ();
            return;
        }

        entry.buffer.text = "";

        // Sending scrolls back down: it would be odd to send and not see it.
        set_follow (true);
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
        set_follow (false);

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

    // One place, so the button showing the way back always matches whether the
    // view is actually pinned to the bottom.
    private void set_follow (bool value) {
        follow = value;
        jump_down.reveal_child = !value;
    }

    // Driving the adjustment rather than asking the list to scroll to the last
    // row: scroll_to only brings a row far enough into view to be visible, and
    // a row that has not been measured yet is brought too little, leaving the
    // view a row short of the bottom with nothing to correct it. The adjustment
    // can be told exactly where the bottom is, and re-told each time the rows
    // are measured and upper grows.
    private void to_bottom () {
        var adjustment = scroll.vadjustment;

        adjusting = true;
        adjustment.value = adjustment.upper - adjustment.page_size;

        // Held for a few frames rather than one idle: the list settles over
        // several, and a value change during that time is ours, not the
        // reader's.
        if (settle_source != 0) {
            Source.remove (settle_source);
        }
        settle_source = Timeout.add (150, () => {
            adjusting = false;
            settle_source = 0;
            return Source.REMOVE;
        });
    }
}
