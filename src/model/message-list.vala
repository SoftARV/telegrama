// One chat's history. Retargeted rather than recreated when the selection
// changes, so there is only ever one open chat and one set of subscriptions.
public class Telegrama.MessageList : Object {

    private const int PAGE = 50;

    // A first page can be a single message. Below this, keep asking rather than
    // waiting for a scroll that will never come in a view with nothing to
    // scroll.
    private const uint MIN_HISTORY = 30;

    // Pages to page back through before giving up on reaching a message.
    private const int PAGE_LIMIT = 12;

    public Td.Client client { get; construct; }
    public UserStore users { get; construct; }
    public ListStore store { get; construct; }

    public Chat? chat { get; private set; default = null; }
    public bool loading { get; private set; default = false; }

    // Raised when older messages have been added, so the view can put the
    // viewport back where the reader left it.
    public signal void prepended ();
    public signal void appended ();

    // Who is typing, phrased for the header. Empty when nobody is.
    public string activity { get; private set; default = ""; }

    private HashTable<string, Message> by_id = new HashTable<string, Message> (str_hash, str_equal);
    private bool exhausted = false;
    private int64[] seen = {};
    private uint seen_source = 0;
    private uint activity_source = 0;

    public MessageList (Td.Client client, UserStore users) {
        Object (client: client, users: users, store: new ListStore (typeof (Message)));
    }

    construct {
        client.update.connect (on_update);

    }

    public void open (Chat? target) {
        if (chat != null && (target == null || target.id != chat.id)) {
            client.send ("closeChat", (b) => {
                b.set_member_name ("chat_id");
                b.add_int_value (chat.id);
            });
        }

        store.remove_all ();
        by_id.remove_all ();
        exhausted = false;
        chat = target;

        if (chat == null) {
            return;
        }

        // Supergroups and channels only deliver updates while the chat is open,
        // so this is required rather than merely polite.
        chat.notify["last-read-outbox"].connect (refresh_read);

        client.send ("openChat", (b) => {
            b.set_member_name ("chat_id");
            b.add_int_value (chat.id);
        });

        load_from.begin (0);
    }

    public bool position_of (int64 message_id, out uint position) {
        position = 0;

        var target = by_id.lookup (message_id.to_string ());
        return target != null && store.find (target, out position);
    }

    // Paging back until the message turns up keeps the store one contiguous
    // run. Loading a window around it instead would be quicker but would leave
    // a hole in the middle of the history.
    public async bool reach (int64 message_id) {
        uint position;

        for (var attempt = 0; attempt < PAGE_LIMIT; attempt++) {
            if (position_of (message_id, out position)) {
                return true;
            }
            if (exhausted || store.get_n_items () == 0) {
                return false;
            }

            var before = store.get_n_items ();
            yield load_from (((Message) store.get_item (0)).id);

            if (store.get_n_items () == before) {
                return false;
            }
        }

        return position_of (message_id, out position);
    }

    public void send (string text) {
        if (chat == null || text.strip () == "") {
            return;
        }

        var target = chat.id;
        client.send ("sendMessage", (b) => {
            b.set_member_name ("chat_id");
            b.add_int_value (target);
            b.set_member_name ("input_message_content");
            b.begin_object ();
            b.set_member_name ("@type");
            b.add_string_value ("inputMessageText");
            b.set_member_name ("text");
            b.begin_object ();
            b.set_member_name ("@type");
            b.add_string_value ("formattedText");
            b.set_member_name ("text");
            b.add_string_value (text);
            b.end_object ();
            b.end_object ();
        });
    }

    public void edit (int64 message_id, string text) {
        if (chat == null || text.strip () == "") {
            return;
        }

        var target = chat.id;
        client.send ("editMessageText", (b) => {
            b.set_member_name ("chat_id");
            b.add_int_value (target);
            b.set_member_name ("message_id");
            b.add_int_value (message_id);
            b.set_member_name ("input_message_content");
            b.begin_object ();
            b.set_member_name ("@type");
            b.add_string_value ("inputMessageText");
            b.set_member_name ("text");
            b.begin_object ();
            b.set_member_name ("@type");
            b.add_string_value ("formattedText");
            b.set_member_name ("text");
            b.add_string_value (text);
            b.end_object ();
            b.end_object ();
        });
    }

