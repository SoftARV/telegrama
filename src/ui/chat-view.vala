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
    [GtkChild] private unowned Gtk.Revealer completion_revealer;
    [GtkChild] private unowned Gtk.ScrolledWindow completion_scroller;
    [GtkChild] private unowned Gtk.ListBox completion_list;
    [GtkChild] private unowned Gtk.Revealer edit_banner;
    [GtkChild] private unowned Gtk.Label edit_preview;
    [GtkChild] private unowned Gtk.Button edit_cancel;
    [GtkChild] private unowned Gtk.Revealer mention_jump;
    [GtkChild] private unowned Gtk.Button mention_button;
    [GtkChild] private unowned Gtk.Revealer jump_down;
    [GtkChild] private unowned Gtk.Button to_bottom_button;

    public signal void chat_requested (int64 chat_id);

    public MessageList messages { get; construct; }

    // Distance from the bottom to restore once the newly prepended rows have
    // been measured. Negative means nothing is waiting.
    private double anchor = -1;
    private bool follow = true;
    private Message? flashing = null;
    private uint flash_source = 0;
    private bool flash_variant = false;
    private bool adjusting = false;
    private Chat? drafting = null;
    private Chat? watched = null;

    private int64[] candidates = {};
    private int mention_start = -1;

    // Not a user id: the row that writes every member out.
    private const int64 EVERYONE = 0;
    private ulong mention_handler = 0;
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
            var row = new MessageRow (messages.users, messages.loader);
            row.jump.connect (jump_to);
            row.edit_requested.connect (begin_edit);
            row.menu_requested.connect ((message, x, y) => {
                open_menu (row, message, x, y);
            });
            row.mention_activated.connect ((target) => {
                follow_mention.begin (target);
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

        entry.buffer.changed.connect (() => {
            offer_completions.begin ();
        });

        completion_list.row_activated.connect ((row) => {
            accept_completion (row.get_index ());
        });

        // A TextView has no placeholder of its own, so one is laid over it.
        entry.buffer.changed.connect (() => {
            placeholder.visible = entry.buffer.text == "";
        });

        edit_cancel.clicked.connect (cancel_edit);

        var keys = new Gtk.EventControllerKey ();
        keys.key_pressed.connect ((keyval, code, state) => {
            var shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;

            // While the list is up it owns these keys; otherwise Enter would
            // send the half-typed name and Up would start editing.
            if (completions_showing ()) {
                if (keyval == Gdk.Key.Escape) {
                    hide_completions ();
                    return true;
                }
                if (keyval == Gdk.Key.Down) {
                    move_completion (1);
                    return true;
                }
                if (keyval == Gdk.Key.Up) {
                    move_completion (-1);
                    return true;
                }
                if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter || keyval == Gdk.Key.Tab) {
                    var row = completion_list.get_selected_row ();
                    accept_completion (row == null ? 0 : row.get_index ());
                    return true;
                }
            }

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

        mention_button.clicked.connect (() => {
            seek_mention.begin ();
        });

        to_bottom_button.clicked.connect (() => {
            set_follow (true);
            to_bottom ();
        });

        messages.notify["chat"].connect (() => {
            // Read before cancel_edit, which empties the composer. An edit in
            // progress is not a draft: it belongs to the message being edited.
            if (drafting != null && editing == null) {
                messages.keep_draft (drafting.id, entry.buffer.text);
            }
            drafting = messages.chat;

            // The count changes as mentions are read, so the button follows the
            // chat's property rather than being set once on open.
            if (watched != null && mention_handler != 0) {
                watched.disconnect (mention_handler);
                mention_handler = 0;
            }
            watched = messages.chat;
            if (watched != null) {
                mention_handler = watched.notify["unread-mentions"].connect (sync_mentions);
            }
            sync_mentions ();

            cancel_edit ();
            set_follow (true);
            anchor = -1;
            stack.visible_child_name = messages.chat == null ? "empty" : "messages";

            if (messages.chat != null) {
                entry.buffer.text = messages.chat.draft;

                // Deferred: the stack has only just been told to show this page,
                // and a widget that is not mapped yet cannot take focus.
                Idle.add (() => {
                    entry.grab_focus ();
                    Gtk.TextIter end;
                    entry.buffer.get_end_iter (out end);
                    entry.buffer.place_cursor (end);
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
        if (messages.chat != null) {
            messages.keep_draft (messages.chat.id, "");
        }

        // Sending scrolls back down: it would be odd to send and not see it.
        set_follow (true);
        messages.send (text);
    }

    // The token being typed, if the caret sits just after an @word. Returns
    // the query without the @, or null when the caret is somewhere else.
    private string? mention_query (out int start) {
        start = -1;

        Gtk.TextIter caret;
        entry.buffer.get_iter_at_mark (out caret, entry.buffer.get_insert ());

        Gtk.TextIter line;
        entry.buffer.get_iter_at_line (out line, caret.get_line ());

        var text = entry.buffer.get_text (line, caret, false);
        var at = text.last_index_of_char ('@');
        if (at < 0) {
            return null;
        }

        // Only an @ that begins a word: an email address should not offer
        // members halfway through.
        if (at > 0 && !text[at - 1].isspace ()) {
            return null;
        }

        var word = text.substring (at + 1);
        if (word.contains (" ")) {
            return null;
        }

        start = (int) caret.get_offset () - (int) word.char_count () - 1;
        return word;
    }

    private async void offer_completions () {
        int start;
        var query = mention_query (out start);

        if (query == null || messages.chat == null || !messages.chat.is_group) {
            hide_completions ();
            return;
        }

        var found = yield messages.search_members (query);
        if (found.length == 0 && !"all".has_prefix (query.down ())) {
            hide_completions ();
            return;
        }

        // The caret may have moved on while the request was in flight.
        int now;
        if (mention_query (out now) == null) {
            hide_completions ();
            return;
        }

        candidates = {};

        // Offered while the typed token is still a prefix of "all".
        if ("all".has_prefix (query.down ())) {
            candidates += EVERYONE;
        }
        foreach (var id in found) {
            candidates += id;
        }

        mention_start = start;
        show_completions ();
    }

    private void show_completions () {
        while (completion_list.get_first_child () != null) {
            completion_list.remove (completion_list.get_first_child ());
        }

        foreach (var id in candidates) {
            var line = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10) {
                margin_start = 8, margin_end = 8, margin_top = 4, margin_bottom = 4
            };

            if (id == EVERYONE) {
                line.append (new Adw.Avatar (24, "@", true));
                line.append (new Gtk.Label ("Everyone") { halign = Gtk.Align.START });
                line.append (new Gtk.Label ("mention all the members") {
                    halign = Gtk.Align.START,
                    hexpand = true
                });
            } else {
                var avatar = new Adw.Avatar (24, messages.users.name_for (id), true);
                avatar.set_custom_image (messages.users.photo_for (id));
                line.append (avatar);
                line.append (new Gtk.Label (messages.users.name_for (id)) {
                    halign = Gtk.Align.START
                });
                line.append (new Gtk.Label ("@" + messages.users.username_for (id)) {
                    halign = Gtk.Align.START,
                    hexpand = true
                });
            }

            line.get_last_child ().add_css_class ("dim-label");
            completion_list.append (line);
        }

        completion_list.select_row (completion_list.get_row_at_index (0));
        completion_scroller.vadjustment.value = 0;
        completion_revealer.reveal_child = true;
    }

    private void hide_completions () {
        candidates = {};
        mention_start = -1;
        completion_revealer.reveal_child = false;
    }

    private bool completions_showing () {
        return completion_revealer.reveal_child && candidates.length > 0;
    }

    private void accept_completion (int index) {
        if (index < 0 || index >= candidates.length || mention_start < 0) {
            return;
        }

        if (candidates[index] == EVERYONE) {
            insert_everyone.begin (mention_start);
            hide_completions ();
            return;
        }

        var username = messages.users.username_for (candidates[index]);
        var from = mention_start;
        hide_completions ();

        Gtk.TextIter start, end;
        entry.buffer.get_iter_at_offset (out start, from);
        entry.buffer.get_iter_at_mark (out end, entry.buffer.get_insert ());
        entry.buffer.delete (ref start, ref end);
        entry.buffer.insert (ref start, @"@$username ", -1);
    }

    // Telegram sends no such thing as an everyone-mention, so this writes the
    // members out individually. Only those with a username: the rest cannot be
    // mentioned by text at all.
    private async void insert_everyone (int from) {
        var members = yield messages.mentionable_members ();
        if (members.length == 0) {
            return;
        }

        var text = new StringBuilder ();
        foreach (var id in members) {
            text.append ("@");
            text.append (messages.users.username_for (id));
            text.append (" ");
        }

        Gtk.TextIter start, end;
        entry.buffer.get_iter_at_offset (out start, from);
        entry.buffer.get_iter_at_mark (out end, entry.buffer.get_insert ());
        entry.buffer.delete (ref start, ref end);
        entry.buffer.insert (ref start, text.str, -1);
    }

    private void move_completion (int delta) {
        var row = completion_list.get_selected_row ();
        var next = (row == null ? 0 : row.get_index () + delta).clamp (0, candidates.length - 1);

        var target = completion_list.get_row_at_index (next);
        completion_list.select_row (target);
        reveal_row (target);
    }

    // A GtkListBox scrolls for its own click and focus handling, but not for a
    // row selected in code. Arrowing to a row below the fold would otherwise
    // select something the reader cannot see, which for a list driven entirely
    // by the keyboard is the whole feature.
    private void reveal_row (Gtk.ListBoxRow? row) {
        if (row == null) {
            return;
        }

        Graphene.Rect bounds;
        if (!row.compute_bounds (completion_list, out bounds)) {
            return;
        }

        var adjustment = completion_scroller.vadjustment;
        var top = (double) bounds.origin.y;
        var bottom = top + bounds.size.height;

        if (top < adjustment.value) {
            adjustment.value = top;
        } else if (bottom > adjustment.value + adjustment.page_size) {
            adjustment.value = bottom - adjustment.page_size;
        }
    }

    private void sync_mentions () {
        var count = watched == null ? 0 : watched.unread_mentions;

        mention_button.label = count > 1 ? @"@ $count" : "@";
        mention_jump.reveal_child = count > 0;
    }

    private async void seek_mention () {
        var id = yield messages.next_mention ();
        if (id == 0) {
            return;
        }

        if (!(yield messages.reach (id))) {
            return;
        }

        uint position;
        if (!messages.position_of (id, out position)) {
            return;
        }

        anchor = -1;
        set_follow (false);
        list.scroll_to (position, Gtk.ListScrollFlags.NONE, null);
        flash ((Message) messages.store.get_item (position));
    }

    private async void follow_mention (string target) {
        var chat_id = yield messages.resolve_mention (target);
        if (chat_id != 0) {
            chat_requested (chat_id);
        }
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
