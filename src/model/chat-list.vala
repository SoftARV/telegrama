// TDLib will not hand over an ordered list; loadChats only asks it to start
// sending updates, and the order is something the client maintains itself.
public class Telegrama.ChatList : Object {

    private const int PAGE = 40;

    public Td.Client client { get; construct; }
    public AuthSession auth { get; construct; }
    public ListStore store { get; construct; }

    private HashTable<string, Chat> by_id = new HashTable<string, Chat> (str_hash, str_equal);

    // Chats waiting on an avatar, keyed by the TDLib file id they are waiting for.
    private HashTable<string, Chat> awaiting_photo = new HashTable<string, Chat> (str_hash, str_equal);
    private uint resort_source = 0;
    private bool loading = false;
    private bool exhausted = false;

    public ChatList (Td.Client client, AuthSession auth) {
        Object (client: client, auth: auth, store: new ListStore (typeof (Chat)));
    }

    construct {
        client.update.connect (on_update);

        auth.notify["stage"].connect (() => {
            if (auth.stage == AuthStage.READY) {
                load.begin ();
            } else {
                reset ();
            }
        });

        if (auth.stage == AuthStage.READY) {
            load.begin ();
        }
    }

    public Chat? find (int64 id) {
        return by_id.lookup (id.to_string ());
    }

    public async void load () {
        if (loading || exhausted) {
            return;
        }
        loading = true;

        try {
            yield client.request ("loadChats", (b) => {
                b.set_member_name ("chat_list");
                b.begin_object ();
                b.set_member_name ("@type");
                b.add_string_value ("chatListMain");
                b.end_object ();
                b.set_member_name ("limit");
                b.add_int_value (PAGE);
            });
        } catch (Td.ClientError.NOT_FOUND e) {
            exhausted = true;
        } catch (Td.ClientError e) {
            warning ("%s", e.message);
        }

        loading = false;
    }

    private void reset () {
        store.remove_all ();
        by_id.remove_all ();
        awaiting_photo.remove_all ();
        exhausted = false;
    }

    private void on_update (string type, Json.Object body) {
        switch (type) {
            case "updateNewChat":
                apply_chat (body.get_object_member ("chat"));
                break;

            case "updateChatTitle":
                lookup (body).title = body.get_string_member ("title");
                break;

            case "updateChatPhoto":
                apply_photo (lookup (body), body.has_member ("photo")
                    ? body.get_object_member ("photo")
                    : null);
                break;

            case "updateFile":
                apply_downloaded (body.get_object_member ("file"));
                break;

            case "updateChatLastMessage":
                var chat = lookup (body);
                if (body.has_member ("last_message")) {
                    apply_last_message (chat, body.get_object_member ("last_message"));
                }
                apply_positions (chat, body.get_array_member ("positions"));
                break;

            case "updateChatPosition":
                apply_position (lookup (body), body.get_object_member ("position"));
                break;

            case "updateChatDraftMessage":
                apply_positions (lookup (body), body.get_array_member ("positions"));
                break;

            case "updateChatReadOutbox":
                lookup (body).last_read_outbox = body.get_int_member ("last_read_outbox_message_id");
                break;

            case "updateChatReadInbox":
                lookup (body).unread_count = (int) body.get_int_member ("unread_count");
                break;

            case "updateChatRemovedFromList":
                if (is_main_list (body.get_object_member ("chat_list"))) {
                    var chat = lookup (body);
                    chat.order = 0;
                    place (chat);
                }
                break;

            default:
                break;
        }
    }

    private void apply_chat (Json.Object source) {
        var chat = intern (source.get_int_member ("id"));

        chat.title = source.get_string_member ("title");
        chat.is_group = is_group (source);
        chat.unread_count = (int) source.get_int_member ("unread_count");
        chat.last_read_outbox = source.get_int_member ("last_read_outbox_message_id");

        if (source.has_member ("last_message")) {
            apply_last_message (chat, source.get_object_member ("last_message"));
        }

        apply_photo (chat, source.has_member ("photo") ? source.get_object_member ("photo") : null);
        apply_positions (chat, source.get_array_member ("positions"));
    }

