public class Telegrama.Chat : Object {

    public int64 id { get; construct; }

    public string title { get; set; default = ""; }
    public string preview { get; set; default = ""; }
    public int64 date { get; set; default = 0; }
    public int unread_count { get; set; default = 0; }
    public bool is_pinned { get; set; default = false; }

    // Position in the main chat list. Zero means the chat is not in it.
    public int64 order { get; set; default = 0; }

    public Chat (int64 id) {
        Object (id: id);
    }
}
