public errordomain Telegrama.Td.ClientError {
    CLOSED,
    NOT_FOUND,
    REMOTE,
}

public delegate void Telegrama.Td.RequestBuilder (Json.Builder builder);

public class Telegrama.Td.Client : Object {

    public signal void update (string type, Json.Object body);

    // Distinguishes our own shutdown from TDLib closing under us, which is what
    // a remote logout looks like.
    public bool stopping { get; private set; default = false; }

    private class Pending {
        public SourceFunc resume;
        public Json.Object? response = null;
    }

    private int client_id = 0;
    private Thread<void>? receiver = null;
    private MainContext context = MainContext.ref_thread_default ();
    private AsyncQueue<Json.Node> inbox = new AsyncQueue<Json.Node> ();
    private HashTable<string, Pending> pending = new HashTable<string, Pending> (str_hash, str_equal);
    private int running = 0;
    private int drain_scheduled = 0;
    private uint64 next_extra = 0;

    public void start () {
        if (!AtomicInt.compare_and_exchange (ref running, 0, 1)) {
            return;
        }

        // A previous client may have closed on its own; its thread has left the
        // loop already but still needs joining before we replace it.
        if (receiver != null) {
            receiver.join ();
            receiver = null;
        }

        TDJson.execute ("""{"@type":"setLogVerbosityLevel","new_verbosity_level":1}""");
        client_id = TDJson.create_client_id ();
        receiver = new Thread<void> ("td-receive", receive_loop);
    }

    public async void stop () {
        if (AtomicInt.get (ref running) == 0) {
            return;
        }

        stopping = true;

        var closed = false;
        var handler = update.connect ((type, body) => {
            if (type != "updateAuthorizationState") {
                return;
            }
            var state = body.get_object_member ("authorization_state");
            if (state != null && state.get_string_member ("@type") == "authorizationStateClosed") {
                closed = true;
            }
        });

        TDJson.send (client_id, """{"@type":"close"}""");

        // close only starts the teardown; TDLib confirms with authorizationStateClosed.
        for (var i = 0; i < 60 && !closed; i++) {
            Timeout.add (50, stop.callback);
            yield;
        }

        SignalHandler.disconnect (this, handler);
        AtomicInt.set (ref running, 0);

        if (receiver != null) {
            receiver.join ();
            receiver = null;
        }
    }

    public async Json.Object request (string method, owned RequestBuilder? build = null) throws ClientError {
        if (AtomicInt.get (ref running) == 0) {
            throw new ClientError.CLOSED (@"$method: client is not running");
        }

        var extra = (++next_extra).to_string ();

        var builder = new Json.Builder ();
        builder.begin_object ();
        builder.set_member_name ("@type");
        builder.add_string_value (method);
        builder.set_member_name ("@extra");
        builder.add_string_value (extra);
        if (build != null) {
            build (builder);
        }
        builder.end_object ();

        var generator = new Json.Generator ();
        generator.set_root (builder.get_root ());

        var waiting = new Pending ();
        waiting.resume = request.callback;
        pending.insert (extra, waiting);

        TDJson.send (client_id, generator.to_data (null));
        yield;

        pending.remove (extra);

        if (waiting.response == null) {
            throw new ClientError.CLOSED (@"$method: client closed before a reply arrived");
        }

        Json.Object response = waiting.response;
        if (response.get_string_member ("@type") == "error") {
            var code = (int) response.get_int_member ("code");
            var detail = "%s: %s (%d)".printf (method, response.get_string_member ("message"), code);

            // 404 is how TDLib says "nothing more to give", which several callers
            // treat as a normal end rather than a failure.
            if (code == 404) {
                throw new ClientError.NOT_FOUND (detail);
            }
            throw new ClientError.REMOTE (detail);
        }

        return response;
    }

    // Fire-and-forget for requests whose only useful outcome is an update.
    public void send (string method, owned RequestBuilder? build = null) {
        request.begin (method, (owned) build, (obj, res) => {
            try {
                request.end (res);
            } catch (ClientError e) {
                warning ("%s", e.message);
            }
        });
    }

    private void receive_loop () {
        var parser = new Json.Parser ();

        while (AtomicInt.get (ref running) == 1) {
            unowned string? raw = TDJson.receive (1.0);
            if (raw == null) {
                continue;
            }

            try {
                parser.load_from_data (raw);
            } catch (Error e) {
                warning ("unparsable JSON from TDLib: %s", e.message);
                continue;
            }

            // json-glib refcounts with grefcount, which is deliberately NOT
            // atomic, so one object must never be referenced from two threads.
            // steal_root hands the whole tree over: the parser lets go, nothing
            // here takes a reference of its own, and the main thread ends up its
            // only owner. Taking an owned Json.Object anywhere in this loop
            // would put the counter back in the hands of two threads.
            var root = parser.steal_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                continue;
            }

            var last = is_closed (root.get_object ());
            inbox.push ((owned) root);

            if (AtomicInt.compare_and_exchange (ref drain_scheduled, 0, 1)) {
                var source = new IdleSource ();
                source.set_callback (() => {
                    drain ();
                    return Source.REMOVE;
                });
                source.attach (context);
            }

            // Nothing follows authorizationStateClosed, and staying parked in
            // receive would cost stop() a full timeout before the thread joins.
            // TDLib needs a fresh instance after this, so clear running and let
            // start() build one.
            if (last) {
                AtomicInt.set (ref running, 0);
                break;
            }
        }
    }

    private static bool is_closed (Json.Object body) {
        if (!body.has_member ("@type") || body.get_string_member ("@type") != "updateAuthorizationState") {
            return false;
        }
        if (!body.has_member ("authorization_state")) {
            return false;
        }

        var state = body.get_object_member ("authorization_state");
        return state != null
            && state.has_member ("@type")
            && state.get_string_member ("@type") == "authorizationStateClosed";
    }

    private void drain () {
        AtomicInt.set (ref drain_scheduled, 0);

        Json.Node? node = null;
        while ((node = inbox.try_pop ()) != null) {
            unowned Json.Object body = node.get_object ();

            // Before dispatch, not after: dispatching a close can start a new
            // client, and its first request must not be caught by this sweep.
            if (is_closed (body)) {
                fail_pending ();
            }
            dispatch (body);
        }
    }

    // A closed client answers nothing further, so anything still waiting would
    // hang for the life of the process.
    private void fail_pending () {
        // Reference every entry before clearing: get_values only borrows, and
        // remove_all frees the values out from under the list.
        var waiting = new GenericArray<Pending> ();
        foreach (unowned Pending p in pending.get_values ()) {
            waiting.add (p);
        }
        pending.remove_all ();

        for (var i = 0; i < waiting.length; i++) {
            waiting[i].response = null;
            waiting[i].resume ();
        }
    }

    private void dispatch (Json.Object body) {
        if (!body.has_member ("@type")) {
            return;
        }

        var type = body.get_string_member ("@type");

        if (body.has_member ("@extra")) {
            var waiting = pending.lookup (body.get_string_member ("@extra"));
            if (waiting != null) {
                waiting.response = body;
                waiting.resume ();
                return;
            }
        }

        update (type, body);
    }
}
