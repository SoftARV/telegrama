// TDLib will not hand over an ordered list; loadChats only asks it to start
// sending updates, and the order is something the client maintains itself.
public class Telegrama.ChatList : Object {

    private const int PAGE = 40;

    public Td.Client client { get; construct; }
    public AuthSession auth { get; construct; }
    public ListStore store { get; construct; }

    private HashTable<string, Chat> by_id = new HashTable<string, Chat> (str_hash, str_equal);
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
        chat.unread_count = (int) source.get_int_member ("unread_count");

        if (source.has_member ("last_message")) {
            apply_last_message (chat, source.get_object_member ("last_message"));
        }

        apply_positions (chat, source.get_array_member ("positions"));
    }

    private void apply_last_message (Chat chat, Json.Object? message) {
        if (message == null) {
            return;
        }

        chat.preview = preview_of (message);
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

    private static string preview_of (Json.Object message) {
        if (!message.has_member ("content")) {
            return "";
        }

        var content = message.get_object_member ("content");

        switch (content.get_string_member ("@type")) {
            case "messageText":
                return one_line (content.get_object_member ("text").get_string_member ("text"));

            // An emoji sent on its own is its own content type, not text.
            case "messageAnimatedEmoji":
                return content.has_member ("emoji") ? content.get_string_member ("emoji") : "Emoji";
            case "messageDice":
                return content.has_member ("emoji") ? content.get_string_member ("emoji") : "Dice";

            case "messagePhoto":
                return captioned (content, "Photo");
            case "messageVideo":
                return captioned (content, "Video");
            case "messageAnimation":
                return captioned (content, "GIF");
            case "messageAudio":
                return captioned (content, "Audio");
            case "messageDocument":
                return captioned (content, "File");
            case "messageVoiceNote":
                return captioned (content, "Voice message");
            case "messagePaidMedia":
                return captioned (content, "Paid media");

            case "messageSticker":
                return "Sticker";
            case "messageVideoNote":
                return "Video message";
            case "messageLocation":
            case "messageVenue":
                return "Location";
            case "messageContact":
                return "Contact";
            case "messagePoll":
                return "Poll";
            case "messageCall":
                return "Call";
            case "messageStory":
                return "Story";
            case "messageGame":
                return "Game";

            case "messageExpiredPhoto":
            case "messageExpiredVideo":
            case "messageExpiredVideoNote":
                return "Expired";
            case "messageUnsupported":
                return "Unsupported message";

            case "messageChatJoinByLink":
            case "messageChatAddMembers":
                return "Joined the chat";
            case "messageChatDeleteMember":
                return "Left the chat";
            case "messagePinMessage":
                return "Pinned a message";
            case "messageChatChangeTitle":
                return "Changed the title";
            case "messageChatChangePhoto":
                return "Changed the photo";

            default:
                return "Message";
        }
    }

    // Real clients show the caption rather than the media label when there is
    // one, so a photo with text reads like the message it is.
    private static string captioned (Json.Object content, string label) {
        if (!content.has_member ("caption")) {
            return label;
        }

        var caption = one_line (content.get_object_member ("caption").get_string_member ("text"));
        return caption == "" ? label : caption;
    }

    private static string one_line (string text) {
        return text.replace ("\n", " ").strip ();
    }
}
