public class Telegrama.Chat : Object {

    public int64 id { get; construct; }

    public string title { get; set; default = ""; }
    public string preview { get; set; default = ""; }
    public int64 date { get; set; default = 0; }
    public int unread_count { get; set; default = 0; }
    public bool is_pinned { get; set; default = false; }

    // Private chats have one other participant, so naming them above every
    // bubble is noise.
    public bool is_group { get; set; default = false; }

    // Everything at or below this id has been read by the other side.
    public int64 last_read_outbox { get; set; default = 0; }

    // Position in the main chat list. Zero means the chat is not in it.
    public int64 order { get; set; default = 0; }

    // Null until the avatar has been downloaded, which is what makes the
    // Adw.Avatar fall back to initials.
    public Gdk.Paintable? photo { get; set; default = null; }

    // Kept alongside the texture: notifications take a GIcon, which wants a
    // file rather than something already decoded.
    public string photo_path { get; set; default = ""; }

    // Unsent text, kept by Telegram and shared with the user's other clients.
    public string draft { get; set; default = ""; }

    public Chat (int64 id) {
        Object (id: id);
    }
}
