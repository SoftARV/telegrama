// Decoded previews, bounded. Rows come and go as the history scrolls, so the
// textures cannot hang off the messages themselves: a long chat would keep
// every picture it had ever shown.
public class Telegrama.MediaLoader : Object {

    private const uint CAP = 64;

    public FileStore files { get; construct; }

    private HashTable<int, Gdk.Texture> textures =
        new HashTable<int, Gdk.Texture> (direct_hash, direct_equal);
    private Queue<int> order = new Queue<int> ();

    public MediaLoader (FileStore files) {
        Object (files: files);
    }

    public Gdk.Texture? cached (int file_id) {
        var texture = textures.lookup (file_id);
        if (texture != null) {
            order.remove (file_id);
            order.push_head (file_id);
        }
        return texture;
    }

    public async Gdk.Texture? load (Media media) {
        var file_id = media.preview_id;
        if (file_id == 0) {
            return null;
        }

        var have = cached (file_id);
        if (have != null) {
            return have;
        }

        var path = media.preview_path;
        if (path == "") {
            path = yield files.fetch (file_id, FileStore.PRIORITY_THUMBNAIL);
        }
        if (path == "") {
            return null;
        }

        // Another caller may have decoded it while this one waited.
        have = cached (file_id);
        if (have != null) {
            return have;
        }

        Gdk.Texture texture;
        try {
            texture = Gdk.Texture.from_filename (path);
        } catch (Error e) {
            warning ("could not decode %s: %s", path, e.message);
            return null;
        }

        keep (file_id, texture);
        return texture;
    }

    private void keep (int file_id, Gdk.Texture texture) {
        textures.insert (file_id, texture);
        order.push_head (file_id);

        while (order.get_length () > CAP) {
            textures.remove (order.pop_tail ());
        }
    }
}