    private void apply_photo (Chat chat, Json.Object? info) {
        if (info == null || !info.has_member ("small")) {
            chat.photo = null;
            return;
        }

        var small = info.get_object_member ("small");
        var id = ((int) small.get_int_member ("id")).to_string ();
        var local = small.get_object_member ("local");

        // Already on disk from an earlier run: TDLib keeps its file cache across
        // sessions, so most avatars never need downloading twice.
        if (local.get_boolean_member ("is_downloading_completed")) {
            load_photo (chat, local.get_string_member ("path"));
            return;
        }

        awaiting_photo.insert (id, chat);
        client.send ("downloadFile", (b) => {
            b.set_member_name ("file_id");
            b.add_int_value (small.get_int_member ("id"));
            b.set_member_name ("priority");
            b.add_int_value (16);
            b.set_member_name ("offset");
            b.add_int_value (0);
            b.set_member_name ("limit");
            b.add_int_value (0);
            b.set_member_name ("synchronous");
            b.add_boolean_value (false);
        });
    }

    // updateFile arrives for every download in flight, most of which are not ours.
    private void apply_downloaded (Json.Object file) {
        var id = ((int) file.get_int_member ("id")).to_string ();
        var chat = awaiting_photo.lookup (id);
        if (chat == null) {
            return;
        }

        var local = file.get_object_member ("local");
        if (!local.get_boolean_member ("is_downloading_completed")) {
            return;
        }

        awaiting_photo.remove (id);
        load_photo (chat, local.get_string_member ("path"));
    }

    // Avatars are a few kilobytes, so the read is not worth an async round trip.
    private void load_photo (Chat chat, string path) {
        if (path == "") {
            return;
        }

        try {
            chat.photo = Gdk.Texture.from_filename (path);
        } catch (Error e) {
            warning ("could not load avatar %s: %s", path, e.message);
        }
    }

    private void apply_last_message (Chat chat, Json.Object? message) {
        if (message == null) {
            return;
        }

        chat.preview = Content.summary (message);
        chat.date = message.get_int_member ("date");
    }

    private void apply_positions (Chat chat, Json.Array? positions) {
        if (positions == null) {
            return;
        }

        for (var i = 0; i < positions.get_length (); i++) {
            apply_position (chat, positions.get_object_element (i));
        }
    }

    private void apply_position (Chat chat, Json.Object position) {
        if (!is_main_list (position.get_object_member ("list"))) {
            return;
        }

        chat.is_pinned = position.get_boolean_member ("is_pinned");
        chat.order = read_int64 (position, "order");
        place (chat);
    }

    private void place (Chat chat) {
        uint position;
        var present = store.find (chat, out position);

        if (chat.order == 0) {
            if (present) {
                store.remove (position);
            }
            return;
        }

        if (!present) {
            store.append (chat);
        }

        schedule_resort ();
    }

    // Updates arrive in bursts, and every one of them can move a chat. Sorting
    // once when the burst settles beats sorting per update.
    private void schedule_resort () {
        if (resort_source != 0) {
            return;
        }

        resort_source = Idle.add (() => {
            resort_source = 0;
            store.sort ((a, b) => {
                var left = (Chat) a;
                var right = (Chat) b;

                // TDLib orders by (order, id) descending; without the id the
                // sort is unstable whenever two chats share an order.
                if (left.order != right.order) {
                    return right.order > left.order ? 1 : -1;
                }
                if (left.id == right.id) {
                    return 0;
                }
                return right.id > left.id ? 1 : -1;
            });
            return Source.REMOVE;
        });
    }

    private Chat lookup (Json.Object body) {
        return intern (body.get_int_member ("chat_id"));
    }

    private Chat intern (int64 id) {
        var key = id.to_string ();
        var chat = by_id.lookup (key);

        if (chat == null) {
            chat = new Chat (id);
            by_id.insert (key, chat);
        }

        return chat;
    }

    private static bool is_group (Json.Object source) {
        if (!source.has_member ("type")) {
            return false;
        }

        var kind = source.get_object_member ("type").get_string_member ("@type");
        return kind == "chatTypeBasicGroup" || kind == "chatTypeSupergroup";
    }

    private static bool is_main_list (Json.Object? list) {
        return list != null
            && list.has_member ("@type")
            && list.get_string_member ("@type") == "chatListMain";
    }

    // int53 fields arrive as JSON numbers but int64 fields arrive as strings.
    // Reading either shape keeps a wrong guess from collapsing every order to
    // zero and scrambling the list.
    private static int64 read_int64 (Json.Object obj, string member) {
        if (!obj.has_member (member)) {
            return 0;
        }

        var node = obj.get_member (member);
        if (node.get_value_type () == typeof (string)) {
            return int64.parse (node.get_string ());
        }

        return node.get_int ();
    }


}