    // revoke removes it for everyone; without it the message only goes from our
    // own history. TDLib forces revoke in supergroups, channels and secret chats
    // regardless of what is passed.
    public void discard (int64 message_id, bool revoke) {
        if (chat == null) {
            return;
        }

        var target = chat.id;
        client.send ("deleteMessages", (b) => {
            b.set_member_name ("chat_id");
            b.add_int_value (target);
            b.set_member_name ("message_ids");
            b.begin_array ();
            b.add_int_value (message_id);
            b.end_array ();
            b.set_member_name ("revoke");
            b.add_boolean_value (revoke);
        });
    }

    // Walked from the end, since editing almost always means the last thing
    // said rather than something further back.
    public Message? last_editable () {
        for (var i = (int) store.get_n_items () - 1; i >= 0; i--) {
            var message = (Message) store.get_item (i);
            if (message.editable) {
                return message;
            }
        }
        return null;
    }

    // Batched: binding a screenful of rows would otherwise be a request each.
    public void saw (int64 message_id) {
        if (chat == null) {
            return;
        }

        seen += message_id;

        if (seen_source == 0) {
            seen_source = Timeout.add (400, () => {
                seen_source = 0;
                flush_seen ();
                return Source.REMOVE;
            });
        }
    }

    private void flush_seen () {
        if (chat == null || seen.length == 0) {
            return;
        }

        var batch = seen;
        seen = {};
        var target = chat.id;

        client.send ("viewMessages", (b) => {
            b.set_member_name ("chat_id");
            b.add_int_value (target);
            b.set_member_name ("message_ids");
            b.begin_array ();
            foreach (var id in batch) {
                b.add_int_value (id);
            }
            b.end_array ();
            b.set_member_name ("source");
            b.begin_object ();
            b.set_member_name ("@type");
            b.add_string_value ("messageSourceChatHistory");
            b.end_object ();
            b.set_member_name ("force_read");
            b.add_boolean_value (false);
        });
    }

    private void refresh_read () {
        if (chat == null) {
            return;
        }

        for (uint i = 0; i < store.get_n_items (); i++) {
            var message = (Message) store.get_item (i);
            message.read = message.is_outgoing && message.id <= chat.last_read_outbox;
        }
    }

    public void load_older () {
        if (loading || exhausted || chat == null || store.get_n_items () == 0) {
            return;
        }

        load_from.begin (((Message) store.get_item (0)).id);
    }

    private async void load_from (int64 from_message_id) {
        if (loading || chat == null) {
            return;
        }
        loading = true;

        var target = chat.id;
        var added = 0;

        // The first request for a chat routinely comes back empty while TDLib
        // fetches, and answering that with "no history" would be wrong.
        for (var attempt = 0; attempt < 2 && added == 0; attempt++) {
            Json.Object response;
            try {
                response = yield client.request ("getChatHistory", (b) => {
                    b.set_member_name ("chat_id");
                    b.add_int_value (target);
                    b.set_member_name ("from_message_id");
                    b.add_int_value (from_message_id);
                    b.set_member_name ("offset");
                    b.add_int_value (0);
                    b.set_member_name ("limit");
                    b.add_int_value (PAGE);
                    b.set_member_name ("only_local");
                    b.add_boolean_value (false);
                });
            } catch (Td.ClientError e) {
                warning ("%s", e.message);
                break;
            }

            // The selection moved on while we were waiting.
            if (chat == null || chat.id != target) {
                loading = false;
                return;
            }

            added = absorb (response.get_array_member ("messages"));
        }

        // Released before the signals: a handler that reacts by asking for more
        // would otherwise be turned away by the guard above, and with nothing
        // left to move the adjustment, nothing would ever ask again.
        loading = false;

        if (added == 0) {
            exhausted = true;
            return;
        }

        if (from_message_id != 0) {
            prepended ();
        } else {
            appended ();
        }

        if (!exhausted && store.get_n_items () < MIN_HISTORY) {
            load_from.begin (((Message) store.get_item (0)).id);
        }
    }

