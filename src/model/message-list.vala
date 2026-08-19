// One chat's history. Retargeted rather than recreated when the selection
// changes, so there is only ever one open chat and one set of subscriptions.
public class Telegrama.MessageList : Object {

    private const int PAGE = 50;

    // A first page can be a single message. Below this, keep asking rather than
    // waiting for a scroll that will never come in a view with nothing to
    // scroll.
    private const uint MIN_HISTORY = 30;

    public Td.Client client { get; construct; }
    public UserStore users { get; construct; }
    public ListStore store { get; construct; }

    public Chat? chat { get; private set; default = null; }
    public bool loading { get; private set; default = false; }

    // Raised when older messages have been added, so the view can put the
    // viewport back where the reader left it.
    public signal void prepended ();
    public signal void appended ();

    private HashTable<string, Message> by_id = new HashTable<string, Message> (str_hash, str_equal);
    private bool exhausted = false;

    public MessageList (Td.Client client, UserStore users) {
        Object (client: client, users: users, store: new ListStore (typeof (Message)));
    }

    construct {
        client.update.connect (on_update);

        users.learned.connect ((id, name) => {
            for (uint i = 0; i < store.get_n_items (); i++) {
                var message = (Message) store.get_item (i);
                if (message.sender_id != id) {
                    continue;
                }
                if (chat != null && chat.is_group) {
                    message.sender_name = name;
                }
            }
        });
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
        client.send ("openChat", (b) => {
            b.set_member_name ("chat_id");
            b.add_int_value (chat.id);
        });

        load_from.begin (0);
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
            service
        );

        message.sender_name = chat.is_group ? users.name_for (message.sender_id) : "";

        if (service) {
            message.text = Content.notice (content, users.name_for (message.sender_id));
        } else {
            message.text = Content.full (source);
            message.formatted = formatted_of (content);
        }

        by_id.insert (key, message);
        return message;
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

            case "updateMessageContent":
                if (body.get_int_member ("chat_id") != chat.id) {
                    return;
                }

                var edited = by_id.lookup (body.get_int_member ("message_id").to_string ());
                if (edited != null) {
                    edited.text = Content.describe (body.get_object_member ("new_content"));
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
