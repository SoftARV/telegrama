// Notifications come from TDLib's own notification groups rather than from raw
// new-message updates. TDLib already knows what is muted, what has been read
// elsewhere and what belongs together; deciding any of that here would produce
// notifications for messages the user has already seen on their phone.
public class Telegrama.Notifier : Object {

    // Zero by default, and zero means TDLib sends no notification updates at
    // all. Nothing else in this file runs until it is raised.
    private const int GROUPS = 5;

    public Td.Client client { get; construct; }
    public AuthSession auth { get; construct; }
    public ChatList chats { get; construct; }
    public UserStore users { get; construct; }
    public Application app { get; construct; }

    public Notifier (Application app, Td.Client client, AuthSession auth, ChatList chats, UserStore users) {
        Object (app: app, client: client, auth: auth, chats: chats, users: users);
    }

    construct {
        auth.notify["stage"].connect (() => {
            if (auth.stage == AuthStage.READY) {
                enable ();
            }
        });

        if (auth.stage == AuthStage.READY) {
            enable ();
        }

        client.update.connect ((type, body) => {
            if (type == "updateNotificationGroup") {
                apply (body);
            }
        });
    }

    private void enable () {
        client.send ("setOption", (b) => {
            b.set_member_name ("name");
            b.add_string_value ("notification_group_count_max");
            b.set_member_name ("value");
            b.begin_object ();
            b.set_member_name ("@type");
            b.add_string_value ("optionValueInteger");
            b.set_member_name ("value");
            // int64 travels as a string in TDLib's JSON.
            b.add_string_value (GROUPS.to_string ());
            b.end_object ();
        });
    }

    private void apply (Json.Object body) {
        var group = (int) body.get_int_member ("notification_group_id");
        var chat_id = body.get_int_member ("chat_id");

        // Withdrawn first: a group often replaces its contents in one update.
        if (body.has_member ("removed_notification_ids")) {
            var gone = body.get_array_member ("removed_notification_ids");
            for (var i = 0; i < gone.get_length (); i++) {
                app.withdraw_notification (tag (group, (int) gone.get_int_element (i)));
            }
        }

        if (!body.has_member ("added_notifications")) {
            return;
        }

        var added = body.get_array_member ("added_notifications");
        for (var i = 0; i < added.get_length (); i++) {
            announce (group, chat_id, added.get_object_element (i));
        }
    }

    private void announce (int group, int64 chat_id, Json.Object entry) {
        var kind = entry.get_object_member ("type");
        if (kind.get_string_member ("@type") != "notificationTypeNewMessage") {
            return;
        }

        var chat = chats.find (chat_id);
        var title = chat == null ? "Telegrama" : chat.title;

        var source = kind.get_object_member ("message");
        var preview = !kind.has_member ("show_preview") || kind.get_boolean_member ("show_preview");

        var body = preview ? Content.summary (source) : "New message";

        // In a group the chat name is the title, so the sender belongs in the
        // body or there is no way to tell who spoke.
        if (preview && chat != null && chat.is_group) {
            var who = users.name_for (sender_of (source));
            if (who != "") {
                body = @"$who: $body";
            }
        }

        var note = new Notification (title);
        note.set_body (body);
        note.set_category ("im.received");
        note.set_default_action_and_target_value (
            "app.open-chat", new Variant.int64 (chat_id));

        if (entry.has_member ("is_silent") && entry.get_boolean_member ("is_silent")) {
            note.set_priority (NotificationPriority.LOW);
        }

        app.send_notification (tag (group, (int) entry.get_int_member ("id")), note);
    }

    private static int64 sender_of (Json.Object source) {
        if (!source.has_member ("sender_id")) {
            return 0;
        }

        var sender = source.get_object_member ("sender_id");
        return sender.get_string_member ("@type") == "messageSenderUser"
            ? sender.get_int_member ("user_id")
            : 0;
    }

    // Withdrawing needs the same string that was used to send.
    private static string tag (int group, int id) {
        return @"telegrama-$group-$id";
    }
}
