// Names for message senders. TDLib sends users as updates rather than inline
// with the messages that mention them, so this fills in as they arrive.
public class Telegrama.UserStore : Object {

    public signal void learned (int64 user_id, string name);

    private HashTable<string, string> names = new HashTable<string, string> (str_hash, str_equal);

    public UserStore (Td.Client client) {
        client.update.connect ((type, body) => {
            if (type == "updateUser") {
                remember (body.get_object_member ("user"));
            }
        });
    }

    public string name_for (int64 user_id) {
        var known = names.lookup (user_id.to_string ());
        return known ?? "";
    }

    private void remember (Json.Object user) {
        var id = user.get_int_member ("id");

        var first = user.get_string_member ("first_name");
        var last = user.get_string_member ("last_name");
        var name = last == "" ? first : @"$first $last";

        if (name.strip () == "") {
            return;
        }

        names.insert (id.to_string (), name);
        learned (id, name);
    }
}