    // getChatHistory answers newest first; the store runs oldest first.
    private int absorb (Json.Array messages) {
        var fresh = new GenericArray<Object> ();

        for (var i = (int) messages.get_length () - 1; i >= 0; i--) {
            var message = build (messages.get_object_element (i));
            if (message != null) {
                fresh.add (message);
            }
        }

        if (fresh.length == 0) {
            return 0;
        }

        store.splice (0, 0, fresh.data);
        return fresh.length;
    }

    private Message? build (Json.Object source) {
        var id = source.get_int_member ("id");
        var key = id.to_string ();

        if (by_id.contains (key)) {
            return null;
        }

        var content = source.get_object_member ("content");
        var service = Content.is_service (content);

        var message = new Message (
            id,
            sender_of (source),
            source.get_boolean_member ("is_outgoing"),
            source.get_int_member ("date"),
            !service && content.get_string_member ("@type") != "messageText",
            service,
            chat.is_group
        );

        apply_state (message, source);

        if (service) {
            message.text = Content.notice (content, users.name_for (message.sender_id));
        } else {
            resolve_reply (message, source);
            message.text = Content.full (source);
            message.formatted = formatted_of (content);
        }

        by_id.insert (key, message);
        return message;
    }

    private void apply_state (Message message, Json.Object source) {
        if (source.has_member ("sending_state")) {
            var state = source.get_object_member ("sending_state").get_string_member ("@type");
            message.sending = state == "messageSendingStatePending";
            message.failed = state == "messageSendingStateFailed";
        } else {
            message.sending = false;
            message.failed = false;
        }

        message.read = message.is_outgoing
            && chat != null
            && message.id <= chat.last_read_outbox;

        message.edited = source.has_member ("edit_date") && source.get_int_member ("edit_date") > 0;
    }

    // A reply to a message in the same chat carries only its id: origin and
    // content are filled in only when the reply crosses chats. So the quoted
    // text comes from what is already loaded, or from TDLib if it is not.
    private void resolve_reply (Message message, Json.Object source) {
        if (!source.has_member ("reply_to")) {
            return;
        }

        var reply = source.get_object_member ("reply_to");
        if (reply.get_string_member ("@type") != "messageReplyToMessage") {
            return;
        }

        message.reply_to_id = reply.get_int_member ("message_id");
        if (message.reply_to_id == 0) {
            return;
        }

        // A manually chosen quote is what the sender meant to point at, so it
        // wins over the whole message.
        if (reply.has_member ("quote")) {
            var quote = reply.get_object_member ("quote");
            message.reply_preview = quote.get_object_member ("text").get_string_member ("text")
                .replace ("\n", " ").strip ();
        }

        var known = by_id.lookup (message.reply_to_id.to_string ());
        if (known != null) {
            message.reply_sender_id = known.sender_id;
            if (message.reply_preview == "") {
                message.reply_preview = known.text.replace ("\n", " ").strip ();
            }
            return;
        }

        fetch_reply.begin (message, source.get_int_member ("chat_id"));
    }

    private async void fetch_reply (Message message, int64 chat_id) {
        try {
            var source = yield client.request ("getMessage", (b) => {
                b.set_member_name ("chat_id");
                b.add_int_value (chat_id);
                b.set_member_name ("message_id");
                b.add_int_value (message.reply_to_id);
            });

            message.reply_sender_id = sender_of (source);
            if (message.reply_preview == "") {
                message.reply_preview = Content.summary (source);
            }
        } catch (Td.ClientError e) {
            // Deleted, or too old for TDLib to still have it.
            if (message.reply_preview == "") {
                message.reply_preview = "Message unavailable";
            }
        }
    }

    // Only text and captions carry entities; everything else renders as a label.
    private static Json.Object? formatted_of (Json.Object content) {
        if (content.get_string_member ("@type") == "messageText") {
            return content.get_object_member ("text");
        }
        if (content.has_member ("caption")) {
            return content.get_object_member ("caption");
        }
        return null;
    }

