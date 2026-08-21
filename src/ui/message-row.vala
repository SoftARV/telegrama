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
    [GtkChild] private unowned Gtk.Box body;
    [GtkChild] private unowned Gtk.Box footer;
    [GtkChild] private unowned Gtk.Label text_label;
    [GtkChild] private unowned Gtk.Label time_label;
    [GtkChild] private unowned Gtk.Label edited_label;
    [GtkChild] private unowned Gtk.Image state_icon;
    [GtkChild] private unowned Gtk.Overlay media_frame;
    [GtkChild] private unowned Gtk.Picture media_picture;
    [GtkChild] private unowned Gtk.Box media_badge;
    [GtkChild] private unowned Gtk.Image media_badge_icon;
    [GtkChild] private unowned Gtk.Label media_note;
    [GtkChild] private unowned Gtk.Box file_frame;
    [GtkChild] private unowned Gtk.Image file_icon;
    [GtkChild] private unowned Gtk.Label file_name;
    [GtkChild] private unowned Gtk.Label file_detail;

    public signal void jump (int64 message_id);
    public signal void edit_requested (Message message);
    public signal void menu_requested (Message message, double x, double y);
    public signal void mention_activated (string target);

    public UserStore users { get; construct; }
    public MediaLoader loader { get; construct; }

    // Wide enough to be worth looking at, narrow enough that a bubble does not
    // take the whole window.
    private const int PREVIEW_MAX = 320;

    private Message? message = null;
    private ulong handler = 0;

    // Which preview this row has already gone looking for, so a refresh for
    // some unrelated property does not ask again.
    private int requested = 0;

    public MessageRow (UserStore users, MediaLoader loader) {
        Object (users: users, loader: loader);
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

        var pointer = new Gdk.Cursor.from_name ("pointer", null);
        media_frame.cursor = pointer;
        file_frame.cursor = pointer;

        var uncover = new Gtk.GestureClick ();
        uncover.released.connect (() => {
            if (message == null || message.media == null) {
                return;
            }

            if (message.media.spoiler && !message.media.revealed) {
                message.media.revealed = true;
                render_media ();
                return;
            }

            open_media ();
        });
        media_frame.add_controller (uncover);

        var open = new Gtk.GestureClick ();
        open.released.connect (() => {
            open_media ();
        });
        file_frame.add_controller (open);

        // Real links keep GTK's own handling; ours are intercepted before it
        // tries to hand a telegrama: URL to a browser.
        text_label.activate_link.connect ((uri) => {
            if (!uri.has_prefix ("telegrama:")) {
                return false;
            }
            mention_activated (uri.substring ("telegrama:".length));
            return true;
        });

        var follow = new Gtk.GestureClick ();
        follow.released.connect (() => {
            if (message != null && message.reply_to_id != 0) {
                jump (message.reply_to_id);
            }
        });
        reply_box.add_controller (follow);

        // Capture phase: a selectable Gtk.Label brings its own menu offering
        // cut, paste and delete on text that is not editable. Claiming the
        // click before it reaches the label replaces that with ours.
        var secondary = new Gtk.GestureClick () {
            button = 3,
            propagation_phase = Gtk.PropagationPhase.CAPTURE
        };
        secondary.pressed.connect ((n, x, y) => {
            if (message == null || message.is_service) {
                return;
            }
            secondary.set_state (Gtk.EventSequenceState.CLAIMED);
            menu_requested (message, x, y);
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
        requested = 0;
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

    // Telegram tucks the stamp onto the last line of a short message rather
    // than always giving it a line of its own. There is no GTK layout that does
    // this, so the text and the stamp are measured and laid side by side when
    // they fit.
    private void shape_body () {
        if (message == null) {
            return;
        }

        var metrics = text_label.get_pango_context ().get_metrics (null, null);
        var char_width = metrics.get_approximate_char_width () / Pango.SCALE;
        var limit = char_width * text_label.max_width_chars;

        // Measured from the plain text: the label holds Pango markup, whose
        // tags would count towards the width.
        var layout = text_label.create_pango_layout (message.text);
        int text_width, text_height;
        layout.get_pixel_size (out text_width, out text_height);

        int stamp_min, stamp_natural, ignored_a, ignored_b;
        footer.measure (Gtk.Orientation.HORIZONTAL, -1,
            out stamp_min, out stamp_natural, out ignored_a, out ignored_b);

        var one_line = layout.get_line_count () == 1;
        var fits = one_line && text_width + stamp_natural + body.spacing <= limit;

        body.orientation = fits ? Gtk.Orientation.HORIZONTAL : Gtk.Orientation.VERTICAL;
    }

    private void render_media () {
        var media = message.media;

        text_label.visible = media == null || message.text != "";

        if (media == null) {
            media_frame.visible = false;
            file_frame.visible = false;
            return;
        }

        if (!media.kind.is_picture ()) {
            media_frame.visible = false;
            file_frame.visible = true;
            file_icon.icon_name = media.kind.icon ();
            file_name.label = media.file_name != "" ? media.file_name : media.kind.label ();
            file_detail.label = media.detail ();
            return;
        }

        file_frame.visible = false;
        media_frame.visible = true;
        size_preview (media);

        media_picture.paintable = media.blur;

        var hidden = media.spoiler && !media.revealed;

        media_badge.visible = hidden || media.kind == MediaKind.VIDEO
            || media.kind == MediaKind.ANIMATION;
        media_badge_icon.icon_name = hidden
            ? "view-conceal-symbolic"
            : "media-playback-start-symbolic";

        media_note.visible = !hidden && media.duration > 0;
        media_note.label = media.duration_text ();

        // A spoiler is meant to stay unreadable, and the blur already is.
        if (hidden) {
            return;
        }

        var sharp = loader.cached (media.preview_id);
        if (sharp != null) {
            media_picture.paintable = sharp;
            return;
        }

        if (requested == media.preview_id) {
            return;
        }
        requested = media.preview_id;

        var target = message;
        loader.load.begin (media, (source, result) => {
            var texture = loader.load.end (result);
            // The row is recycled, so it may be showing something else by now.
            if (texture != null && message == target) {
                media_picture.paintable = texture;
            }
        });
    }

    // Hands the file to whatever the desktop uses for it. Downloading it first
    // is the whole of the wait, so the bubble reports how far along it is.
    private void open_media () {
        if (message == null || message.media == null || message.media.opening) {
            return;
        }

        message.media.opening = true;
        launch.begin (message.media, message);
    }

    private async void launch (Media media, Message target) {
        var watcher = loader.files.progress.connect ((id, fraction) => {
            if (id == media.file_id && message == target) {
                report (media, fraction);
            }
        });

        var path = media.path != ""
            ? media.path
            : yield loader.files.fetch (media.file_id, FileStore.PRIORITY_OPENED);

        SignalHandler.disconnect (loader.files, watcher);
        media.opening = false;
        media.path = path;

        if (message == target) {
            render_media ();
        }

        if (path == "") {
            warning ("could not download %s", media.kind.label ());
            return;
        }

        try {
            var launcher = new Gtk.FileLauncher (File.new_for_path (path));
            yield launcher.launch (get_root () as Gtk.Window, null);
        } catch (Error e) {
            warning ("could not open %s: %s", path, e.message);
        }
    }

    private void report (Media media, double fraction) {
        var percent = "%d%%".printf ((int) (fraction * 100));

        if (media.kind.is_picture ()) {
            media_note.visible = true;
            media_note.label = percent;
        } else {
            file_detail.label = percent;
        }
    }

    // Reserved from the dimensions in the message, so the bubble is the right
    // shape before any pixels arrive and the history does not shift when they
    // do. Never scaled up: a small picture blown out to fill the box is worse
    // than a small picture.
    private void size_preview (Media media) {
        var width = media.width > 0 ? media.width : PREVIEW_MAX;
        var height = media.height > 0 ? media.height : PREVIEW_MAX;

        var scale = double.min (
            double.min ((double) PREVIEW_MAX / width, (double) PREVIEW_MAX / height),
            1.0
        );

        media_picture.set_size_request ((int) (width * scale), (int) (height * scale));
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

        // A stand-in like "Location" should not read as if someone typed it.
        // A caption under a picture is exactly that, so it stays plain.
        if (message.is_media && message.media == null) {
            text_label.add_css_class ("dim-label");
        } else {
            text_label.remove_css_class ("dim-label");
        }

        render_media ();

        time_label.label = new DateTime.from_unix_local (message.date).format ("%H:%M");

        shape_body ();

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
