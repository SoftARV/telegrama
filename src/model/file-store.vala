// One place that asks TDLib for files. downloadFile answers with the file's
// current state, so a file already in the cache resolves without waiting;
// anything else is settled by the updateFile that follows.
public class Telegrama.FileStore : Object {

    // TDLib takes 1-32, higher first. Thumbnails are what the eye is waiting
    // for; a file someone actually clicked outranks them.
    public const int PRIORITY_THUMBNAIL = 16;
    public const int PRIORITY_OPENED = 32;

    public Td.Client client { get; construct; }

    private HashTable<int, string> done = new HashTable<int, string> (direct_hash, direct_equal);
    private GenericSet<int> asking = new GenericSet<int> (direct_hash, direct_equal);

    // Emitted for every file in flight, including ones nobody here asked for.
    public signal void settled (int file_id, string path);
    public signal void progress (int file_id, double fraction);

    public FileStore (Td.Client client) {
        Object (client: client);
    }

    construct {
        client.update.connect ((type, body) => {
            if (type == "updateFile") {
                absorb (body.get_object_member ("file"));
            }
        });
    }

    public static int id_of (Json.Object file) {
        return (int) file.get_int_member ("id");
    }

    public static string local_path (Json.Object file) {
        if (!file.has_member ("local")) {
            return "";
        }

        var local = file.get_object_member ("local");
        return local.get_boolean_member ("is_downloading_completed")
            ? local.get_string_member ("path")
            : "";
    }

    public string cached (int file_id) {
        var path = done.lookup (file_id);
        return path == null ? "" : path;
    }

    // For callers holding the file object: TDLib states there whether the bytes
    // are already on disk, which saves the round trip entirely.
    public async string fetch_file (Json.Object file, int priority = PRIORITY_THUMBNAIL) {
        var path = local_path (file);
        if (path != "") {
            done.insert (id_of (file), path);
            return path;
        }

        return yield fetch (id_of (file), priority);
    }

    // Empty when the file cannot be had. Two callers asking at once both send
    // the request, which TDLib folds into one download.
    public async string fetch (int file_id, int priority = PRIORITY_THUMBNAIL) {
        if (file_id == 0) {
            return "";
        }

        var known = cached (file_id);
        if (known != "") {
            return known;
        }

        // A second caller for the same file waits on the first one's download
        // rather than asking again.
        if (!asking.contains (file_id)) {
            asking.add (file_id);

            Json.Object answer;
            try {
                answer = yield client.request ("downloadFile", (b) => {
                    b.set_member_name ("file_id");
                    b.add_int_value (file_id);
                    b.set_member_name ("priority");
                    b.add_int_value (priority);
                    b.set_member_name ("offset");
                    b.add_int_value (0);
                    b.set_member_name ("limit");
                    b.add_int_value (0);
                    b.set_member_name ("synchronous");
                    b.add_boolean_value (false);
                });
            } catch (Td.ClientError e) {
                asking.remove (file_id);
                return "";
            }

            var path = local_path (answer);
            if (path != "") {
                asking.remove (file_id);
                done.insert (file_id, path);
                return path;
            }
        }

        // Not here yet: wait for the update that says it landed. Resuming on
        // an idle rather than in the handler keeps the coroutine out of the
        // middle of update dispatch.
        string result = "";
        ulong handler = 0;
        SourceFunc resume = fetch.callback;

        handler = settled.connect ((id, landed) => {
            if (id != file_id) {
                return;
            }
            result = landed;
            SignalHandler.disconnect (this, handler);
            handler = 0;
            Idle.add ((owned) resume);
        });

        yield;

        if (handler != 0) {
            SignalHandler.disconnect (this, handler);
        }

        return result;
    }

    public void cancel (int file_id) {
        client.send ("cancelDownloadFile", (b) => {
            b.set_member_name ("file_id");
            b.add_int_value (file_id);
            b.set_member_name ("only_if_pending");
            b.add_boolean_value (false);
        });
    }

    private void absorb (Json.Object file) {
        var id = id_of (file);
        var local = file.get_object_member ("local");

        if (local.get_boolean_member ("is_downloading_completed")) {
            var path = local.get_string_member ("path");
            asking.remove (id);
            done.insert (id, path);
            settled (id, path);
            return;
        }

        if (!local.get_boolean_member ("is_downloading_active")) {
            // Neither finished nor still going: nothing further will arrive.
            if (asking.remove (id)) {
                settled (id, "");
            }
            return;
        }

        var total = file.get_int_member ("size");
        if (total <= 0) {
            total = file.get_int_member ("expected_size");
        }
        if (total > 0) {
            progress (id, (double) local.get_int_member ("downloaded_size") / total);
        }
    }
}