    private static int64 sender_of (Json.Object source) {
        if (!source.has_member ("sender_id")) {
            return 0;
        }

        var sender = source.get_object_member ("sender_id");
        switch (sender.get_string_member ("@type")) {
            case "messageSenderUser":
                return sender.get_int_member ("user_id");
            case "messageSenderChat":
                return sender.get_int_member ("chat_id");
            default:
                return 0;
        }
    }

    private void on_update (string type, Json.Object body) {
        if (chat == null) {
            return;
        }

        switch (type) {
            case "updateNewMessage":
                var source = body.get_object_member ("message");
                if (source.get_int_member ("chat_id") != chat.id) {
                    return;
                }

                var message = build (source);
                if (message != null) {
                    store.append (message);
                    appended ();
                }
                break;

            case "updateMessageSendSucceeded":
                if (body.get_object_member ("message").get_int_member ("chat_id") != chat.id) {
                    return;
                }
                promote (body.get_int_member ("old_message_id"), body.get_object_member ("message"));
                break;

            case "updateMessageSendFailed":
                if (body.get_object_member ("message").get_int_member ("chat_id") != chat.id) {
                    return;
                }
                var doomed = by_id.lookup (body.get_int_member ("old_message_id").to_string ());
                if (doomed != null) {
                    doomed.sending = false;
                    doomed.failed = true;
                }
                break;

            case "updateChatAction":
                if (body.get_int_member ("chat_id") == chat.id) {
                    note_activity (body);
                }
                break;

            case "updateMessageEdited":
                if (body.get_int_member ("chat_id") != chat.id) {
                    return;
                }
                var touched = by_id.lookup (body.get_int_member ("message_id").to_string ());
                if (touched != null) {
                    touched.edited = body.get_int_member ("edit_date") > 0;
                }
                break;

            case "updateMessageContent":
                if (body.get_int_member ("chat_id") != chat.id) {
                    return;
                }

                var changed = by_id.lookup (body.get_int_member ("message_id").to_string ());
                if (changed != null) {
                    var fresh = body.get_object_member ("new_content");
                    changed.text = Content.describe (fresh);
                    changed.formatted = formatted_of (fresh);
                }
                break;

            case "updateDeleteMessages":
                if (body.get_int_member ("chat_id") != chat.id) {
                    return;
                }
                remove_all (body.get_array_member ("message_ids"));
                break;

            default:
                break;
        }
    }

    // The temporary id is replaced in place. Removing and re-inserting would
    // make the message visibly jump the moment the server accepted it.
    private void promote (int64 old_id, Json.Object source) {
        var message = by_id.lookup (old_id.to_string ());
        if (message == null) {
            return;
        }

        by_id.remove (old_id.to_string ());
        message.id = source.get_int_member ("id");
        by_id.insert (message.id.to_string (), message);

        apply_state (message, source);
    }

    private void note_activity (Json.Object body) {
        var sender = body.get_object_member ("sender_id");
        var who = sender.get_string_member ("@type") == "messageSenderUser"
            ? users.name_for (sender.get_int_member ("user_id"))
            : "";

        var kind = body.get_object_member ("action").get_string_member ("@type");
        if (kind == "chatActionCancel") {
            activity = "";
            return;
        }

        activity = who == "" ? "typing…" : @"$who is typing…";

        // TDLib does not always send a cancel, so this expires on its own.
        if (activity_source != 0) {
            Source.remove (activity_source);
        }
        activity_source = Timeout.add_seconds (5, () => {
            activity = "";
            activity_source = 0;
            return Source.REMOVE;
        });
    }

    private void remove_all (Json.Array ids) {
        for (var i = 0; i < ids.get_length (); i++) {
            var key = ids.get_int_element (i).to_string ();
            var message = by_id.lookup (key);
            if (message == null) {
                continue;
            }

            uint position;
            if (store.find (message, out position)) {
                store.remove (position);
            }
            by_id.remove (key);
        }
    }
}
