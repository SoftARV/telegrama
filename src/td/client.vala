namespace Telegrama.Td {

public errordomain ClientError {
	CLOSED,
	REMOTE,
}

public delegate void RequestBuilder (Json.Builder builder);

public class Client : Object {

	public signal void update (string type, Json.Object body);

	private class Pending {
		public SourceFunc resume;
		public Json.Object? response = null;
	}

	private int client_id = 0;
	private Thread<void>? receiver = null;
	private MainContext context = MainContext.ref_thread_default ();
	private AsyncQueue<Json.Object> inbox = new AsyncQueue<Json.Object> ();
	private HashTable<string, Pending> pending = new HashTable<string, Pending> (str_hash, str_equal);
	private int running = 0;
	private int drain_scheduled = 0;
	private uint64 next_extra = 0;

	public void start () {
		if (!AtomicInt.compare_and_exchange (ref running, 0, 1))
			return;

		TDJson.execute ("""{"@type":"setLogVerbosityLevel","new_verbosity_level":1}""");
		client_id = TDJson.create_client_id ();
		receiver = new Thread<void> ("td-receive", receive_loop);
	}

	public async void stop () {
		if (AtomicInt.get (ref running) == 0)
			return;

		var closed = false;
		var handler = update.connect ((type, body) => {
			if (type != "updateAuthorizationState")
				return;
			var state = body.get_object_member ("authorization_state");
			if (state != null && state.get_string_member ("@type") == "authorizationStateClosed")
				closed = true;
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
		if (AtomicInt.get (ref running) == 0)
			throw new ClientError.CLOSED (@"$method: client is not running");

		var extra = (++next_extra).to_string ();

		var builder = new Json.Builder ();
		builder.begin_object ();
		builder.set_member_name ("@type");
		builder.add_string_value (method);
		builder.set_member_name ("@extra");
		builder.add_string_value (extra);
		if (build != null)
			build (builder);
		builder.end_object ();

		var generator = new Json.Generator ();
		generator.set_root (builder.get_root ());

		var waiting = new Pending ();
		waiting.resume = request.callback;
		pending.insert (extra, waiting);

		TDJson.send (client_id, generator.to_data (null));
		yield;

		pending.remove (extra);

		if (waiting.response == null)
			throw new ClientError.CLOSED (@"$method: client closed before a reply arrived");

		Json.Object response = waiting.response;
		if (response.get_string_member ("@type") == "error")
			throw new ClientError.REMOTE ("%s: %s (%d)".printf (
				method,
				response.get_string_member ("message"),
				(int) response.get_int_member ("code")));

		return response;
	}

	private void receive_loop () {
		var parser = new Json.Parser ();

		while (AtomicInt.get (ref running) == 1) {
			unowned string? raw = TDJson.receive (1.0);
			if (raw == null)
				continue;

			try {
				parser.load_from_data (raw);
			} catch (Error e) {
				warning ("unparsable JSON from TDLib: %s", e.message);
				continue;
			}

			unowned Json.Node? root = parser.get_root ();
			if (root == null || root.get_node_type () != Json.NodeType.OBJECT)
				continue;

			// Ref'd out of the parser so the next load cannot free it under us.
			Json.Object body = root.get_object ();
			var last = is_closed (body);
			inbox.push (body);

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
			if (last)
				break;
		}
	}

	private static bool is_closed (Json.Object body) {
		if (!body.has_member ("@type") || body.get_string_member ("@type") != "updateAuthorizationState")
			return false;
		if (!body.has_member ("authorization_state"))
			return false;

		var state = body.get_object_member ("authorization_state");
		return state != null
			&& state.has_member ("@type")
			&& state.get_string_member ("@type") == "authorizationStateClosed";
	}

	private void drain () {
		AtomicInt.set (ref drain_scheduled, 0);

		Json.Object? body = null;
		while ((body = inbox.try_pop ()) != null)
			dispatch (body);
	}

	private void dispatch (Json.Object body) {
		if (!body.has_member ("@type"))
			return;

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

}
