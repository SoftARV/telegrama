namespace Telegrama.Keyring {

    private const string ATTR_PURPOSE = "purpose";
    private const string PURPOSE_DATABASE = "database-key";

    private static Secret.Schema schema () {
        var types = new HashTable<string, Secret.SchemaAttributeType> (str_hash, str_equal);
        types[ATTR_PURPOSE] = Secret.SchemaAttributeType.STRING;
        return new Secret.Schema.newv (Config.APP_ID, Secret.SchemaFlags.NONE, types);
    }

    private static HashTable<string, string> attributes () {
        var attrs = new HashTable<string, string> (str_hash, str_equal);
        attrs[ATTR_PURPOSE] = PURPOSE_DATABASE;
        return attrs;
    }

    // TDLib wants the key as base64 in JSON. An empty string means "no
    // encryption", which is the deliberate fallback when no keyring is running:
    // better an unencrypted local cache than an app that cannot start.
    public async string database_key () {
        try {
            var existing = yield Secret.password_lookupv (schema (), attributes (), null);
            if (existing != null && existing != "") {
                return existing;
            }
        } catch (Error e) {
            warning ("keyring unavailable, database will not be encrypted: %s", e.message);
            return "";
        }

        var key = generate ();
        if (key == "") {
            return "";
        }

        try {
            yield Secret.password_storev (schema (), attributes (), Secret.COLLECTION_DEFAULT,
                "Telegrama database key", key, null);
        } catch (Error e) {
            warning ("could not store database key: %s", e.message);
            return "";
        }

        return key;
    }

    // GLib's Random is a Mersenne Twister, which has no business generating an
    // encryption key, so this goes to the kernel instead.
    private static string generate () {
        var raw = new uint8[32];

        try {
            var stream = File.new_for_path ("/dev/urandom").read ();
            size_t read = 0;
            stream.read_all (raw, out read);
            if (read != raw.length) {
                warning ("short read from /dev/urandom, database will not be encrypted");
                return "";
            }
        } catch (Error e) {
            warning ("no entropy source, database will not be encrypted: %s", e.message);
            return "";
        }

        return Base64.encode (raw);
    }
}
