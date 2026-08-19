[GtkTemplate (ui = "/dev/miguel/Telegrama/message-row.ui")]
public class Telegrama.MessageRow : Gtk.Box {

    [GtkChild] private unowned Gtk.Label service_label;
    [GtkChild] private unowned Gtk.Box line;
    [GtkChild] private unowned Adw.Avatar avatar;
    [GtkChild] private unowned Gtk.Box bubble;
    [GtkChild] private unowned Gtk.Label sender_label;
    [GtkChild] private unowned Gtk.Box reply_box;
    [GtkChild] private unowned Gtk.Label reply_sender;
    [GtkChild] private unowned Gtk.Label reply_text;
    [GtkChild] private unowned Gtk.Label text_label;
    [GtkChild] private unowned Gtk.Label time_label;
    [GtkChild] private unowned Gtk.Label edited_label;
    [GtkChild] private unowned Gtk.Image state_icon;

    public signal void jump (int64 message_id);
    public signal void edit_requested (Message message);

    public UserStore users { get; construct; }

    private Message? message = null;
    private ulong handler = 0;
    private Gtk.Popover? menu = null;

    public MessageRow (UserStore users) {
        Object (users: users);
    }

    construct {
        // A sender's name, colour and picture usually arrive after the messages
        // that need them, so the row repaints when its own sender turns up.
        users.changed.connect ((id) => {
            if (message != null && (message.sender_id == id || message.reply_sender_id == id)) {
                refresh ();
            }
        });

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

        var follow = new Gtk.GestureClick ();
        follow.released.connect (() => {
            if (message != null && message.reply_to_id != 0) {
                jump (message.reply_to_id);
            }
        });
        reply_box.add_controller (follow);

        var secondary = new Gtk.GestureClick () { button = 3 };
        secondary.pressed.connect ((n, x, y) => {
            if (message != null && message.editable) {
                open_menu (x, y);
            }
        });
        add_controller (secondary);
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

    private void open_menu (double x, double y) {
        if (menu == null) {
            var edit = new Gtk.Button.with_label ("Edit") {
                has_frame = false
            };
            edit.clicked.connect (() => {
                menu.popdown ();
                if (message != null) {
                    edit_requested (message);
                }
            });

            menu = new Gtk.Popover () {
                child = edit,
                has_arrow = false,
                autohide = true
            };
            menu.set_parent (this);
        }

        menu.set_pointing_to ({ (int) x, (int) y, 1, 1 });
        menu.popup ();
    }

    // Popovers are parented rather than owned, so GTK wants them taken down by
    // hand before the row goes.
    public override void dispose () {
        if (menu != null) {
            menu.unparent ();
            menu = null;
        }
        base.dispose ();
    }

    private void refresh () {
        if (message == null) {
            return;
        }

        service_label.visible = message.is_service;
        line.visible = !message.is_service;

        if (message.is_service) {
            service_label.label = message.text;
            return;
        }

        line.halign = message.is_outgoing ? Gtk.Align.END : Gtk.Align.START;

        // Named and pictured only where there is more than one other person.
        var attributed = message.in_group && !message.is_outgoing;
        var name = attributed ? users.name_for (message.sender_id) : "";

        bubble.remove_css_class (message.is_outgoing ? "bubble-in" : "bubble-out");
        bubble.add_css_class (message.is_outgoing ? "bubble-out" : "bubble-in");

        sender_label.visible = name != "";
        if (name != "") {
            // Telegram assigns each person a colour; this shows theirs rather
            // than picking one.
            var colour = users.colour_for (message.sender_id);
            sender_label.label = @"<span foreground=\"$colour\">$(Markup.escape_text (name))</span>";
        }

        bubble.remove_css_class ("flash-a");
        bubble.remove_css_class ("flash-b");
        if (message.highlighted) {
            bubble.add_css_class (message.flash_variant ? "flash-b" : "flash-a");
        }

        reply_box.visible = message.reply_to_id != 0;
        if (reply_box.visible) {
            var replied = users.name_for (message.reply_sender_id);
            reply_sender.visible = replied != "";
            if (replied != "") {
                var tint = users.colour_for (message.reply_sender_id);
                reply_sender.label =
                    @"<span foreground=\"$tint\">$(Markup.escape_text (replied))</span>";
            }
            reply_text.label = message.reply_preview;
        }

        avatar.visible = attributed;
        if (attributed) {
            avatar.text = name;
            avatar.set_custom_image (users.photo_for (message.sender_id));
        }

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

        edited_label.visible = message.edited;

        // Only our own messages have a delivery state worth reporting. Drawn
        // icons rather than tick characters, which render at the mercy of
        // whichever font happens to carry them.
        state_icon.visible = message.is_outgoing;
        if (message.is_outgoing) {
            if (message.failed) {
                state_icon.icon_name = "telegrama-status-failed-symbolic";
            } else if (message.sending) {
                state_icon.icon_name = "telegrama-status-sending-symbolic";
            } else if (message.read) {
                state_icon.icon_name = "telegrama-status-delivered-symbolic";
            } else {
                state_icon.icon_name = "telegrama-status-sent-symbolic";
            }
        }
    }
}
